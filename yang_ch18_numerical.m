function res = yang_ch18_numerical(cfg)
% YANG_CH18_NUMERICAL  Chapters 18 & 19 - numerical instability analysis.
%   Ch.18 Habiballah & Dubois, Eqs (1)-(55)
%   Ch.19 Grenda, Venkateswaran & Merkle, Eqs (1)-(26)
%
% Ch.18: two-phase source terms for a spray-combustion solver - droplet
% diameter (Eq 15), vaporization mass loss (Eqs 16-18), Arrhenius chemistry
% (Eqs 19,20), drag with the Re-dependent Cd (Eqs 24-26), energy exchange
% (Eqs 27-33), lateral-flow sources (Eqs 34-40), the Helmholtz-resonator
% boundary (Eqs 41-44), wall friction (Eqs 45-47), the bomb disturbance
% (Eqs 48,49) and the Deardorff SGS viscosity (Eqs 9,10).
%
% Ch.19: the Euler flux vectors Q,E,F,G and source H (Eqs 1-3), the
% Priem-Heidmann vaporization rate (Eq 6), droplet heating (Eqs 7,8), and
% the linearised perturbation response coefficients alpha*, beta*, phi
% (Eqs 14-22) used to close a linear stability sweep.
%
%   res = yang_ch18_numerical(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

gam = cfg.gamma_gas;
R   = cfg.r_gas;
rho = cfg.p_chamber/(R*cfg.t_gas);
c   = sqrt(gam*R*cfg.t_gas);

%% ======================================================================
%  CH.18 - SPRAY SOURCE TERMS
%% ======================================================================
% Eq (15): D_m = (6 rho_m /(pi rho_L n_m))^(1/3)
sp.d_drop = (6*cfg.rho_liq_bulk/(pi*cfg.rho_liq*cfg.n_drop))^(1/3);
sp.vol_drop  = pi/6*sp.d_drop^3;
sp.mass_drop = cfg.rho_liq*sp.vol_drop;

% Eq (25): Re_m = rho D_m |V - V_m| / mu
sp.v_slip = cfg.u_gas - cfg.u_drop;
sp.re_m   = rho*sp.d_drop*abs(sp.v_slip)/cfg.mu_gas;
% Eq (26): Cd = 12/Re (1 + 0.15 Re^0.687) for Re <= 1000, else 0.22
if sp.re_m <= 1000
    sp.cd = 12/sp.re_m*(1 + 0.15*sp.re_m^0.687);
else
    sp.cd = 0.22;
end
% Eq (24): f_m = (pi/8) mu n_m D_m Cd Re_m (V - V_m)
sp.f_drag = pi/8*cfg.mu_gas*cfg.n_drop*sp.d_drop*sp.cd*sp.re_m*sp.v_slip;
sp.f_gas  = -sp.f_drag;                                   % Eq (23)

% Eqs (52),(53): generalized vaporization law and rate
Di = cfg.d_drop_init;  Kv = cfg.k_vap;  av = cfg.alpha_vap;
sp.d2_current = max(Di^2 - (Kv*cfg.t_resid)^av*(Di^2)^(1-av), 0);
arg = max(Di^2 - sp.d2_current, eps);
sp.mdot_drop = cfg.rho_liq*pi*sqrt(sp.d2_current)/4 ...
               *(Di^2)^((1-av)/av)*av*Kv*arg^((av-1)/av);
if ~isfinite(sp.mdot_drop); sp.mdot_drop = 0; end
% Eqs (16)-(18): mass sources
sp.W_liq_vap = -cfg.n_drop*sp.mdot_drop;                  % Eq (16)
sp.W_gas_vap = -sp.W_liq_vap;                             % Eq (17)

% Eqs (21),(22): momentum sources from vaporization
sp.S_mx_liq = sp.W_liq_vap*cfg.u_drop;
sp.S_x_gas  = -sp.S_mx_liq;
% Eqs (30)-(33): energy sources
sp.h_interface = cfg.h_latent + cfg.cp_liq*(cfg.t_surf - cfg.t_liq_init);
sp.S_E_vap = -sp.W_liq_vap*(sp.h_interface - R*cfg.t_surf + cfg.u_drop^2/2);
sp.S_e_vap = -sp.W_liq_vap*(sp.h_interface - R*cfg.t_surf ...
                            + 0.5*sp.v_slip^2);           % Eq (32)
sp.S_e_drag= sp.f_drag*sp.v_slip;                         % Eq (33)
% Eq (29): heat feedback to the droplet
sp.phi_heat = -sp.W_liq_vap*(cfg.cp_liq*(cfg.t_surf - cfg.t_liq_init) ...
                             + cfg.h_latent);

% Eqs (19),(20): Arrhenius chemistry.  Defaults are the H2/O2 set of Eq (54);
% Eq (55) gives the Viking (UDMH/NTO) set.
sp.omega_dot = cfg.arr_CC*exp(-cfg.arr_TA/cfg.t_gas) ...
               *(cfg.rho_ox_sp/cfg.mw_ox)^cfg.arr_a1 ...
               *(cfg.rho_fu_sp/cfg.mw_fu)^cfg.arr_a2;
sp.W_k_comb  = -cfg.nu_stoich*cfg.mw_ox*sp.omega_dot;     % Eq (20)
sp.heat_release = sp.omega_dot*cfg.q_reaction;

% Eqs (9),(10): Deardorff subgrid viscosity and turbulent transport
S_mag = sqrt(2*cfg.dudx^2 + 2*cfg.dvdy^2 + (cfg.dudy + cfg.dvdx)^2);
sp.mu_turb  = rho*cfg.c_deardorff*cfg.dx_cell^2*S_mag;    % Eq (9)
sp.k_turb   = sp.mu_turb*cfg.cp_gas/cfg.pr_turb;          % Eq (10a)
sp.d_turb   = sp.mu_turb/(rho*cfg.sc_turb);               % Eq (10b)

% Eqs (34)-(40): lateral-flow (baffle/film) source terms
lat.W_mass = cfg.mdot_lateral/cfg.v_cell;                 % Eq (34)
lat.S_x    = cfg.mdot_lateral*cfg.u_lateral/cfg.v_cell;   % Eq (35)
lat.S_y    = 0;
lat.S_e    = cfg.mdot_lateral/cfg.v_cell ...
             *(cfg.h_lateral + cfg.u_lateral^2/2 ...
               - cfg.u_gas*cfg.u_lateral + cfg.u_gas^2/2);% Eq (36)
lat.W_k    = cfg.y_k_lateral*cfg.mdot_lateral/cfg.v_cell; % Eq (37)
lat.S_n    = 1/cfg.v_cell*6*cfg.mdot_liq_lateral ...
             /(pi*cfg.d_lateral^3*cfg.rho_liq);           % Eq (40)

% Eqs (45)-(47): wall friction closure
wall.re     = rho*cfg.u_tangential*cfg.delta_wall/cfg.mu_gas;   % Eq (47)
Rw          = wall.re;
wall.beta_f = 1 + 0.0236*((Rw/80)+(Rw/240)^2)/(1+(Rw/80)+(Rw/240)^2) ...
              *(Rw/4)^0.811;                                     % Eq (46)
wall.tau_w  = wall.beta_f*cfg.mu_gas*cfg.u_tangential/cfg.delta_wall; % Eq (45)

% Eqs (41)-(44): Helmholtz-resonator boundary condition
hr.l_eff = cfg.l_orifice + 0.96*sqrt(cfg.a_orifice) ...
           *(0.5 - 0.7*sqrt(cfg.a_orifice/cfg.a_cavity));        % Eq (43)
hr.R0    = cfg.gamma_resist*rho*cfg.u_orifice;                   % Eq (44)
hr.omega0= sqrt(c^2*cfg.a_orifice/(cfg.v_cavity*hr.l_eff));
hr.f0    = hr.omega0/(2*pi);
hr.zeta  = (hr.R0/rho)/(2*hr.l_eff*hr.omega0);

% Eqs (48),(49): bomb disturbance field
xg = linspace(0, cfg.len_chamber, 80);
yg = linspace(0, cfg.rad_chamber, 40);
[Xg, Yg] = meshgrid(xg, yg);
bomb.x = Xg;  bomb.y = Yg;
bomb.p_shaped  = cfg.p_chamber*(1 + cfg.amp_bomb ...
                 *sin(cfg.beta1_bomb*Xg + cfg.beta2_bomb) ...
                 .*sin(cfg.gamma1_bomb*Yg + cfg.gamma2_bomb));   % Eq (48)
bomb.p_uniform = cfg.p_chamber*(1 + cfg.amp_bomb);               % Eq (49)
bomb.overpressure_pct = cfg.amp_bomb*100;

%% ======================================================================
%  CH.19 - CFD FLUX VECTORS AND LINEARISED RESPONSE
%% ======================================================================
% Eqs (2),(3): conserved-variable and flux vectors in cylindrical form
u = cfg.u_gas;  v = cfg.v_gas;  w = cfg.w_gas;  p = cfg.p_chamber;
e = p/(gam-1) + 0.5*rho*(u^2 + v^2 + w^2);
cfd.Q = [rho; rho*u; rho*v; rho*w; e];
cfd.E = [rho*u; rho*u^2 + p; rho*u*v; rho*u*w; (e+p)*u];
cfd.F = [rho*v; rho*u*v; rho*v^2 + p; rho*v*w; (e+p)*v];
cfd.G = [rho*w; rho*u*w; rho*v*w; rho*w^2 + p; (e+p)*w];
cfd.H_gas = [0; 0; p + rho*w^2; -rho*v*w; 0];                    % Eq (3)
cfd.H_liq = [sp.W_gas_vap; sp.S_x_gas; 0; 0; sp.S_e_vap + sp.S_e_drag];

% Eq (6): Priem-Heidmann vaporization rate
%   mdot = pi d rho D Sh ln[p/(p - p_vs)]
cfd.b_number = log(p/max(p - cfg.p_vapor_surf, eps));
cfd.mdot_vap = pi*sp.d_drop*rho*cfg.diff_binary*cfg.sherwood*cfd.b_number;
% Eq (7): heat feedback with the Stefan correction
E_st = cfd.mdot_vap*cfg.cp_vapor/(pi*sp.d_drop*cfg.k_gas*cfg.nusselt);
cfd.q_vap = cfd.mdot_vap*cfg.cp_vapor*(cfg.t_gas - cfg.t_surf)/(exp(E_st)-1);
% Eq (8): droplet temperature rate
cfd.dTd_dt = (cfd.q_vap - cfd.mdot_vap*cfg.h_latent)/(sp.mass_drop*cfg.cp_liq);

% Eqs (14)-(22): linearised response coefficients over a frequency sweep
f = cfg.f_sweep(:).';   w_ang = 2*pi*f;
% Eq (21): phi = mdot Tl/qv dlam/dTl + mdot lam/qv delta_v - delta_q
%                + i omega m_d cp_l Tl/qv
phi = cfg.mdot_bar*cfg.t_surf/cfg.q_bar*cfg.dlam_dT ...
      + cfg.mdot_bar*cfg.h_latent/cfg.q_bar*cfg.delta_v - cfg.delta_q ...
      + 1i*w_ang*sp.mass_drop*cfg.cp_liq*cfg.t_surf/cfg.q_bar;
% Eq (19),(20): the complex pressure and velocity sensitivities
cfd.alpha_star = cfg.alpha_v + cfg.delta_v./phi ...
                 .*(cfg.alpha_q - cfg.h_latent*cfg.mdot_bar/cfg.q_bar*cfg.alpha_v);
cfd.beta_star  = cfg.beta_v  + cfg.delta_v./phi ...
                 .*(cfg.beta_q  - cfg.h_latent*cfg.mdot_bar/cfg.q_bar*cfg.beta_v);
% Eq (22): combined coefficient including the droplet-size response (Eq 14)
cfd.alpha_total = cfd.alpha_star - 3*cfg.alpha_d + cfg.alpha_inj;
cfd.freq_hz  = f;
cfd.phi      = phi;
cfd.resp_mag = abs(cfd.alpha_total);
cfd.resp_deg = angle(cfd.alpha_total)*180/pi;
% The mode is driven where the in-phase part of the response is positive.
cfd.driving  = real(cfd.alpha_total) > 0;
[cfd.resp_peak, ip] = max(real(cfd.alpha_total));
cfd.f_peak   = f(ip);

% Eq (13): analytical axial solution  p' ~ (P1 e^{-k+ x} + P2 e^{-k- x}) J_mu
kp = 1i*w_ang/c./(1 + cfg.mach_mean);
km = -1i*w_ang/c./(1 - cfg.mach_mean);
cfd.k_plus  = kp;
cfd.k_minus = km;

res.cfg = cfg;  res.spray = sp;  res.lateral = lat;  res.wall = wall;
res.resonator = hr;  res.bomb = bomb;  res.cfd = cfd;
res.rho_gas = rho;   res.a_sound = c;
end

% =========================================================================
function c = default_cfg()
c.gamma_gas = 1.22;  c.r_gas = 8314/7.5;
c.p_chamber = 20.7e6;  c.t_gas = 3400;
c.len_chamber = 0.50;  c.rad_chamber = 0.15;
c.u_gas = 120;  c.v_gas = 5;  c.w_gas = 0;
c.mu_gas = 9.0e-5;  c.k_gas = 0.40;  c.cp_gas = 3500;
c.rho_liq = 1140;   c.rho_liq_bulk = 20;  c.n_drop = 2.5e9;
c.u_drop = 40;      c.cp_liq = 1700;  c.h_latent = 213e3;
c.t_surf = 130;     c.t_liq_init = 90;
c.d_drop_init = 1.2e-4;  c.k_vap = 6.0e-7;  c.alpha_vap = 0.85;
c.t_resid = 2.0e-3;
c.arr_CC = 1.2e6;  c.arr_TA = 800;  c.arr_a1 = 1;  c.arr_a2 = 1;
c.rho_ox_sp = 3.0;  c.rho_fu_sp = 0.5;
c.mw_ox = 32;  c.mw_fu = 2;  c.nu_stoich = 1;
% omega_dot comes out in kmol/m^3/s, so the heat of reaction must be per
% kmol of fuel burned (H2/O2: ~2.4e8 J/kmol), not per kg.
c.q_reaction = 2.4e8;
c.c_deardorff = 0.10;  c.dx_cell = 2.0e-3;
c.dudx = 500;  c.dvdy = 200;  c.dudy = 800;  c.dvdx = 300;
c.pr_turb = 0.9;  c.sc_turb = 0.9;
c.mdot_lateral = 0.5;  c.v_cell = 8.0e-9;  c.u_lateral = 30;
c.h_lateral = 4.0e5;  c.y_k_lateral = 0.2;
c.mdot_liq_lateral = 0.1;  c.d_lateral = 1.0e-4;
c.u_tangential = 60;  c.delta_wall = 5.0e-4;
c.l_orifice = 0.010;  c.a_orifice = 7.85e-5;  c.a_cavity = 1.0e-3;
c.v_cavity = 5.0e-5;  c.gamma_resist = 0.5;  c.u_orifice = 20;
c.amp_bomb = 0.20;
c.beta1_bomb = 2*pi/0.5;  c.beta2_bomb = 0;
c.gamma1_bomb = pi/0.15;  c.gamma2_bomb = 0;
c.p_vapor_surf = 3.0e6;  c.diff_binary = 3.0e-5;
c.sherwood = 2.5;  c.nusselt = 2.5;  c.cp_vapor = 1000;
c.f_sweep = linspace(200, 8000, 600);
c.mdot_bar = 1.0e-6;  c.q_bar = 2.0;  c.dlam_dT = -500;
c.alpha_v = 0.6;  c.beta_v = 0.3;  c.delta_v = 0.8;
c.alpha_q = 0.5;  c.beta_q = 0.4;  c.delta_q = 0.9;
c.alpha_d = 0.10; c.alpha_inj = 0.20;
c.mach_mean = 0.12;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
