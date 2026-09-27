function res = yang_ch10_damping(cfg)
% YANG_CH10_DAMPING  Chapters 10 & 11 - flame stabilization statistics and
% droplet vaporization response.
%   Ch.10 Agarkov et al. - damping decrement, correlation envelope, impulse
%         response, disturbance parameter, Helmholtz resonator dynamics
%   Ch.11 Sirignano et al. - vaporization response factor G, phase
%         equilibrium, interface balances, generalized d^2 law
%
%   res = yang_ch10_damping(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

om  = 2*pi*cfg.freq_hz;

%% ===== Ch.10 damped random oscillation =================================
% P' = A exp(-INT delta dt) sin(INT omega dt + phi)
% delta = (E2 - E1)/(2 E_sigma) is the FRACTIONAL energy loss per cycle, so
% it is the logarithmic decrement (dimensionless), not a rate.  The decay
% rate that appears in the exponential is delta_rate = delta * f = delta/T.
dmp.log_decrement = (cfg.energy_out - cfg.energy_in)/(2*cfg.energy_total);
dmp.period        = 1/cfg.freq_hz;
dmp.delta         = dmp.log_decrement/dmp.period;   % 1/s, used below
dmp.decrement     = dmp.log_decrement;              % delta*T
dmp.zeta          = dmp.delta/om;                   % damping ratio
dmp.q_factor      = 1/(2*max(dmp.zeta,eps));

t = linspace(0, cfg.t_span, cfg.n_time);
dmp.time     = t;
dmp.envelope = cfg.amp0*exp(-dmp.delta*t);
dmp.signal   = dmp.envelope.*sin(om*t + cfg.phase0);

% Impulse response  h(t) = exp(-delta t) sin(omega t), t > 0
dmp.impulse  = exp(-dmp.delta*t).*sin(om*t);
% RMS output of a white-noise-driven oscillator: y^2 = x^2/(4 delta)
dmp.rms_out  = sqrt(cfg.rms_forcing^2/(4*max(dmp.delta,eps)));
% sqrt(E[A^2]) = (1/sqrt(delta)) * sqrt(E[x^2])/sqrt(2)
dmp.rms_amp  = (1/sqrt(max(dmp.delta,eps)))*cfg.rms_forcing/sqrt(2);

% Correlation envelope  R_A(tau) = (4/5)[1 + (1/4) exp(-2 delta tau)]
tau = linspace(0, cfg.tau_span, cfg.n_time);
dmp.tau        = tau;
dmp.corr_env   = 0.8*(1 + 0.25*exp(-2*dmp.delta*tau));
% E[(A(t+tau)-A(t))^2]/E[A^2] = (2/5)(1 - exp(-2 delta tau))
dmp.rms_change = 0.4*(1 - exp(-2*dmp.delta*tau));
% Full correlation coefficient R(tau) = B(tau)/B(0)
dmp.corr_coef  = exp(-dmp.delta*tau).*cos(om*tau);

% Disturbance parameter  n = A_0/(2 A_{n,max})
dmp.n_disturb  = cfg.amp_bomb/(2*cfg.amp_max_natural);
dmp.triggered  = dmp.n_disturb > 1;
% Effective decrement measured from successive peaks: (delta T)_i = ln(A_i/A_{i-1})
pk             = cfg.amp0*exp(-dmp.delta*(0:cfg.n_peaks-1)*dmp.period);
dmp.peaks      = pk;
dmp.decr_meas  = log(pk(1:end-1)./pk(2:end));

%% ===== Ch.10 / Ch.18 Helmholtz resonator dynamics ======================
% l_eff d(mdot)/dt + R0 mdot/rho + rho a^2 A_ori^2/V_cav z = A_ori p'
% with mdot = rho A_ori dz/dt.  Divide through to a 2nd-order system in z:
%   l_eff z'' + (R0/rho) z' + (a^2 A_ori/V_cav) z = p'/rho
a_ori = cfg.a_orifice;  a_cav = cfg.a_cavity;
% Effective length: l_eff = l_ori + 0.96 sqrt(A_ori)(0.5 - 0.7 sqrt(A_ori/A_cav))
hr.l_corr = 0.96*sqrt(a_ori)*(0.5 - 0.7*sqrt(a_ori/a_cav));
hr.l_eff  = cfg.l_orifice + hr.l_corr;
hr.r0     = cfg.gamma_resist*cfg.rho_gas*cfg.u_mean_orifice;   % R0 = G rho U
hr.omega0 = sqrt(cfg.a_sound^2*a_ori/(cfg.v_cavity*hr.l_eff));
hr.f0     = hr.omega0/(2*pi);
hr.zeta   = (hr.r0/cfg.rho_gas)/(2*hr.l_eff*hr.omega0);
hr.q      = 1/(2*max(hr.zeta,eps));

% Frequency response of the resonator displacement to chamber pressure
f  = cfg.f_sweep(:).';  w = 2*pi*f;
den = -hr.l_eff*w.^2 + 1i*w*(hr.r0/cfg.rho_gas) + hr.omega0^2*hr.l_eff;
hr.freq_hz  = f;
hr.z_resp   = (1/cfg.rho_gas) ./ den;
hr.mdot_resp= 1i*w.*hr.z_resp*cfg.rho_gas*a_ori;
% Absorbed acoustic power ~ R0 |mdot/rho|^2, normalised
hr.absorb   = hr.r0*abs(hr.mdot_resp/cfg.rho_gas).^2;
hr.absorb   = hr.absorb/max(hr.absorb);

%% ===== Ch.11 droplet vaporization response =============================
% Generalized law:  D^2(t) = D_i^2 - (K_v t)^a (D_i^2)^(1-a)
Di = cfg.d_drop_init;  Kv = cfg.k_vaporization;  av = cfg.alpha_vap;
tv = linspace(0, cfg.t_vap_span, cfg.n_time);
d2 = Di^2 - (Kv*tv).^av * (Di^2)^(1-av);
d2(d2 < 0) = 0;
vap.time    = tv;
vap.d_drop  = sqrt(d2);
vap.d2_law  = max(Di^2 - Kv*tv, 0);            % classical a = 1 limit
vap.lifetime= (Di^2/Kv)^(1/av)*(Di^2)^((av-1)/av);

% Instantaneous vaporization rate
%   mdot0 = rho_L pi D/4 (D_i^2)^((1-a)/a) a K_v [D_i^2 - D^2]^((a-1)/a)
arg = max(Di^2 - d2, eps);
vap.mdot = cfg.rho_liq*pi*vap.d_drop/4*(Di^2)^((1-av)/av)*av*Kv ...
           .* arg.^((av-1)/av);
vap.mdot(~isfinite(vap.mdot)) = 0;

% Characteristic droplet heating time  tau_dh ~ (rho_l c_l / lambda_g) r_d^2
vap.tau_heat = (cfg.rho_liq*cfg.cp_liq/cfg.k_gas)*(Di/2)^2;
% Ratio of heating to vaporization time controls the response phase.
vap.heat_ratio = vap.tau_heat/vap.lifetime;

% Response factor  G = INT m' p' dtheta / INT p'^2 dtheta  (Eqs 1 and 7).
% Model the vaporization response as a first-order lag with the heating time,
% then evaluate G over the frequency sweep.
w      = 2*pi*cfg.f_sweep(:).';
h_resp = cfg.gain_vap ./ (1 + 1i*w*vap.tau_heat);
vap.freq_hz  = cfg.f_sweep;
vap.g_factor = real(h_resp);          % in-phase part drives the Rayleigh integral
vap.g_imag   = imag(h_resp);
vap.g_mag    = abs(h_resp);
[vap.g_max, ig] = max(vap.g_factor);
vap.f_g_max  = cfg.f_sweep(ig);
% G > 0 adds energy to the mode, but only matters if it is large enough to
% compete with the acoustic losses.  When the droplet heating time is much
% longer than the acoustic period the droplet simply cannot follow the
% oscillation and G collapses towards zero -- that is not "driving".
vap.driving      = vap.g_factor > cfg.g_significant;
vap.driving_any  = vap.g_max    > cfg.g_significant;
vap.responsive   = vap.tau_heat*2*pi*max(cfg.f_sweep) > 1;

% Critical-point / phase-equilibrium check (Eqs 2-4).  Above T_crit the
% interface disappears and the d^2 law no longer applies.
vap.t_surface  = cfg.t_surface;
vap.supercrit  = cfg.t_surface >= cfg.t_critical;
% Interface energy balance (Eq 6), lumped: conduction in = latent + sensible
vap.q_iface    = cfg.k_gas*(cfg.t_gas - cfg.t_surface)/(Di/2);
vap.mdot_iface = vap.q_iface*pi*Di^2 ...
                 /(cfg.h_latent + cfg.cp_liq*(cfg.t_surface - cfg.t_liq_init));

res.cfg = cfg;  res.damping = dmp;  res.resonator = hr;  res.vaporization = vap;
end

% =========================================================================
function c = default_cfg()
c.freq_hz     = 2000;   c.amp0 = 1.0;   c.phase0 = 0;
% (E_out - E_in)/(2 E_total) = log decrement.  0.0628 corresponds to the
% Q ~ 50 typical of a lightly damped liquid rocket chamber.
c.energy_in   = 1.0;    c.energy_out = 1.1256;  c.energy_total = 1.0;
c.t_span      = 0.02;   c.tau_span = 0.02;    c.n_time = 800;
c.rms_forcing = 0.05;
c.amp_bomb    = 0.5;    c.amp_max_natural = 1.0;  c.n_peaks = 12;
c.a_orifice   = 7.85e-5;  c.a_cavity = 1.0e-3;
c.l_orifice   = 0.010;    c.v_cavity = 5.0e-5;
c.rho_gas     = 1.6;      c.a_sound  = 1100;
c.gamma_resist= 0.5;      c.u_mean_orifice = 20;
c.f_sweep     = linspace(200, 8000, 500);
c.d_drop_init = 1.0e-4;   c.k_vaporization = 5.0e-7;  c.alpha_vap = 0.85;
c.rho_liq     = 1140;     c.cp_liq = 1700;  c.k_gas = 0.15;
c.t_vap_span  = 0.02;
c.gain_vap    = 1.5;
c.g_significant = 0.05;   % below this, G is too small to matter vs damping
c.t_surface   = 140;   c.t_critical = 155;  c.t_gas = 3000;  c.t_liq_init = 90;
c.h_latent    = 213e3;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
