function g = yang_growth_budget(mode, gas, cfg)
% YANG_GROWTH_BUDGET  Linear growth constant of one acoustic mode.
%
% This is the single definition of the driving and damping terms, shared by
% Ch.1 (Culick & Yang) and Ch.15 (Mitchell) so the two cannot disagree about
% the same physics.  Every term is a rate in 1/s and they simply add:
%
%   alpha_net = alpha_drive + alpha_nozzle + alpha_cavity
%             + alpha_baffle + alpha_visc
%
%   g = yang_growth_budget(mode, gas, cfg)
%
% COMBUSTION DRIVING -- two models, selected by cfg.comb_model:
%
%  'prescribed' (Ch.1 Eqs 73-76).  The heat release is a prescribed
%    oscillation lagging the pressure by tau,  Q' = Qhat sin(omega(t-tau)).
%    Eq (75) gives
%       alpha = (gamma-1)/(2 p_bar E_n^2) INT(psi_n Qhat)dV cos(omega tau)
%    so driving alternates in sign with the lag: destabilising over
%    0 < tau < pi/omega, then 3pi/(2 omega) < tau < 5pi/(2 omega), ... (Eq 76).
%
%  'crocco' (Ch.1 Eqs 77-85, Ch.15 Eqs 32,33,45).  The burning rate responds
%    to pressure through the Crocco n-tau law,
%       w' = w_bar n [p'(t) - p'(t-tau)]/p_bar,
%    whose frequency response is n(1 - e^{-i omega tau}) (Eq 78).  Driving is
%    the IN-PHASE part of that response (Eq 79a),
%       Re = n(1 - cos(omega tau)),
%    which is non-negative for every lag -- this model is always destabilising
%    and is held in check only by the damping terms (Eqs 83,85).
%
%    NOTE: it is the real part that drives.  Taking the imaginary part
%    (equivalently multiplying by i before taking the real part) yields
%    n sin(omega tau), which is the FREQUENCY SHIFT of Eq (56), not the
%    growth rate.  Confusing the two flips the apparent stability of a mode.
%
% DAMPING -- all four terms are evaluated for both chapters:
%
%   nozzle   Eq (70)/(72) surface-admittance integral, with the short-nozzle
%            admittance of Ch.15 Eq (34), A = (gamma-1)/(2 gamma) M_e
%   cavity   the same integral applied to the acoustic cavities, using the
%            real part of the resonator admittance (Ch.15 Eqs 36-38)
%   baffle   acoustic boundary-layer dissipation on the blade surfaces
%            (Ch.15 Eqs 39-43)
%   visc     residual wall and bulk losses, expressed through a Q factor

cfg = merge_defaults(cfg, budget_default_cfg());

om   = mode.omega;
gam  = gas.gamma;
a    = gas.a_sound;
pbar = gas.p_mean;
En2  = mode.e_norm2;

%% --- combustion driving, Eq (75) or Eqs (83)/(45) -----------------------
% Common prefactor: the mode's share of the heat release, per unit of the
% heat-release amplitude.  Both models scale by this identically.
K = (gam - 1)/(2*pbar*En2) * cfg.q_amp * mode.int_psi;
phase = om*cfg.tau_lag;

switch lower(cfg.comb_model)
    case 'prescribed'
        g.alpha_drive = K*cos(phase);                        % Eq (75)
        % Eq (56): the out-of-phase part shifts the frequency
        g.omega_shift = -K*sin(phase)/(2*om);
    case 'crocco'
        resp = cfg.n_interact*(1 - exp(-1i*phase));          % Eq (78)
        g.alpha_drive = K*real(resp);                        % Eq (79a)
        g.omega_shift = -K*imag(resp)/(2*om);                % Eq (79b)/(56)
    otherwise
        error('yang_growth_budget:model', ...
              'comb_model must be ''prescribed'' or ''crocco''');
end
g.comb_model  = lower(cfg.comb_model);
g.drive_phase = phase;
% Eq (76): is this lag inside a destabilising window?
g.destabilising_lag = cos(phase) > 0;

%% --- nozzle damping, Eqs (70),(72) with Eq (34) -------------------------
% u'.n = A (a/p_bar) p'  ->  alpha = -gamma a/(2 E_n^2) Re{A} INT psi^2 dS
% Short-nozzle admittance, Ch.15 Eq (34):  A = (gamma-1)/(2 gamma) M_e
g.adm_nozzle    = (gam - 1)/(2*gam)*cfg.mach_exit;
g.alpha_nozzle  = -gam*a/(2*En2)*g.adm_nozzle*mode.int_psi2_exit;

