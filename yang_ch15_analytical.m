function res = yang_ch15_analytical(cfg)
% YANG_CH15_ANALYTICAL  Chapters 15-17 - analytical instability models.
%   Ch.15 Mitchell,          Eqs (1)-(50)  Green's-function modal analysis
%   Ch.16 Kim,               Eqs (1)-(71)  turbulence effects, Landau-Stuart
%   Ch.17 Priem & Breisacher,Eqs (1)-(25)  combustion response profiles
%
% Ch.15 forms the complex eigenvalue omega = omega_R + i lambda from the
% frequency equation (Eq 28), with combustion driving (Eq 45), nozzle and
% cavity admittance damping (Eqs 34-38,44) and baffle blade dissipation
% (Eqs 39-43).  Ch.16 adds the turbulence-corrected dispersion relation
% (Eqs 63,66,67) and integrates the Landau-Stuart amplitude equation (Eq 70).
% Ch.17 evaluates the local and global combustion response (Eqs 23-25) with
% the admittance boundary conditions of Eqs (6)-(8).
%
%   res = yang_ch15_analytical(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

gam = cfg.gamma_gas;
c   = sqrt(gam*cfg.r_gas*cfg.t_chamber);
rho = cfg.p_chamber/(cfg.r_gas*cfg.t_chamber);

%% ======================================================================
%  CH.15 - MITCHELL GREEN'S-FUNCTION MODAL ANALYSIS
%% ======================================================================
% Eq (22): unperturbed eigenfunctions   lap(Om_N) + eta_N^2 Om_N = 0
% Eq (23): n . grad(Om_N) = 0
%
% These are the same hard-wall eigenfunctions as Ch.1 Eqs (45),(46), so the
% shared solver builds them -- including the norms E_n^2 and the driving
% overlap integral that the growth budget needs.  Using one mode set is what
% keeps Ch.1 and Ch.15 talking about the same modes at the same frequencies.
mcfg = cfg;
mcfg.rad_chamber  = cfg.r_chamber;
mcfg.p_mean       = cfg.p_chamber;
mcfg.t_mean       = cfg.t_chamber;
mcfg.n_modes_keep = cfg.n_keep;
[shared_modes, gas] = yang_chamber_modes(mcfg);

% Copy field by field: yang_growth_budget needs omega, e_norm2, int_psi,
% int_psi2_exit and mode_id, and Ch.15 adds Mitchell's own names on top.
mit.modes = struct([]);
for k = 1:numel(shared_modes)
    s = shared_modes(k);
    mit.modes(k).mode_id       = s.mode_id;
    mit.modes(k).omega         = s.omega;
    mit.modes(k).e_norm2       = s.e_norm2;
    mit.modes(k).int_psi       = s.int_psi;
    mit.modes(k).int_psi2_exit = s.int_psi2_exit;
    mit.modes(k).l = s.l;  mit.modes(k).m = s.m;  mit.modes(k).s = s.s;
    mit.modes(k).id        = sprintf('%dL%dT%dR', s.l, s.m, s.s);
    mit.modes(k).eta_N     = s.k_wave;         % Eq (22) eigenvalue
    mit.modes(k).omega0    = s.omega;
    mit.modes(k).freq0     = s.freq_hz;
    mit.modes(k).lambda_mn = s.alpha_ms;
end

% Eq (34): short-nozzle relation  u' = [(gamma-1)/(2 gamma)] M_e p'
mit.adm_nozzle_short = (gam-1)/(2*gam)*cfg.mach_exit;

% Eq (28)/(31): omega^2 = eta_N^2 + volume integral + surface integral.  The
% imaginary part is the growth rate lambda (Eq 7): the combustion driving of
% Eq (45) minus the admittance damping of Eq (44) and the baffle dissipation
% of Eqs (39)-(43).
%
% Those are exactly the terms Ch.1 evaluates in Eqs (70),(72),(75), so they
% are computed once, in yang_growth_budget, and shared.  Ch.15 differs from
% Ch.1 only in what it adds ON TOP: the Green's-function coupling between
% modes (Eqs 19-31) and, through Ch.16, the turbulence correction.
%
% Mitchell's combustion closure is the pressure-coupled n-tau law of Eq (33),
% Q' = Qbar n(1 - e^{-i omega tau}) p'/pbar, so 'crocco' is the default here
% while Ch.1 defaults to the prescribed heat release of Eq (75).  Set
% cfg.comb_model to force both onto the same closure.
bcfg = cfg;
if ~isfield(cfg,'comb_model') || isempty(cfg.comb_model)
    bcfg.comb_model = 'crocco';
end
for i = 1:numel(mit.modes)
    b = yang_growth_budget(mit.modes(i), gas, bcfg);
    mit.modes(i).drive_comb = b.alpha_drive;             % Eq (45)
    mit.modes(i).damp_nozzle= b.alpha_nozzle;            % Eq (44)
    mit.modes(i).damp_cavity= b.alpha_cavity;            % Eqs (36)-(38)
    mit.modes(i).damp_baffle= b.alpha_baffle;            % Eqs (39)-(43)
    mit.modes(i).damp_visc  = b.alpha_visc;
    mit.modes(i).lambda_base= b.alpha_net;
    mit.modes(i).omega_R    = b.omega_act;               % Eqs (55),(56)
    mit.modes(i).freq_hz    = b.freq_hz;
    mit.modes(i).beta_cav   = b.beta_cavity;
    mit.modes(i).budget     = b;
end

% Eqs (19)-(31): the Green's-function expansion couples each mode to every
% other one through G = SUM Om_N(r) Om_N(r0)/(omega^2 - eta_N^2).  For a
% well-separated mode this is a small correction on the single-mode budget
% above; it is what distinguishes Mitchell's result from Culick's.
for i = 1:numel(mit.modes)
    kn = mit.modes(i).eta_N;
    coupling = 0;
    for j = 1:numel(mit.modes)
        if j == i; continue; end
        kj = mit.modes(j).eta_N;
        % Eq (25): mu_N = 1/(omega^2 - eta_N^2) [volume - surface integrals]
        coupling = coupling + mit.modes(j).drive_comb/(kn^2 - kj^2)*kn^2;
    end
    mit.modes(i).coupling = cfg.green_coupling*coupling;
    mit.modes(i).lambda   = mit.modes(i).lambda_base + mit.modes(i).coupling;
    mit.modes(i).stable   = mit.modes(i).lambda < 0;
end
mit.stable = all([mit.modes.stable]);
[~, iw] = max([mit.modes.lambda]);
mit.worst = mit.modes(iw);
mit.comb_model = bcfg.comb_model;

% Eqs (46)-(50): traveling-wave (spinning) decomposition
%   Phi = Re[phi_1 e^{i alpha} + phi_2 e^{2 i alpha}],  alpha = theta + omega t
mit.travelling.alpha  = linspace(0, 2*pi, 200);
mit.travelling.phi_1  = cfg.eps_travel*cos(mit.travelling.alpha);
mit.travelling.phi_2  = 0;                                   % Eq (50)
mit.travelling.spin_frac = cfg.spin_fraction;

%% ======================================================================
%  CH.16 - KIM: TURBULENCE EFFECTS ON LINEAR STABILITY
%% ======================================================================
% Nondimensionalisation of Eqs (17)-(24)
u0 = cfg.mdot_total/(rho*cfg.area_chamber);
turb.u_0   = u0;
turb.a_0   = c;
turb.mach  = u0/c;                                            % Eq (18)
M = turb.mach;

for i = 1:numel(mit.modes)
    kn = mit.modes(i).eta_N;
    % Eq (67): Xi = sqrt(2 pi^3) k_n^2 INT G_n phi_n^2 dxi.  G_n is the
    % self-Green's function (Eq 55), dominated by the nearest neighbours.
    Gn = 0;
    for j = 1:numel(mit.modes)
        if j == i; continue; end
        kj = mit.modes(j).eta_N;
        Gn = Gn + 1/(kn^2 - kj^2);
    end
    Xi = sqrt(2*pi^3)*kn^2*Gn*cfg.mode_overlap;

    % Eq (63)/(66): dispersion relation
    %   k = k_n{1 + (1/2) eps^2 lc^3 Xi <rho1^2>}
    %       + M/(2 k_n) INT (R_v0 . grad phi_n) phi_n dxi
    %       + i M { (1/2) INT R_p0 phi_n^2 dxi + eps^2 lc^3 Xi <rho1 R_p1> }
    e2  = cfg.eps_turb^2;
    lc3 = cfg.corr_length^3;
    k_real = kn*(1 + 0.5*e2*lc3*Xi*cfg.rho1_var) ...
             + M/(2*kn)*cfg.Rv0_int;
    k_imag = M*(0.5*cfg.Rp0_int + e2*lc3*Xi*cfg.rho1_Rp1);

    turb.modes(i).id        = mit.modes(i).id;
    turb.modes(i).k_n       = kn;
    turb.modes(i).Xi        = Xi;
    turb.modes(i).k_real    = k_real;
    turb.modes(i).k_imag    = k_imag;
    turb.modes(i).freq_hz   = k_real*c/(2*pi);
    turb.modes(i).freq_shift= (k_real - kn)/kn;
    % Eq (71): lambda is the MEAN-FIELD growth rate and eta is the extra
    % contribution from turbulent inhomogeneity.  lambda is the same physical
    % quantity Ch.15 and Ch.1 already computed, so take it from the shared
    % budget rather than recomputing it from an abstract response integral --
    % otherwise the turbulence branch reports a growth rate that ignores the
    % nozzle, cavity and baffle damping entirely, and calls a stable chamber
    % unstable.
    turb.modes(i).lambda_lin= mit.modes(i).lambda;
    turb.modes(i).eta_turb  = e2*lc3*Xi*cfg.rho1_Rp1*M*c;
    turb.modes(i).growth    = turb.modes(i).lambda_lin + turb.modes(i).eta_turb;
    turb.modes(i).stable    = turb.modes(i).growth < 0;
    % How much the turbulence correction moved the answer
    turb.modes(i).eta_frac  = turb.modes(i).eta_turb ...
                              /max(abs(turb.modes(i).lambda_lin), eps);
    % Eq (57): assumed isotropic correlation C(r) = exp(-r^2/lc^2);
    % Eq (58) gives its integral sqrt(2 pi^3) lc^3.
    turb.modes(i).corr_integral = cfg.rho1_var*sqrt(2*pi^3)*lc3;
end

% Eq (70): Landau-Stuart amplitude equation  dA/dtau' = (lambda+eta)A - A^3
lam_ls = turb.modes(1).growth;
odef   = @(~,A) lam_ls*A - cfg.landau_cubic*A^3;
[tA, A]= ode45(odef, [0 cfg.t_landau], cfg.a_init);
turb.landau.time = tA;
turb.landau.amp  = A;
if lam_ls > 0
    turb.landau.a_sat = sqrt(lam_ls/cfg.landau_cubic);
else
    turb.landau.a_sat = 0;
end
turb.landau.saturates = lam_ls > 0;

%% ======================================================================
%  CH.17 - PRIEM & BREISACHER COMBUSTION RESPONSE
%% ======================================================================
% Eqs (6)-(8): admittance boundary conditions
%   v_r1 = gamma A_w p_1   (wall)
%   v_z1 = gamma A_f p_1   (injector face)
%   v_z1 = gamma A_n rho_1 (nozzle)
pri.adm_wall     = cfg.adm_wall;
pri.adm_injector = cfg.adm_injector;
pri.adm_nozzle   = cfg.adm_nozzle_priem;
% Eq (5)/(9): adiabatic ideal gas coupling  p_1 = gamma p_0/rho_0 * rho_1
pri.dp_drho      = gam*cfg.p_chamber/rho;

% Eq (23): global combustion response  R_p = (W1/W0)/(p1/p0)
f  = cfg.f_sweep(:).';   w = 2*pi*f;
% Model the local burning-rate response as an n-tau law plus a droplet lag.
ntau = cfg.n_interact*(1 - exp(-1i*w*cfg.tau_lag));
lag  = 1./(1 + 1i*w*cfg.tau_droplet);
pri.freq_hz = f;
pri.R_p     = ntau.*lag;
pri.R_p_real= real(pri.R_p);
pri.R_p_mag = abs(pri.R_p);
pri.R_p_deg = angle(pri.R_p)*180/pi;
[pri.R_max, ir] = max(pri.R_p_real);
pri.f_at_max    = f(ir);

% Eq (24): normalised local response  R_c = p0 SUM w_i p_i / (p_f1^2 SUM w_0)
zpos = linspace(0, cfg.len_chamber, cfg.n_stations);
% Assume a Gaussian axial burning-rate distribution and a 1L pressure shape.
w_local = exp(-((zpos - cfg.z_peak_burn)/cfg.z_width_burn).^2);
p_local = cos(pi*zpos/cfg.len_chamber);
pri.z_axis    = zpos;
pri.w_profile = w_local/max(w_local);
pri.p_profile = p_local;
pri.R_c_local = pri.R_max*pri.w_profile.*p_local;
pri.R_c_global= sum(pri.R_c_local.*p_local)/sum(pri.w_profile);
% Positive R_c means the burning distribution drives the mode.
pri.driving   = pri.R_c_global > 0;

res.cfg = cfg;  res.mitchell = mit;  res.turbulence = turb;  res.priem = pri;
res.stable = mit.stable && all([turb.modes.stable]);
end


% =========================================================================
function c = default_cfg()
c.gamma_gas = 1.22;   c.r_gas = 8314/7.5;
c.t_chamber = 3600;   c.p_chamber = 20.7e6;
c.r_chamber = 0.15;   c.len_chamber = 0.50;
c.area_chamber = pi*0.15^2;
c.vol_chamber  = pi*0.15^2*0.50;
c.mdot_total   = 100;
c.n_axial = 2;  c.n_tang = 2;  c.n_radial = 2;  c.n_keep = 6;
c.mach_exit = 0.25;
c.rho_cavity = 1.6;   c.a_cavity_sound = 1100;
c.gamma_resist = 0.5; c.l_eff_cavity = 0.045;
c.n_interact = 0.6;   c.tau_lag = 1.0e-3;
% Driving and damping parameters are those of yang_growth_budget, so Ch.1
% and Ch.15 read the same knobs.
c.q_amp    = 5.0e9;     % W/m^3  heat-release fluctuation amplitude
c.q_factor = 50;        % -      residual-loss quality factor
c.mu_gas   = 9.0e-5;    c.mu_turb = 1.0e-3;
% Damping hardware is OFF by default here, exactly as in yang_growth_budget,
% so Ch.1 and Ch.15 describe the same bare chamber and can be compared
% directly.  Turn baffles and cavities on for BOTH chapters at once via the
% driver, e.g. yang_instability_main('damping', struct('n_blades',6, ...
% 'area_cavity',2.0e-3)) -- enabling them in only one chapter is what made
% the two disagree in the first place.
c.n_blades = 0;  c.area_blade = 0.01;  c.eps_u_blade = 1.0;
c.area_cavity = 0;  c.psi2_at_cavity = 1.0;
c.eps_travel = 0.01;  c.spin_fraction = 0.5;
c.eps_turb = 0.20;    c.corr_length = 0.02;
c.rho1_var = 0.15;    c.rho1_Rp1 = 0.05;
c.Rv0_int  = 0.10;    c.Rp0_int  = 0.20;
c.mode_overlap = 0.5;
% Strength of the Green's-function inter-mode coupling of Eqs (19)-(31),
% the correction Mitchell's formulation adds on top of the single-mode
% growth budget that Ch.1 also evaluates.  Set to 0 to reproduce Ch.1
% exactly (given the same combustion closure).
c.green_coupling = 0.15;
% The Landau-Stuart transient needs ~ln(a_sat/a_0)/lambda to saturate, which
% is a few tenths of a second at these growth rates.
c.landau_cubic = 1.0e4;  c.a_init = 1e-4;  c.t_landau = 0.60;
c.adm_wall = 0.005;  c.adm_injector = 0.02;  c.adm_nozzle_priem = 0.08;
c.tau_droplet = 0.5e-3;
c.f_sweep = linspace(200, 8000, 600);
c.n_stations = 120;  c.z_peak_burn = 0.12;  c.z_width_burn = 0.08;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
