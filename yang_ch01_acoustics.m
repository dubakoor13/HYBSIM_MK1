function res = yang_ch01_acoustics(cfg)
% YANG_CH01_ACOUSTICS  Culick & Yang (1995) Ch.1 - Overview of Combustion
% Instabilities. Implements Eqs. (1)-(89): the forced-oscillator model,
% two-phase conservation equations, modal expansion of the wave equation,
% growth constants, the Rayleigh criterion, time-lag combustion response,
% nozzle admittance damping and the delayed-feedback control model.
%
%   res = yang_ch01_acoustics(cfg)
%
% cfg fields (all optional, defaults shown in local default_cfg):
%   geom_type    'cylindrical' | 'rectangular'
%   len_chamber  chamber length            [m]
%   rad_chamber  chamber radius            [m]
%   p_mean       mean chamber pressure     [Pa]
%   t_mean       mean chamber temperature  [K]
%   gamma_gas    ratio of specific heats   [-]
%   r_gas        specific gas constant     [J/kg/K]
%   n_axial      # axial mode indices to scan
%   n_radial     # radial mode indices to scan
%   n_tang       # tangential mode indices to scan
%   tau_lag      combustion time lag       [s]
%   n_interact   Crocco interaction index  [-]
%   q_amp        heat-release amplitude    [W/m^3]
%   adm_nozzle   real part of nozzle admittance [-]
%   q_factor     acoustic quality factor   [-]
%
% Returns res with fields: cfg, gas, modes, growth, rayleigh, timelag,
% control, oscillator.

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

%% --- normal modes and mean gas state ------------------------------------
% Eqs (36),(28),(45),(46),(49).  Built by the shared mode solver so Ch.1,
% Ch.14 and Ch.15 use one mode set, one set of norms E_n^2 and one driving
% overlap integral.
[modes, gas] = yang_chamber_modes(cfg);

%% --- linear growth constants: Eqs (56),(57),(70),(72),(75) ---------------
% Evaluated by the shared growth budget, so Ch.1 and Ch.15 cannot disagree
% about the same terms.  Ch.1's default combustion model is the prescribed
% time-lagged heat release of Eqs (73)-(76); pass comb_model = 'crocco' to
% use the pressure-coupled n-tau law of Eqs (77)-(85) instead.
growth = struct([]);
for im = 1:numel(modes)
    b = yang_growth_budget(modes(im), gas, cfg);
    growth(im).mode_id     = b.mode_id; %#ok<*AGROW>
    growth(im).omega       = b.omega;
    growth(im).freq_hz     = b.freq0_hz;
    growth(im).alpha_drive = b.alpha_drive;
    growth(im).alpha_noz   = b.alpha_nozzle;
    growth(im).alpha_cav   = b.alpha_cavity;
    growth(im).alpha_baf   = b.alpha_baffle;
    growth(im).alpha_vis   = b.alpha_visc;
    growth(im).alpha_damp  = b.alpha_damp;
    growth(im).alpha_net   = b.alpha_net;
    growth(im).stable      = b.stable;
    growth(im).omega_shift = b.omega_shift;      % Eqs (55),(56)
    growth(im).omega_act   = b.omega_act;
    growth(im).t_double    = b.t_double;         % Eqs (68),(69)
    growth(im).budget      = b;
end

