function res = yang_ch13_nonlinear(cfg)
% YANG_CH13_NONLINEAR  Chapter 13 - nonlinear acoustic waves in combustion
% chambers (Yang, Wicker & Yoon, 1995), Eqs (1)-(52).
%
% Integrates the two-mode amplitude/phase system obtained by time-averaging
% the modal equation d2(eta_n)/dt2 + omega_n^2 eta_n = F_n with second-order
% gasdynamic coupling (Eq 19).  Four combustion-response laws are supported:
%
%   'quadratic'  Eqs (20)-(22)   mdot_b' ~ p', u', p'^2, u'^2, p'u'
%   'abs_u'      Eqs (36)-(38)   mdot_b' ~ |u'|
%   'p_abs_u'    Eqs (39)-(41)   mdot_b' ~ p'|u'|
%   'third'      Eqs (46)-(48)   third-order gasdynamics
%   'mean_flow'  Eqs (50)-(52)   mean-flow interaction, ubar = (ue/L) x
%
% Limit-cycle amplitudes follow Eqs (24),(25) with the existence condition
% alpha_1 alpha_2 < 0 (Eq 26); modal energies use Eqs (30)-(32).
%
%   res = yang_ch13_nonlinear(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

a1 = cfg.alpha_1;  a2 = cfg.alpha_2;
A1 = cfg.a_coup;   B1 = cfg.b_coup;
dth = -2*cfg.theta_1 + cfg.theta_2 + cfg.omega_detune;

%% ===== analytical limit cycle, Eqs (24)-(26) ==========================
% r_10 = sqrt{ (a1 a2)/(A1 B1) [1 + ((2th1-th2-Om1)/(2a1+a2))^2] }
% r_20 = -(a1/A1) sqrt{ 1 + (...)^2 }
brack = 1 + (-dth/(2*a1 + a2))^2;
lc.exists = (a1*a2) < 0;                                 % Eq (26)
if lc.exists
    lc.r1 = sqrt( (a1*a2)/(A1*B1) * brack );
    lc.r2 = -(a1/A1)*sqrt(brack);
else
    lc.r1 = NaN;  lc.r2 = NaN;
end
lc.r1 = real(lc.r1);  lc.r2 = real(lc.r2);
lc.bracket = brack;
% Eq (27)-(29): phases drift linearly, the cycle is periodic at omega_1+nu_1
lc.nu_1     = dth/3;
lc.psi_star = atan2(-dth, (2*a1 + a2));

%% ===== time integration of the amplitude system ========================
tspan = [0 cfg.t_final];
y0    = [cfg.r1_init; cfg.r2_init; cfg.psi_init];
odef  = @(t,y) amplitude_rhs(t, y, cfg, a1, a2, A1, B1, dth);
% The averaged system is stiff: the coupling coefficients are O(1e4) while
% the growth rates are O(1e2), and the 1/r terms sharpen further whenever an
% amplitude approaches its floor.  ode15s handles that without the step-size
% collapse ode45 suffers on the |u'| and mean-flow response models.
% The second-order averaged equations have no saturating term, so for some
% coefficient sets (notably the |u'| and mean-flow responses) the amplitude
% genuinely diverges in finite time rather than settling on a limit cycle.
% That is a limitation of the truncation, not a solver problem, so stop
% cleanly at a physical ceiling and report it instead of grinding the step
% size down to zero.  NonNegative is not used: the RHS already floors both
% amplitudes, and the solver's projection chatters against a state that
% wants to go negative.
opts  = odeset('RelTol',1e-8,'AbsTol',1e-12, ...
               'Events', @(t,y) blowup_event(t, y, cfg.r_ceiling));
[t,y] = ode15s(odef, tspan, y0, opts);
y(:,1:2) = max(y(:,1:2), 0);
diverged = t(end) < cfg.t_final*(1 - 1e-6);

sim.time  = t;
sim.r1    = y(:,1);
sim.r2    = y(:,2);
sim.psi   = y(:,3);
sim.model = cfg.model;

% Eq (17),(18): reconstruct the modal amplitudes and their rates
om1 = cfg.omega_1;  om2 = 2*om1;
sim.phi1  = cumtrapz(t, zeros(size(t)));            % phi_n absorbed into psi
sim.eta1  = sim.r1.*sin(om1*t);
sim.eta2  = sim.r2.*sin(om2*t + sim.psi);
sim.eta1_dot = sim.r1.*om1.*cos(om1*t);
sim.eta2_dot = sim.r2.*om2.*cos(om2*t + sim.psi);

% Eq (3): p'(r,t) = p_bar SUM eta_n(t) psi_n(r); evaluate at the head end
sim.p_head = cfg.p_mean*(sim.eta1*1 + sim.eta2*1);
sim.p_mid  = cfg.p_mean*(sim.eta1*cos(pi/2) + sim.eta2*cos(pi));

% Eqs (30)-(32): modal energies and their rates
sim.E1 = (sim.r1.^2*cfg.e_norm1^2)/(2*cfg.gamma_gas^2);
sim.E2 = (sim.r2.^2*cfg.e_norm2^2)/(2*cfg.gamma_gas^2);
sim.dE1 = cfg.e_norm1^2/cfg.gamma_gas^2 ...
          *(a1*sim.r1.^2 + A1*sim.r1.^2.*sim.r2.*cos(sim.psi));
sim.dE2 = cfg.e_norm2^2/cfg.gamma_gas^2 ...
          *(a2*sim.r2.^2 + B1*sim.r1.^2.*sim.r2.*cos(sim.psi));
sim.E_total = sim.E1 + sim.E2;

% Steady-state (limit cycle) values from the tail of the integration
ntail = max(1, round(0.2*numel(t)));
sim.r1_final = mean(sim.r1(end-ntail+1:end));
sim.r2_final = mean(sim.r2(end-ntail+1:end));
sim.psi_final= mean(sim.psi(end-ntail+1:end));
sim.p_amp_pct= 100*max(abs(sim.p_head(end-ntail+1:end)))/cfg.p_mean;
sim.drift    = std(sim.r1(end-ntail+1:end))/max(sim.r1_final,eps);
sim.diverged = diverged;
sim.converged= ~diverged && sim.drift < 1e-2;
if diverged
    sim.note = sprintf(['amplitude reached the %.2f ceiling at t = %.4f s: ' ...
        'the second-order truncation has no saturating term for these ' ...
        'coefficients, so add the third-order terms (model ''third'') ' ...
        'to obtain a bounded limit cycle'], cfg.r_ceiling, t(end));
else
    sim.note = '';
end

%% ===== triggering study: amplitude threshold for the limit cycle =======
% Scan initial amplitudes to find the smallest disturbance that reaches the
% nonlinear limit cycle rather than decaying (Eq 26 regime).
r0 = cfg.trigger_scan;
final_amp = zeros(size(r0));
for k = 1:numel(r0)
    [~, yk] = ode15s(odef, [0 cfg.t_final/2], ...
                     [r0(k); r0(k)/4; cfg.psi_init], opts);
    final_amp(k) = min(max(yk(end,1), 0), cfg.r_ceiling);
end
trig.r_init   = r0;
trig.r_final  = final_amp;
grew          = final_amp > 1.5*r0(:)';
if any(grew)
    trig.threshold = r0(find(grew, 1, 'first'));
else
    trig.threshold = NaN;
end
trig.linearly_unstable = a1 > 0;

%% ===== mode-shape catalogue, Eqs (10)-(13) ============================
% Rectangular:  psi = cos(l pi x/L) cos(m pi y/W) cos(s pi z/H)
%               k^2 = pi^2[(l/L)^2 + (m/W)^2 + (s/H)^2]
% Cylindrical:  psi = cos(l pi x/L) J_m(kappa r) {cos,sin}(m theta)
%               k^2 = (l pi/L)^2 + kappa^2
x = linspace(0, cfg.len_chamber, 200);
shp.x       = x;
shp.psi_1L  = cos(1*pi*x/cfg.len_chamber);
shp.psi_2L  = cos(2*pi*x/cfg.len_chamber);
shp.k_1L    = pi/cfg.len_chamber;
shp.k_2L    = 2*pi/cfg.len_chamber;
% Eq (49): the assumed linear mean-flow profile ubar = (u_e/L) x
shp.u_mean  = (cfg.u_exit/cfg.len_chamber)*x;

res.cfg = cfg;  res.limit_cycle = lc;  res.sim = sim;
res.trigger = trig;  res.shapes = shp;
end

% =========================================================================
function [v, term, dir] = blowup_event(~, y, ceiling)
% Stop the integration when either modal amplitude reaches the physical
% ceiling (a fraction of the mean pressure).  Beyond that the averaging
% assumption behind these equations no longer holds anyway.
v    = ceiling - max(y(1), y(2));
term = 1;
dir  = -1;
end

% =========================================================================
function dy = amplitude_rhs(~, y, cfg, a1, a2, A1, B1, dth)
% Right-hand sides of the averaged amplitude/phase equations.  Which set is
% used depends on the assumed combustion response (Eq 33 / Eq 35).
% The averaged phase equation contains r1^2/r2 and r2/r1, which are singular
% when either amplitude collapses.  That singularity is an artefact of the
% averaging, not physics: once a mode's amplitude is negligible its phase is
% undefined.  Floor both amplitudes so the integration stays well posed.
r1 = max(y(1), cfg.r_floor);
r2 = max(y(2), cfg.r_floor);
ps = y(3);
c  = cos(ps);   s = sin(ps);   c2 = cos(2*ps);  s2 = sin(2*ps);

switch lower(cfg.model)
    case 'quadratic'                              % Eqs (20)-(22)
        dr1 = a1*r1 + A1*r1*r2*c;
        dr2 = a2*r2 + B1*r1^2*c;
        dps = dth - (2*A1*r2 + B1*r1^2/r2)*s;

    case 'abs_u'                                  % Eqs (36)-(38)
        ca = cfg.c_1a;
        dr1 = a1*r1 + A1*r1*r2*c - 4*ca*r2*s;
        dr2 = a2*r2 + B1*r1^2*c  -   ca*r1*s;
        dps = dth - (2*A1*r2 + B1*r1^2/r2)*s ...
                  - (16*r2/r1 + r1/r2)*ca*c;

    case 'p_abs_u'                                % Eqs (39)-(41)
        cb = cfg.c_1b;
        dr1 = a1*r1 + A1*r1*r2*c - cb*(16/9)*(r1^2 - (4/25)*r2^2*c2);
        dr2 = a2*r2 + B1*r1^2*c  - cb*(16/15)*(4 + (7/15)*c2)*r1*r2;
        dps = dth - (2*A1*r2 + B1*r1^2/r2)*s ...
                  - cb*s2*(2*(16/15)^2*r2^2/r1 - 7*(4/15)^2*r1);

    case 'third'                                  % Eqs (46)-(48)
        b1 = cfg.beta_3rd;
        dr1 = a1*r1 + A1*r1*r2*c;
        dr2 = a2*r2 + B1*r1^2*c;
        dps = dth - (2*A1*r2 + B1*r1^2/r2)*s + 2*b1*(r2^2 - r1^2);

    case 'mean_flow'                              % Eqs (50)-(52)
        bm = cfg.beta_mean;
        dr1 = a1*r1 + r1*r2*(A1*c - 7*bm*s);
        dr2 = a2*r2 + r1^2*(B1*c + bm*s);
        dps = dth - (2*A1*r2 + B1*r1^2/r2)*s + bm*(-14*r2 + r1^2/r2)*c;

    otherwise
        error('yang_ch13:model', 'unknown model "%s"', cfg.model);
end
% Cap the phase rate for the same reason: near the floor the 1/r terms can
% still produce an arbitrarily stiff derivative.
dps = max(min(dps, cfg.dpsi_max), -cfg.dpsi_max);
dy = [dr1; dr2; dps];
end

% =========================================================================
function c = default_cfg()
c.model      = 'quadratic';
c.alpha_1    =  120;      % s^-1  mode 1 linear growth (driving)
c.alpha_2    = -260;      % s^-1  mode 2 linear damping
c.a_coup     = -1.2e4;    % Eq (20) coupling coefficient a_1
c.b_coup     =  1.0e4;    % Eq (21) coupling coefficient b_1
c.theta_1    = 0;   c.theta_2 = 0;   c.omega_detune = 0;
c.c_1a       = 50;        % |u'| response coefficient   (Eq 36)
c.c_1b       = 2.0e3;     % p'|u'| response coefficient (Eq 39)
c.beta_3rd   = 1.0e3;     % third-order coefficient     (Eq 48)
c.beta_mean  = 800;       % mean-flow coefficient       (Eq 50)
c.omega_1    = 2*pi*2400;
c.r1_init    = 1e-3;  c.r2_init = 1e-4;  c.psi_init = 0.1;
c.t_final    = 0.08;
c.p_mean     = 20.7e6;
c.gamma_gas  = 1.22;
c.e_norm1    = 1.0;   c.e_norm2 = 1.0;
c.len_chamber= 0.5;   c.u_exit  = 300;
c.trigger_scan = logspace(-5, -1, 25);
c.r_floor    = 1e-9;      % amplitude floor for the averaged equations
c.dpsi_max   = 1e7;       % cap on the phase rate (rad/s)
c.r_ceiling  = 1.0;       % stop if eta_n reaches 100% of the mean pressure
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
