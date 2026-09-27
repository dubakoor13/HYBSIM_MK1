function res = yang_ch08_breakup(cfg)
% YANG_CH08_BREAKUP  Chapters 8 & 9 - impinging jets and spray breakup.
%   Ch.8 Anderson, Ryan & Santoro, Eqs (1)-(15) + cavitation number
%   Ch.9 Wu, Hsiang & Faeth,      Eqs (1)-(20)
%
% Covers the low/high Weber breakup radius, the Hasson-Peck sheet thickness,
% Squire's fastest-growing wave and growth rate, the viscous dispersion
% relation, ligament-to-drop conversion, the empirical impinging-jet drop
% size, and Faeth's secondary/turbulent-primary breakup regime map with the
% merged-breakup SMD correlations.
%
%   res = yang_ch08_breakup(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

rho_l = cfg.rho_liq;  rho_g = cfg.rho_gas;
sig   = cfg.sigma;    mu_l  = cfg.mu_liq;   mu_g = cfg.mu_gas;
d_j   = cfg.d_jet;    u_j   = cfg.u_jet;

%% ===== Ch.8 impinging-jet sheet ========================================
imp.we_jet = rho_l*u_j^2*d_j/sig;
imp.re_jet = rho_l*u_j*d_j/mu_l;
imp.oh     = mu_l/sqrt(rho_l*d_j*sig);

% Eq (1)/(2): breakup radius, low- and high-Weber branches
imp.r_b_low  = 0.167*d_j*imp.we_jet/2;
imp.r_b_high = 14.2*d_j*cfg.s_sheet^(-2/3)*imp.we_jet^(-1/3);
if imp.we_jet < cfg.we_transition
    imp.r_b = imp.r_b_low;  imp.regime = 'low-We (capillary)';
else
    imp.r_b = imp.r_b_high; imp.regime = 'high-We (aerodynamic)';
end

% Eq (5): Hasson-Peck sheet thickness
%   h = d_j^2 sin^3(theta) / [4 r (1 - cos(phi) cos(theta))^2]
th = cfg.theta_imping;  ph = cfg.phi_azimuth;
imp.h_sheet = d_j^2*sin(th)^3 ...
              /(4*imp.r_b*(1 - cos(ph)*cos(th))^2);

% Eq (6): Squire fastest-growing wavelength  lambda = 4 pi sigma/(rho_g U_s^2)
u_s = cfg.u_sheet;
imp.lambda_squire = 4*pi*sig/(rho_g*u_s^2);
imp.k_squire      = 2*pi/imp.lambda_squire;
% Eq (7): growth rate  beta_i = rho_g U_s^2 / (sqrt(2) rho_l h)
imp.beta_squire   = rho_g*u_s^2/(sqrt(2)*rho_l*imp.h_sheet);

% Eq (8): viscous dispersion relation, nondimensional
%   b^2 + (kh)^2/Re_s b + 2 s (kh)^2 [1/(s We_s) - 1/(kh)] = 0
kh   = imp.k_squire*imp.h_sheet;
re_s = rho_l*u_s*imp.h_sheet/mu_l;
we_s = rho_l*u_s^2*imp.h_sheet/sig;
s_r  = rho_g/rho_l;
A = 1;  B = kh^2/re_s;  C = 2*s_r*kh^2*(1/(s_r*we_s) - 1/kh);
disc = B^2 - 4*A*C;
imp.beta_visc = (-B + sqrt(complex(disc)))/(2*A);
imp.beta_visc_growth = real(imp.beta_visc);
imp.wave_unstable    = imp.beta_visc_growth > 0;

% Eq (9): ligament diameter  d_L = sqrt(4 h / k)
imp.d_ligament = sqrt(4*imp.h_sheet/imp.k_squire);
% Eq (10): drop from ligament, with the Weber viscous correction
imp.d_drop = (3*pi/sqrt(2))^(1/3)*imp.d_ligament ...
             *(1 + 3*mu_l/sqrt(rho_l*sig*imp.d_ligament))^(1/6);

% Eq (12): wave orientation  sin^2(Psi) = 2 sigma/(rho_l U_s^2 h)
arg = 2*sig/(rho_l*u_s^2*imp.h_sheet);
imp.psi_wave_deg = asin(min(1, sqrt(max(arg,0))))*180/pi;

% Eqs (13),(14): lateral spreading vs impingement force
imp.f_spread = rho_l*u_j^2*imp.h_sheet*imp.r_b*2;
imp.f_imping = rho_l*u_j^2*sin(th)*imp.h_sheet*imp.r_b*pi;
imp.force_ratio = imp.f_spread/imp.f_imping;

% Eq (15): empirical drop-size correlation
%   d_D/d_o = 2.217 [We_j f(theta)]^-0.354
f_th = 1 - cos(th);
imp.d_over_do = 2.217*(imp.we_jet*f_th)^(-0.354);
imp.d_empirical = imp.d_over_do*d_j;

% Cavitation number  K = (P_up - P_vap)/dP
imp.cav_number = (cfg.p_upstream - cfg.p_vapor)/cfg.dp_orifice;
imp.cavitating = imp.cav_number < cfg.cav_crit;

%% ===== Ch.9 secondary breakup =========================================
d0 = cfg.d_drop0;  u0 = cfg.u_rel;
sb.we    = rho_g*d0*u0^2/sig;                       % Weber
sb.re    = rho_g*d0*u0/mu_g;                        % Reynolds
sb.oh    = mu_l/sqrt(rho_l*d0*sig);                 % Ohnesorge
sb.eotvos= cfg.accel*rho_l*d0^2/sig;                % Eq (7)

% Eq (1): characteristic breakup time  t* = d0 sqrt(rho_l/rho_g)/u0
sb.t_star   = d0*sqrt(rho_l/rho_g)/u0;
sb.t_break  = 5.0*sb.t_star;                        % Eq (2) Ranger-Nicholls
% Eq (3): maximum deformation
sb.d_deform = d0*(1 + 0.19*sqrt(sb.we));
% Eq (10),(11): breakup criteria
sb.we_crit  = 10 + 40*sb.oh;                        % viscosity-shifted
sb.eo_crit  = 16;
sb.breaks   = sb.we > sb.we_crit;
sb.regime   = breakup_regime(sb.we, sb.oh);

% Eq (4): SMD after secondary breakup
%   rho_g SMD u0^2/sigma = 6.2 (rho_l/rho_g)^(1/4) [mu_l/(rho_l d0 u0)]^(1/2) We
lhs = 6.2*(rho_l/rho_g)^(1/4)*sqrt(mu_l/(rho_l*d0*u0))*sb.we;
sb.smd = lhs*sig/(rho_g*u0^2);

% Eqs (5),(6): core-drop velocity after breakup
sb.c_param = (3*cfg.cd_mean*5.0/4)*sqrt(rho_g/rho_l);
sb.u_core  = u0*(3*cfg.cd_mean*5.0/4)/(sqrt(rho_l/rho_g)*(1+3*sb.c_param));
% Eq (8): drop velocity correlation
%   u0/u_b - 1 = 2.7 [sqrt(rho_g/rho_l) d0/d]^(2/3)
sb.u_b = u0/(1 + 2.7*(sqrt(rho_g/rho_l)*d0/max(sb.smd,eps))^(2/3));

% Eq (9): liquid boundary-layer thickness  delta ~ 0.16 Re_x^(-1/7) x
re_x = rho_l*u_j*cfg.x_station/mu_l;
sb.delta_bl = 0.16*re_x^(-1/7)*cfg.x_station;

%% ===== Ch.9 turbulent primary breakup =================================
L = cfg.length_scale;   ubar = cfg.u_mean;   vbar = cfg.v_rms;
tb.we_lambda = rho_l*ubar^2*L/sig;
tb.re_lambda = rho_l*ubar*L/mu_l;

% Eq (12),(13): Rayleigh and secondary-breakup time scales
tb.tau_rayleigh = sqrt(rho_l*sb.smd^3/sig);
tb.tau_second   = sqrt(rho_l/rho_g)*sb.smd/u0;
% Eq (14): their ratio
tb.tau_ratio = sqrt(rho_g/rho_l)*(cfg.x_station*tb.we_lambda/L)^(1/3);

% Eq (15): SMD at the onset of turbulent primary breakup (implicit -> solve)
tb.smd_initial = solve_smd_initial(L, tb.we_lambda, rho_g/rho_l, ubar, vbar);
% Eq (16): axial distance to onset (implicit in the same bracket)
br = (1 + 0.04*(rho_g/rho_l)*(ubar/vbar)^2*(L/tb.smd_initial)^(2/3));
tb.x_onset = 2570*tb.we_lambda^(-0.63)*L/br^(9/10);

% Eq (17): merged primary + secondary breakup, empirical
grp = (cfg.x_station/L)^(1/3)*(rho_g/rho_l)^(3/4) ...
      *tb.we_lambda^(5/6)*tb.re_lambda^(-1/2);
tb.smd_merged_emp = 12.0*grp^1.17*sig/(rho_g*ubar^2);
% Eq (18): theoretical counterpart
tb.smd_merged_th  = 12.9*grp*sig/(rho_g*ubar^2);
% Eq (19): non-aerodynamic turbulent primary breakup
tb.smd_primary = 0.65*(cfg.x_station/(L*sqrt(tb.we_lambda)))^(2/3)*L;
% Eq (20): consistency relation between SMD_p and SMD
tb.smd_p_check = 3.91e-3*sqrt(rho_g/rho_l)*tb.re_lambda ...
                 *(sb.smd/L)^2*L;

res.cfg = cfg;  res.impinging = imp;  res.secondary = sb;  res.turbulent = tb;
end

% =========================================================================
function r = breakup_regime(we, oh)
% Standard secondary-breakup map (Ch.9 Sec. II), shifted for viscosity.
sh = 1 + 1.077*oh^1.6;
if     we < 11*sh;  r = 'vibrational';
elseif we < 35*sh;  r = 'bag';
elseif we < 80*sh;  r = 'bag-and-stamen';
elseif we < 350*sh; r = 'sheet-thinning';
else;               r = 'catastrophic';
end
end

% =========================================================================
function smd = solve_smd_initial(L, we_L, dens_rat, ubar, vbar)
% Eq (15): (SMD/L)[1 + 0.04 (rho_g/rho_l)(u/v)^2 (L/SMD)^(2/3)]^(3/5)
%          = 76 We_L^(-0.69).  Fixed-point iteration on SMD.
rhs = 76*we_L^(-0.69);
smd = rhs*L;                                   % first guess: bracket = 1
for k = 1:100
    br  = (1 + 0.04*dens_rat*(ubar/vbar)^2*(L/smd)^(2/3))^(3/5);
    new = rhs*L/br;
    if abs(new - smd) < 1e-12*max(1,abs(smd)); smd = new; break; end
    smd = 0.5*(smd + new);                     % damped update
end
end

% =========================================================================
function c = default_cfg()
c.rho_liq = 1000;   c.rho_gas = 5.0;
c.sigma   = 0.030;  c.mu_liq  = 1.0e-3;  c.mu_gas = 2.0e-5;
c.d_jet   = 1.0e-3; c.u_jet   = 30;
c.u_sheet = 30;     c.s_sheet = 1.0;
c.theta_imping = deg2rad(60);   c.phi_azimuth = 0;
c.we_transition= 2000;
c.p_upstream = 5.0e6;  c.p_vapor = 2.0e3;  c.dp_orifice = 2.0e6;
c.cav_crit   = 1.8;
c.d_drop0 = 2.0e-4;   c.u_rel = 120;   c.cd_mean = 1.0;
c.accel   = 9.80665e3;
c.x_station = 0.05;   c.length_scale = 2.0e-4;
c.u_mean  = 30;       c.v_rms = 2.0;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