%% --- Rayleigh criterion: Eqs (58)-(64) -----------------------------------
% Eq (62): model the fluctuating heat release as
%   Q' = Q0 psi_n (beta1 eta_n + beta2 eta_dot_n)
% Eq (63): the in-phase part integrates over one cycle to
%   dE_n = pi (gamma-1) beta1 omega_n Q0
rayleigh = struct([]);
for im = 1:numel(modes)
    om = modes(im).omega;
    b1 = cfg.beta_press;      % coefficient on eta_n     (in phase with p')
    b2 = cfg.beta_vel;        % coefficient on eta_dot_n (in phase with u')
    rayleigh(im).mode_id  = modes(im).mode_id;
    rayleigh(im).dE_cycle = pi * (gas.gamma - 1) * b1 * om * cfg.q_amp;
    % Eq (60): dE_n = 2 pi omega_n alpha_n  ->  alpha_n = dE_n/(2 pi omega_n)
    rayleigh(im).alpha    = rayleigh(im).dE_cycle / (2 * pi * om);
    % Rayleigh index: positive when p' and Q' are in phase.
    rayleigh(im).index    = b1;
    rayleigh(im).driving  = b1 > 0;
    rayleigh(im).beta_vel = b2;
end

%% --- Crocco n-tau response: Eqs (73)-(85) --------------------------------
% Eq (78): what_l = w_l_bar n (1 - exp(-i omega tau)) etahat_n psi_n
% Eq (79): real and imaginary parts.
timelag = struct([]);
for im = 1:numel(modes)
    om  = modes(im).omega;
    ph  = om * cfg.tau_lag;
    h   = cfg.n_interact * (1 - exp(-1i*ph));
    timelag(im).mode_id   = modes(im).mode_id;
    timelag(im).phase_rad = ph;
    timelag(im).resp      = h;
    timelag(im).resp_real = cfg.n_interact * (1 - cos(ph));   % Eq (79a)
    timelag(im).resp_imag = cfg.n_interact * sin(ph);         % Eq (79b)
    timelag(im).resp_mag  = abs(h);
    timelag(im).resp_deg  = angle(h) * 180/pi;
    % Eq (76): destabilising windows  0 < tau < pi/omega,
    %   3pi/(2 omega) < tau < 5pi/(2 omega), ...
    timelag(im).destab    = cos(ph) > 0;
    % Eq (84),(85): the neutral-stability locus in the (n, omega*tau) plane.
    timelag(im).n_sin     = cfg.n_interact * sin(ph);
    timelag(im).n_1mcos   = cfg.n_interact * (1 - cos(ph));
end

% Neutral-stability curve n(omega*tau) from Eq (85):
%   n (1 - cos(omega tau)) = C2/C1  ->  n = K/(1-cos(omega tau))
otau        = linspace(0.02, 2*pi-0.02, 400);
n_neutral   = cfg.damp_ratio_ntau ./ (1 - cos(otau));
n_neutral(n_neutral > 50) = NaN;   % clip the asymptotes for plotting
timelag_curve.omega_tau = otau;
timelag_curve.n_neutral = n_neutral;

%% --- simple oscillator + delayed feedback: Eqs (1)-(7),(86)-(89) ---------
% Eq (6): s^2 + 2(alpha - alpha_c)s + (omega0^2 - omega_c^2) = 0
om0    = modes(1).omega;
alp    = -growth(1).alpha_vis;             % passive damping
alp_c  = growth(1).alpha_drive;            % combustion "negative damping"
om_c2  = cfg.omega_c^2;
% Eq (7): roots
disc   = (om0^2 - om_c2) - (alp - alp_c)^2;
if disc >= 0
    roots_s = -(alp-alp_c) + [1i, -1i]*sqrt(disc);
else
    roots_s = -(alp-alp_c) + [1, -1]*sqrt(-disc);
end
oscillator.omega0     = om0;
oscillator.alpha      = alp;
oscillator.alpha_c    = alp_c;
oscillator.roots      = roots_s;
oscillator.growth     = -real(roots_s(1));
oscillator.stable     = real(roots_s(1)) < 0;

% Eqs (87)-(89): closed loop P(s) = G/(1-GQ)U, G = 1/(s^2+2as+w0^2),
%   Q = beta exp(-s tau).  Sweep the Nyquist locus of GQ.
f_hz  = logspace(log10(max(1,modes(1).freq_hz/50)), log10(modes(end).freq_hz*4), 600);
sj    = 1i*2*pi*f_hz;
G     = 1 ./ (sj.^2 + 2*alp*sj + om0^2);
Q     = cfg.beta_fb * exp(-sj * cfg.tau_lag);
loop  = G .* Q;
control.freq_hz   = f_hz;
control.open_loop = loop;
control.closed    = G ./ (1 - loop);
control.gain_db   = 20*log10(abs(control.closed));
% Eq (4): natural motions satisfy Q(s)G(s) - 1 = 0; encirclements of +1.
[~, ipk]          = max(abs(control.closed));
control.peak_hz   = f_hz(ipk);
control.peak_gain = abs(control.closed(ipk));
control.margin    = 1 - max(real(loop));

%% --- pack ----------------------------------------------------------------
res.cfg            = cfg;
res.gas            = gas;
res.modes          = modes;
res.growth         = growth;
res.rayleigh       = rayleigh;
res.timelag        = timelag;
res.timelag_curve  = timelag_curve;
res.oscillator     = oscillator;
res.control        = control;
[~, iw]            = max([growth.alpha_net]);
res.worst_mode     = growth(iw);
res.chamber_stable = all([growth.stable]);
end

% =========================================================================
function c = default_cfg()
c.geom_type   = 'cylindrical';
c.len_chamber = 0.50;      % m
c.rad_chamber = 0.15;      % m
c.wid_chamber = 0.30;      % m  (rectangular only)
c.hgt_chamber = 0.30;      % m  (rectangular only)
c.p_mean      = 20.7e6;    % Pa
c.t_mean      = 3600;      % K
c.gamma_gas   = 1.22;      % -
c.r_gas       = 8314/7.5;  % J/kg/K   (LOX/LH2 products, MW ~ 7.5)
c.cv_liquid   = 1700;      % J/kg/K   liquid specific heat
c.load_liquid = 0.05;      % rho_l/rho_g mass loading
c.n_axial     = 2;
c.n_tang      = 2;
c.n_radial    = 2;
c.n_modes_keep= 8;
c.tau_lag     = 1.0e-3;    % s   combustion time lag
c.n_interact  = 0.6;       % -   Crocco interaction index
c.q_amp       = 5.0e9;     % W/m^3 heat-release fluctuation amplitude
c.x_burn      = 0.08;      % m   centre of the burning zone from the face
c.w_burn      = 0.06;      % m   axial half-width of the burning zone
c.r_burn      = 0.10;      % m   radial half-width of the burning zone
c.adm_nozzle  = 0.02;      % -   Re{A} nozzle admittance
c.q_factor    = 50;        % -   acoustic quality factor
c.beta_press  = 0.30;      % -   Q' coefficient on eta_n      (Eq 62)
c.beta_vel    = 0.10;      % -   Q' coefficient on eta_dot_n  (Eq 62)
c.omega_c     = 0;         % rad/s combustion stiffness       (Eq 2)
c.beta_fb     = 2.0e5;     % feedback gain                    (Eq 89)
c.damp_ratio_ntau = 0.5;   % C2/C1 for the neutral curve      (Eq 85)
end

% =========================================================================
function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(a, f{i}); a.(f{i}) = d.(f{i}); end
end
end
