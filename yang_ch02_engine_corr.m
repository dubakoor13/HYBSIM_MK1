function res = yang_ch02_engine_corr(cfg)
% YANG_CH02_ENGINE_CORR  Chapters 2-5: engine-level empirical correlations.
%   Ch.2 Hulka & Hutt   - LOX/H2 instability phenomenology
%   Ch.3 Muss           - LOX/hydrocarbon instability phenomenology
%   Ch.4 Rubinsky       - RD-0110 amplitude-frequency characteristic
%   Ch.5 Hurlbert et al - earth-storable bipropellant chemistry & breakup
%
%   res = yang_ch02_engine_corr(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

%% ===== Ch.2 - LOX/H2 shear-coaxial injector metrics =====================
inj.vel_ratio = cfg.v_fuel / cfg.v_ox;                          % VR
inj.mom_ratio = (cfg.rho_fuel*cfg.v_fuel^2) ...
                / (cfg.rho_ox*cfg.v_ox^2);                      % J
inj.mass_ratio= cfg.mdot_ox / cfg.mdot_fuel;                    % O/F
inj.mdot_tot  = cfg.mdot_ox + cfg.mdot_fuel;
inj.dp_ratio_ox   = cfg.dp_ox   / cfg.p_chamber;                % dP/Pc
inj.dp_ratio_fuel = cfg.dp_fuel / cfg.p_chamber;
% Ch.2 Eq (1) - Reardon empirical time lag
%   tau = 0.165 * D_j^(1/2) * M_e^(-1/3) * beta_p^(-1)
inj.tau_reardon = 0.165 * cfg.d_jet^0.5 * cfg.mach_exit^(-1/3) / cfg.beta_prop;
inj.f_reardon   = 1/(2*inj.tau_reardon);

% Rule-of-thumb LOX/H2 stability screens used throughout Ch.2:
%   momentum ratio above ~10 and dP/Pc above ~15% are the usual stable side.
inj.screen_mom  = inj.mom_ratio     > 5;
inj.screen_dp   = inj.dp_ratio_fuel > 0.15;
inj.screen_vel  = inj.vel_ratio     > 8;

% Performance metrics referenced throughout Chs. 2-5 and 21
perf.c_star_actual = cfg.p_chamber * cfg.a_throat / inj.mdot_tot;   % Ch21 Eq(27)
perf.eta_c_star    = perf.c_star_actual / cfg.c_star_ideal;         % Ch21 Eq(1)
perf.isp           = cfg.thrust / (inj.mdot_tot * 9.80665);
perf.c_f           = cfg.thrust / (cfg.p_chamber * cfg.a_throat);

%% ===== damping-device tuning (Ch.2 & Ch.14 & Ch.21) =====================
% Helmholtz:    f = c/(2 pi) sqrt(S/(V (l + dl)))
% Quarter-wave: f = c/(4 (L + dl))
c_hot = sqrt(cfg.gamma_gas * cfg.r_gas * cfg.t_chamber);
cav.c_sound   = c_hot;
cav.dl_orifice= 0.85 * sqrt(cfg.a_orifice/pi);   % end correction ~0.85 a
cav.f_helm    = c_hot/(2*pi) * sqrt(cfg.a_orifice ...
                / (cfg.v_cavity * (cfg.l_orifice + cav.dl_orifice)));
cav.f_quarter = c_hot / (4*(cfg.l_quarter + cav.dl_orifice));

%% ===== Ch.3 - LOX/hydrocarbon impinging-jet atomization =================
% Ingebo drop size:
%   d = 0.123 D_j [ (rho_a/rho_l) (rho_a^2 D_j^2 u_rel^2)/(sigma mu_l) ]^-0.44
hc.d_ingebo = 0.123 * cfg.d_jet * ( (cfg.rho_gas/cfg.rho_liq) ...
              * (cfg.rho_gas^2*cfg.d_jet^2*cfg.u_rel^2) ...
              / (cfg.sigma_liq*cfg.mu_liq) )^(-0.44);
hc.we   = cfg.rho_liq * cfg.u_rel^2 * hc.d_ingebo / cfg.sigma_liq;   % Weber
hc.re   = cfg.rho_liq * cfg.u_rel   * hc.d_ingebo / cfg.mu_liq;      % Reynolds
hc.oh   = sqrt(hc.we) / hc.re;                                       % Ohnesorge
% Like-doublet peak response frequency scales with the jet residence D_j/V_j
hc.t_resid = cfg.d_jet / cfg.v_jet;
hc.f_max   = 1 / (2*pi*hc.t_resid);

%% ===== Ch.4 - RD-0110 amplitude-frequency characteristic ================
% K_A e^{i phi} = (p'/p_bar) / (mdot'/mdot_bar)
% Swept over a nondimensional frequency  omega R_k / C*
om   = 2*pi*cfg.f_sweep;
rd.freq_hz  = cfg.f_sweep;
rd.freq_nd  = om * cfg.r_chamber / perf.c_star_actual;      % omega R_k / C*
% Second-order resonant form for the injector-to-chamber gain.
om_r = 2*pi*cfg.f_resonant;
rd.gain_cplx = cfg.k_a_low ./ (1 - (om/om_r).^2 + 2i*cfg.zeta_rd*(om/om_r));
rd.k_a       = abs(rd.gain_cplx);
rd.phase_deg = angle(rd.gain_cplx)*180/pi;
[rd.k_a_max, ipk] = max(rd.k_a);
rd.f_at_max  = cfg.f_sweep(ipk);
% RD-0110 acceptance: gain must stay under the chamber loss line.
rd.acceptable = rd.k_a_max < cfg.k_a_limit;

%% ===== Ch.5 - storable propellants =====================================
% Henry's law for dissolved pressurant:  (ppm)_i = K_i P_i
st.ppm_dissolved = cfg.henry_k * cfg.p_partial;
% MMH nitrate formation chain (mass bookkeeping only):
%   CH3N2H3 + 2 NO2 -> 3 H2O + 2 N2 + CO
%   H2O     + 3 NO2 -> 2 HNO3 + NO
%   HNO3    + CH3N2H3 -> CH3N2H3.HNO3
st.reactions = { 'CH3N2H3 + 2 NO2 -> 3 H2O + 2 N2 + CO', ...
                 'H2O + 3 NO2 -> 2 HNO3 + NO', ...
                 'HNO3 + CH3N2H3 -> CH3N2H3.HNO3' };
% Eotvos number and the Eo_crit = 16 secondary-breakup threshold.
st.eotvos      = cfg.accel * cfg.rho_liq * cfg.d_drop^2 / cfg.sigma_liq;
st.eotvos_crit = 16;
st.breaks_up   = st.eotvos > st.eotvos_crit;
% Weber criterion, We_crit ~ 10 for low-viscosity liquids (Ch.9 Eq 10)
st.we_drop     = cfg.rho_gas * cfg.u_rel^2 * cfg.d_drop / cfg.sigma_liq;
st.we_crit     = 10;
st.we_breakup  = st.we_drop > st.we_crit;

res.cfg = cfg;  res.inj = inj;  res.perf = perf;  res.cav = cav;
res.hc  = hc;   res.rd  = rd;   res.storable = st;
end

% =========================================================================
function c = default_cfg()
c.p_chamber   = 20.7e6;   c.t_chamber = 3600;
c.gamma_gas   = 1.22;     c.r_gas     = 8314/7.5;
c.mdot_ox     = 75;       c.mdot_fuel = 25;
% Shear-coaxial element: slow dense LOX core, fast low-density H2 annulus.
c.v_ox        = 20;       c.v_fuel    = 700;      % m/s
c.rho_ox      = 1140;     c.rho_fuel  = 5.0;      % kg/m^3 (gaseous H2 side)
c.dp_ox       = 3.0e6;    c.dp_fuel   = 3.5e6;    % Pa
c.d_jet       = 2.0e-3;   c.v_jet     = 60;       % m, m/s
c.mach_exit   = 0.25;     c.beta_prop = 1.0;
% Throat sized from the ideal c*: A_t = mdot c* / Pc, so that the reported
% c* efficiency and Isp are self-consistent with the given mass flow.
c.c_star_ideal= 2350;                             % m/s
c.a_throat    = 100*2350/20.7e6;                  % m^2  (= 0.01135)
c.thrust      = 20.7e6*c.a_throat*1.72;           % N    (Cf = 1.72)
c.rho_gas     = 5.0;      c.rho_liq   = 1140;
c.mu_liq      = 2.0e-4;   c.sigma_liq = 0.013;
c.u_rel       = 250;      c.d_drop    = 1.0e-4;
c.accel       = 9.80665e3;
c.a_orifice   = 7.85e-5;  c.l_orifice = 0.010;
c.v_cavity    = 5.0e-5;   c.l_quarter = 0.040;
c.r_chamber   = 0.15;
c.f_sweep     = linspace(200, 6000, 400);
c.f_resonant  = 2400;     c.zeta_rd   = 0.08;
c.k_a_low     = 0.8;      c.k_a_limit = 3.0;
c.henry_k     = 1.2e-4;   c.p_partial = 1.5e6;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