%% --- cavity damping, same integral with the resonator admittance --------
% Eqs (36)-(38): beta = 1/K, K = K_R + i K_I with
%   K_R = Gamma rho_a a_a,   K_I = -gamma rho_a a_a cot(omega L_eff/a_a)
if cfg.area_cavity > 0
    K_R = cfg.gamma_resist*cfg.rho_cavity*cfg.a_cavity_sound;
    K_I = -gam*cfg.rho_cavity*cfg.a_cavity_sound ...
          *cot(om*cfg.l_eff_cavity/cfg.a_cavity_sound);
    beta_cav      = (K_R - 1i*K_I)/(K_R^2 + K_I^2);
    % Nondimensionalise to the same admittance convention as the nozzle
    g.adm_cavity  = real(beta_cav)*gas.rho_mean*a;
    g.alpha_cavity= -gam*a/(2*En2)*g.adm_cavity ...
                    *cfg.area_cavity*cfg.psi2_at_cavity;
    g.beta_cavity = beta_cav;
else
    g.adm_cavity  = 0;  g.alpha_cavity = 0;  g.beta_cavity = 0;
end

%% --- baffle blade dissipation, Eqs (39)-(43) ---------------------------
% Eq (42): E_dis = INT gamma sqrt(mu_eff omega/2) uhat^2 dS.  Dividing the
% dissipated power by twice the stored acoustic energy gives the rate
%   alpha = -(1/2) sqrt(nu_eff omega/2) (eps_u^2 A_blades / V_chamber)
% where eps_u is the tangential velocity at the blade in units of p'/(rho a).
area_blades = cfg.n_blades*cfg.area_blade;
if area_blades > 0
    nu_eff        = (cfg.mu_gas + cfg.mu_turb)/gas.rho_mean;
    g.alpha_baffle= -0.5*sqrt(nu_eff*om/2)*cfg.eps_u_blade^2 ...
                    *area_blades/gas.vol_chamber;
else
    g.alpha_baffle = 0;
end

%% --- residual losses through a Q factor --------------------------------
g.alpha_visc = -om/(2*cfg.q_factor);

%% --- totals ------------------------------------------------------------
g.alpha_damp = g.alpha_nozzle + g.alpha_cavity + g.alpha_baffle + g.alpha_visc;
g.alpha_net  = g.alpha_drive  + g.alpha_damp;
g.omega_act  = om + g.omega_shift;
g.freq_hz    = g.omega_act/(2*pi);
g.freq_shift_pct = 100*g.omega_shift/om;
g.stable     = g.alpha_net < 0;
g.mode_id    = mode.mode_id;
g.omega      = om;
g.freq0_hz   = om/(2*pi);
% Eqs (68),(69): the energy grows as exp(2 alpha t)
if g.alpha_net > 0
    g.t_double = log(2)/(2*g.alpha_net);
else
    g.t_double = Inf;
end
end

% =========================================================================
function c = budget_default_cfg()
c.comb_model  = 'prescribed';   % 'prescribed' (Eq 75) | 'crocco' (Eq 83)
c.q_amp       = 5.0e9;          % W/m^3  heat-release fluctuation amplitude
c.tau_lag     = 1.0e-3;         % s      combustion time lag
c.n_interact  = 0.6;            % -      Crocco interaction index
c.mach_exit   = 0.25;           % -      chamber-end Mach number
c.q_factor    = 50;             % -      residual-loss quality factor
% Acoustic cavities (set area_cavity = 0 to switch them off)
c.area_cavity     = 0;          % m^2  total cavity open area
c.psi2_at_cavity  = 1.0;        % -    psi_n^2 where the cavities sit
c.rho_cavity      = 1.6;        % kg/m^3
c.a_cavity_sound  = 1100;       % m/s
c.gamma_resist    = 0.5;        % -    orifice resistance factor
c.l_eff_cavity    = 0.045;      % m
% Baffles (set n_blades = 0 to switch them off)
c.n_blades    = 0;
c.area_blade  = 0.01;           % m^2 wetted area per blade
c.eps_u_blade = 1.0;            % -   tangential velocity at the blade
c.mu_gas      = 9.0e-5;         % Pa.s
c.mu_turb     = 1.0e-3;         % Pa.s
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
