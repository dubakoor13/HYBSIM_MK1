function res = yang_ch06_atomization(cfg)
% YANG_CH06_ATOMIZATION  Chapters 6 & 7 - coaxial injector atomization.
%   Ch.6 Vingert, Gicquel, Lourme & Menoret, Eqs (1)-(50)
%   Ch.7 Zaller & Klem, Eqs (1)-(3)
%
% Implements the Nukiyama-Tanasawa distribution and SMD correlation, the
% aerodynamic Weber number, prompt atomization, Mayer's mean drop size, the
% Dickerson-Schuman stripping rate, the viscous sheet force balance and its
% dominant wave (Lambda, Omega), Reitz drop radius, the Rosin-Rammler size
% distribution, Abramovitch velocity profiles, the Kim-Marshall MMD, the
% Ferrenberg-Varma and Wolfe-Anderson simulant corrections, multiple-
% scattering corrections, and the Vulcain injector D32 correlation.
%
%   res = yang_ch06_atomization(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

rho_l = cfg.rho_liq;  rho_g = cfg.rho_gas;
sig   = cfg.sigma;    mu_l  = cfg.mu_liq;   mu_g = cfg.mu_gas;
d_j   = cfg.d_jet;    v_l   = cfg.v_liq;    v_g  = cfg.v_gas;
v_r   = v_g - v_l;                          % relative (shear) velocity

%% ===== dimensionless groups ============================================
nd.we_jet   = rho_l*v_l^2*d_j/sig;                 % liquid Weber
nd.we_aero  = rho_g*v_r^2*d_j/sig;                 % aerodynamic Weber
nd.re_liq   = rho_l*v_l*d_j/mu_l;
nd.re_gas   = rho_g*v_r*d_j/mu_g;
nd.oh       = mu_l/sqrt(rho_l*d_j*sig);            % Ohnesorge
nd.dens_rat = rho_l/rho_g;
nd.alr      = cfg.mdot_gas/cfg.mdot_liq;           % air-to-liquid ratio
% Eq (3): aerodynamic Weber with impingement angle
%   We_ae = sigma / [rho_g D_j (V_g - V_l cos a)^2 sin^2 a]
a = cfg.angle_imping;
nd.we_ae_angle = sig / (rho_g*d_j*(v_g - v_l*cos(a))^2*sin(a)^2);

%% ===== Eq (2) Nukiyama-Tanasawa SMD correlation ========================
% The correlation is dimensional and is stated in its original cgs form:
%   SMD[um] = 585/V_r sqrt(sigma/rho_l)
%             + 597 [mu_l/sqrt(sigma rho_l)]^0.45 (1000 Q_l/Q_g)^1.5
% with sigma in dyn/cm, rho in g/cm^3, mu in poise and V_r in m/s.  Convert
% the SI inputs into those units, evaluate, then convert the result back.
sig_cgs = sig*1000;            % N/m   -> dyn/cm
rho_cgs = rho_l/1000;          % kg/m3 -> g/cm3
mu_cgs  = mu_l*10;             % Pa.s  -> poise
q_ratio = (cfg.mdot_liq/rho_l)/(cfg.mdot_gas/rho_g);   % volumetric Q_l/Q_g
smd.nukiyama_um = 585/v_r*sqrt(sig_cgs/rho_cgs) ...
                + 597*(mu_cgs/sqrt(sig_cgs*rho_cgs))^0.45*(1000*q_ratio)^1.5;
smd.nukiyama    = smd.nukiyama_um*1e-6;                % back to metres

%% ===== Eq (4) maximum drop, Eq (5) prompt atomization ==================
smd.d_max     = 2.2*sqrt(nd.we_ae_angle)*d_j;                    % Eq (4)
smd.d32_prompt= 1.5*d_j/(1 + cfg.c_prompt*nd.we_aero/(1+1/nd.alr)); % Eq (5)

%% ===== Eq (7)/(25) Mayer mean drop size ================================
% D_bar = B_A [ mu_l sqrt(sigma/rho_l) / (rho_g V_r^2) ]^(2/3)
smd.d_mayer = cfg.b_mayer*( mu_l*sqrt(sig/rho_l)/(rho_g*v_r^2) )^(2/3);

%% ===== Eq (8)/(26) Dickerson-Schuman stripping rate ====================
% mdot/A = C_A (rho_g^2 V_r^4 mu_l rho_l / sigma)^(1/3)
strip.flux    = cfg.c_strip*( rho_g^2*v_r^4*mu_l*rho_l/sig )^(1/3);
strip.mdot    = strip.flux*pi*d_j;                                % Eq (26)
strip.frac    = min(1, strip.mdot/max(cfg.mdot_liq, eps));

%% ===== Eqs (9)-(15) viscous sheet breakup ==============================
% Eq (11): 1 - F^2 - V F^3 = 0 with the viscosity parameter of Eq (12).
sheet.v_param = (mu_l*rho_g*v_r^2/2)*sqrt(cfg.tau_sheet/(2*rho_l*sig^3));
sheet.f_ratio = solve_cubic_f(sheet.v_param);                     % Eq (11)
sheet.k_wave  = sheet.f_ratio^2*rho_g*v_r^2/(2*sig);              % Eq (10)
% Eq (13): dominant wavelength and growth rate
sheet.lambda  = 3*pi*sig/(rho_g*v_r^2);
sheet.omega   = 2*rho_g*v_r^3/(3*sqrt(3)*sig)*sqrt(rho_g/rho_l);
sheet.c_wave  = (rho_g*v_g + rho_l*v_l)/rho_l;                    % Eq (14)
smd.d32_wave  = 0.75*sheet.lambda;                                % Eq (15)

%% ===== Eqs (19)-(22) spray cone development ============================
% Eq (20): da/dx = -0.78 (A C1/C2) Omega Lambda / V_l
cone.da_dx    = -0.78*cfg.amp_wave*cfg.c1_drop/cfg.c2_drop ...
                * sheet.omega*sheet.lambda/v_l;
% Eq (21): cone (breakup) length
cone.length   = (2*sqrt(3)*(d_j/2)*v_l)/(9*pi*cfg.c_cone*v_r)*sqrt(rho_l/rho_g);
% Eq (22): half spray angle  theta/2 = A Lambda Omega / V_l
cone.half_ang = cfg.amp_wave*sheet.lambda*sheet.omega/v_l;
cone.angle_deg= 2*atan(min(cone.half_ang,10))*180/pi;
% Eq (19): drop production rate per unit length and time
cone.dN       = cfg.c1_drop*(64*pi*cfg.amp_wave*(d_j/2)) ...
                /(9*cfg.t_breakup*sheet.lambda^2);

%% ===== Eqs (23)-(24) Reitz drop radius & jet erosion ===================
a_rad = d_j/2;
r1 = cfg.b0_reitz*sheet.lambda;
if r1 <= a_rad
    reitz.r_drop = r1;                                            % Eq (23a)
else
    reitz.r_drop = min( (3*pi*a_rad^2*v_r/(2*sheet.omega))^(1/3), ...
                        (3*a_rad^2*sheet.lambda/4)^(1/3) );       % Eq (23b)
end
reitz.da_dt = -((a_rad - reitz.r_drop)*sheet.lambda*sheet.omega) ...
              /(3.726*cfg.b1_reitz*a_rad);                        % Eq (24)
reitz.d_drop = 2*reitz.r_drop;

%% ===== Eqs (28)-(29) ligament stripping ================================
lig.t_strip = log(sheet.lambda/cfg.x0_disturb)/max(sheet.omega,eps);  % Eq (28)
lig.mass    = rho_l*a_rad*(pi*sheet.lambda)^2/8;                      % Eq (29)
lig.d_lig   = sqrt(4*cfg.h_sheet/max(sheet.k_wave,eps));

%% ===== Eqs (1),(30)-(33) size distributions ============================
d_ax = linspace(0.05*smd.nukiyama, 5*smd.nukiyama, cfg.n_bins);
% Eq (1) Nukiyama-Tanasawa number distribution
al = cfg.nt_alpha;  be = cfg.nt_beta;  dbar = smd.nukiyama;
dist.d_axis = d_ax;
dist.nt_pdf = (be*d_ax.^al ./ (gamma((al+1)/be)*dbar^(al+1))) ...
              .* exp(-(d_ax/dbar).^be);
% Eqs (32),(33): Rosin-Rammler parameters derived from the SMD.  Both are
% dimensional correlations stated in MICRONS -- evaluating them on metres
% collapses N to zero, so convert in and out explicitly.
d_rr_um   = (0.91*smd.nukiyama_um)^1.18;                          % Eq (32)
dist.n_rr = d_rr_um/(0.126*d_rr_um + 1.2);                        % Eq (33)
dist.d_rr = d_rr_um*1e-6;                                         % back to m
dist.rr_cum   = 1 - exp(-(d_ax/dist.d_rr).^dist.n_rr);            % Eq (31)
dist.rr_mod   = 1 - exp(-(log(max(d_ax,eps))/log(dist.d_rr)).^dist.n_rr); % Eq(30)
% Eq (47): Vulcain Rosin-Rammler exponent
dist.n_vulcain = 1/(1/2.15 - 0.09*log(cfg.mdot_tot_vul/60.5) ...
                    + 0.17*log(cfg.d_tube_vul/2));
% Eq (18): SMD from a discrete population
dist.smd_discrete = trapz(d_ax, dist.nt_pdf.*d_ax.^3) ...
                    / trapz(d_ax, dist.nt_pdf.*d_ax.^2);

%% ===== Eqs (34)-(39) Abramovitch profiles ==============================
r_ax = linspace(0, cfg.r_gas_jet, 60);
prof.r_axis = r_ax;
% Eq (34): u_g(z,r) = u_c [1 - (r/R_g)^1.5]^2
prof.u_gas  = cfg.u_center*max(0, 1 - (r_ax/cfg.r_gas_jet).^1.5).^2;
prof.r_m    = 0.93*(cfg.d_gas_post - cfg.d_liq_post);             % Eq (35)
% Eq (38): liquid mass flux profile
prof.mdot_l = cfg.mdot_l_center ...
              * max(0, 1 - (r_ax/(2.874*cfg.r_bar_liq)).^1.5).^3;
% Eq (39) defines r_bar_l where the profile falls to half the centreline.
prof.r_half = interp1(prof.mdot_l/max(prof.mdot_l,[],'omitnan'), r_ax, 0.5, ...
                      'linear', NaN);

%% ===== Eq (40) Kim-Marshall MMD ========================================
smd.mmd_kim = 5.36e-3*sig^0.41*mu_l^0.32 ...
              /((rho_g*v_r^2)^0.57*cfg.a_gas_ann^0.36*rho_l^0.16) ...
            + 3.44e-3*(mu_l^2/(sig*rho_l))^0.17 ...
              *(cfg.mdot_liq/cfg.mdot_gas)*v_r^(-0.54);

%% ===== Eqs (41),(42),(48),(51) simulant corrections ====================
s = cfg.simulant;
corr.ferrenberg = (mu_l/(sig*rho_l))^(1/4) ...
                  /((s.mu/(s.sigma*s.rho))^(1/4));                % Eq (41)
corr.wolfe      = (mu_l^(1/3)*sig^(1/2)*rho_l^(-1/6)) ...
                  /(s.mu^(1/3)*s.sigma^(1/2)*s.rho^(-1/6));       % Eq (42)
corr.d_actual_fv= corr.ferrenberg*smd.nukiyama;
corr.d_actual_wa= corr.wolfe*smd.nukiyama;

%% ===== Eqs (43)-(45) multiple-scattering correction ====================
Q = cfg.obscuration;
corr.d_scatter = 0.3*cos(pi/4*(Q^5 + Q^8.5)) + 0.7;               % Eq (43)
N0 = dist.n_rr;
if Q < 0.8 - 0.1*N0
    corr.n_scatter = N0;                                          % Eq (44)
else
    corr.n_scatter = 0.8*(0.8 + N0 - Q)/(1.68 - 0.1*N0 - Q);      % Eq (45)
end

%% ===== Eq (46) Vulcain injector D32 ====================================
smd.d32_vulcain = 127*(cfg.v_r_vul/160)^(-0.93)*(cfg.d_liq_vul/2)^2.25 ...
                  *(cfg.d_gas_vul/3)^(-2.65) ...
                  *(cfg.recess_vul/cfg.d_liq_vul)^(-0.26);

%% ===== Ch.7 Zaller & Klem, Eqs (1)-(3) =================================
% Eq (2): composite volume-mean drop size correlation
zk.d30 = 5.92e-5*(sig/mu_l)^0.75*(rho_l/rho_g)^0.05 ...
         *(cfg.mdot_liq/cfg.mdot_gas)^0.25*v_r^0.05 / v_r^0.8;
% Eq (3): recess correction  D_recess/D = 1 + 0.18 R - 0.278 sqrt(R)
R = cfg.recess_ratio;
zk.recess_factor = 1 + 0.18*R - 0.278*sqrt(R);
zk.d30_recessed  = zk.d30*zk.recess_factor;
% Eq (1): composite mean over annular sampling rings, weighted by A_i/t_i
w = cfg.ring_area(:)./cfg.ring_time(:);
zk.d30_composite = ( sum(w.*cfg.ring_d30(:).^3)/sum(w) )^(1/3);
% Ch.6 Eqs (49),(50): line-averaged SMD from local measurements
wi = cfg.ring_dr(:).*cfg.ring_count(:)./(cfg.ring_time(:).*cfg.ring_area(:));
zk.smd_line = sum(wi.*cfg.ring_d30(:).^3)/sum(wi.*cfg.ring_d20(:).^2);

%% ===== applicability of each correlation ===============================
% These are dimensional fits to specific test campaigns.  At the very high
% shear of a LOX/H2 shear-coaxial element several of them are extrapolated
% far outside the range they were calibrated on and must not be read as
% predictions.  Flag each one rather than silently reporting a number.
val.nukiyama = struct( ...
    'valid', nd.we_aero < 1e4 && nd.alr > 0.5, ...
    'note',  'air-blast fit; needs We_ae < 1e4 and ALR > 0.5');
val.mayer = struct( ...
    'valid', v_r > 50 && v_r < 200, ...
    'note',  'calibrated for V_r = 50-200 m/s');
val.wave = struct( ...
    'valid', nd.we_aero > 10 && nd.we_aero < 5e3, ...
    'note',  'inviscid sheet theory; over-predicts breakup at very high We');
val.kim_marshall = struct( ...
    'valid', nd.alr > 0.05 && nd.alr < 10, ...
    'note',  'calibrated for ALR = 0.05-10');
val.vulcain = struct( ...
    'valid', abs(cfg.v_r_vul - v_r)/v_r < 1.0, ...
    'note',  'Vulcain-specific fit, arguments are in mm and m/s');
val.any_invalid = ~(val.nukiyama.valid && val.mayer.valid && val.wave.valid);
% Best available estimate: prefer the correlations still inside their range.
cands = [];  names = {};
if val.kim_marshall.valid; cands(end+1) = smd.mmd_kim;  names{end+1} = 'Kim-Marshall'; end
if val.nukiyama.valid;     cands(end+1) = smd.nukiyama; names{end+1} = 'Nukiyama-Tanasawa'; end
if val.mayer.valid;        cands(end+1) = smd.d_mayer;  names{end+1} = 'Mayer'; end
if val.wave.valid;         cands(end+1) = smd.d32_wave; names{end+1} = 'wave'; end
if isempty(cands)
    smd.recommended = smd.mmd_kim;  smd.recommended_src = 'Kim-Marshall (extrapolated)';
else
    smd.recommended = median(cands);  smd.recommended_src = strjoin(names, '/');
end

res.cfg = cfg;  res.nd = nd;   res.smd = smd;  res.sheet = sheet;
res.validity = val;
res.cone= cone; res.reitz= reitz; res.lig = lig; res.dist = dist;
res.prof= prof; res.corr = corr;  res.strip= strip; res.zaller = zk;
end

% =========================================================================
function F = solve_cubic_f(V)
% Eq (11): 1 - F^2 - V F^3 = 0, take the physical root in (0,1].
if V <= 0; F = 1; return; end
r = roots([-V, -1, 0, 1]);
r = r(abs(imag(r)) < 1e-9);
r = real(r(r > 0));
if isempty(r); F = 1; else; F = min(r); end
end

% =========================================================================
function c = default_cfg()
c.rho_liq = 1140;   c.rho_gas = 5.0;
c.sigma   = 0.013;  c.mu_liq  = 2.0e-4;  c.mu_gas = 2.0e-5;
c.d_jet   = 3.0e-3; c.v_liq   = 25;      c.v_gas  = 300;
c.mdot_liq= 0.30;   c.mdot_gas= 0.05;
c.angle_imping = deg2rad(60);
c.c_prompt= 0.05;   c.b_mayer = 0.30;    c.c_strip= 0.10;
c.tau_sheet = 5e-5; c.amp_wave= 0.10;
c.c1_drop = 1.0;    c.c2_drop = 1.0;     c.c_cone = 0.10;
c.t_breakup = 2e-4; c.b0_reitz= 0.61;    c.b1_reitz = 10;
c.x0_disturb= 1e-7; c.h_sheet = 5e-5;
c.n_bins  = 200;    c.nt_alpha= 2;       c.nt_beta = 1;
c.r_gas_jet = 4e-3; c.u_center= 320;
c.d_gas_post= 6e-3; c.d_liq_post = 3e-3;
c.mdot_l_center = 1.0;  c.r_bar_liq = 1.5e-3;
c.a_gas_ann = 2.0e-5;
c.obscuration = 0.4;
c.mdot_tot_vul = 60.5;  c.d_tube_vul = 2.0;
c.v_r_vul = 160;   c.d_liq_vul = 2.0;  c.d_gas_vul = 3.0;  c.recess_vul = 1.0;
c.recess_ratio = 1.0;
c.simulant = struct('mu',1.0e-3,'sigma',0.072,'rho',998);
c.ring_area  = [1 2 3 4]*1e-6;
c.ring_time  = [1 1 1 1]*1e-3;
c.ring_d30   = [40 55 70 85]*1e-6;
c.ring_d20   = [35 50 64 78]*1e-6;
c.ring_dr    = [1 1 1 1]*1e-3;
c.ring_count = [500 400 300 200];
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
