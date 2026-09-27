function res = yang_ch14_cavity(cfg)
% YANG_CH14_CAVITY  Chapter 14 - acoustic cavity design (Laudien, Pongratz,
% Pierro & Preclik, 1995), Eqs (1)-(18).
%
% Computes chamber resonant frequencies (Eq 1), the velocity potential and
% acoustic pressure fields (Eqs 2-4), Helmholtz and quarter-wave tuning
% (Eqs 5,6), the orifice impedance Z = R + i chi with radiation and viscous
% resistance (Eqs 7-12), the combined impedance of an array (Eq 13), the
% absorption coefficient and conductance (Eqs 14,15), the two-microphone
% transfer function (Eqs 16,17) and the cold-flow to hot-fire tuning shift
% (Eq 18).
%
%   res = yang_ch14_cavity(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

c   = sqrt(cfg.gamma_gas*cfg.r_gas*cfg.t_chamber);   % hot sound speed
rho = cfg.p_chamber/(cfg.r_gas*cfg.t_chamber);

%% ===== Eq (1) chamber resonant frequencies ============================
% f_lmn = c/(2 pi) sqrt( lambda_mn^2/R_c^2 + l^2 pi^2/L_c^2 )
ch.c_sound = c;
ch.rho     = rho;
k = 0;  ch.modes = struct([]);
for l = 0:cfg.n_axial
    for m = 0:cfg.n_tang
        for sidx = 1:cfg.n_radial
            if l==0 && m==0 && sidx==1; continue; end
            lam = besselj_prime_zero(m, sidx);
            f   = c/(2*pi)*sqrt(lam^2/cfg.r_chamber^2 ...
                                + l^2*pi^2/cfg.len_chamber^2);
            k = k + 1;
            ch.modes(k).id      = sprintf('%dL%dT%dR', l, m, sidx-1);
            ch.modes(k).l = l;  ch.modes(k).m = m;  ch.modes(k).s = sidx-1;
            ch.modes(k).lambda_mn = lam;
            ch.modes(k).freq_hz = f;
            ch.modes(k).omega   = 2*pi*f;
        end
    end
end
[~, o] = sort([ch.modes.freq_hz]);  ch.modes = ch.modes(o);
ch.f_target = ch.modes(cfg.target_mode).freq_hz;
ch.id_target= ch.modes(cfg.target_mode).id;

% Eqs (2)-(4): potential, pressure and mode shape on a chamber cross-section
% phi_lmn = J_m(lambda r/R) cos(l pi x/L) cos(m theta)
rr = linspace(0, cfg.r_chamber, 60);
tt = linspace(0, 2*pi, 90);
[Rg, Tg] = meshgrid(rr, tt);
mt = ch.modes(cfg.target_mode);
ch.field_r = Rg;  ch.field_t = Tg;
ch.mode_shape = besselj(mt.m, mt.lambda_mn*Rg/cfg.r_chamber).*cos(mt.m*Tg);
ch.p_amplitude = cfg.amp_lmn*rho*c^2*ch.mode_shape;   % Eq (3)

%% ===== Eqs (5),(6) resonator tuning ===================================
% End correction ~ 0.85 a for a flanged orifice of radius a
res_o.a_orifice = cfg.a_orifice;
res_o.dl        = 0.85*sqrt(cfg.a_orifice/pi);
% Eq (5): Helmholtz
res_o.f_helm    = c/(2*pi)*sqrt(cfg.a_orifice ...
                  /(cfg.v_cavity*(cfg.l_orifice + res_o.dl)));
% Eq (6): quarter wave
res_o.f_quarter = c/(4*(cfg.l_quarter + res_o.dl));
% Cavity length required to tune the quarter-wave onto the target mode
res_o.l_required= c/(4*ch.f_target) - res_o.dl;
% Cavity volume required to tune a Helmholtz resonator onto the target
res_o.v_required= cfg.a_orifice*c^2 ...
                  /((2*pi*ch.f_target)^2*(cfg.l_orifice + res_o.dl));

%% ===== Eqs (7)-(12) impedance =========================================
f  = cfg.f_sweep(:).';   w = 2*pi*f;
nu = cfg.mu_gas/rho;                                   % kinematic viscosity

% Eq (10): radiation resistance  R_r = 2 pi rho S f0^2/c
imp.R_r = 2*pi*rho*cfg.a_orifice*res_o.f_helm^2/c;
% Eq (11): internal (viscous + nonlinear) resistance
%   R_i = 4 (eps_l + eps_nl + l/d) sqrt(nu rho pi f)
d_ori   = 2*sqrt(cfg.a_orifice/pi);
imp.R_i = 4*(cfg.eps_linear + cfg.eps_nonlin + cfg.l_orifice/d_ori) ...
          .* sqrt(nu*rho*pi*f);
imp.R   = imp.R_r + imp.R_i;                           % Eq (9)

% Eq (8): Helmholtz reactance  chi = 2 pi f rho (l+dl)(1 - f0^2/f^2)
imp.chi_helm = 2*pi*f*rho*(cfg.l_orifice + res_o.dl) ...
               .*(1 - res_o.f_helm^2./f.^2);
% Eq (12): quarter-wave reactance  chi = -4 rho (L+dl) f0 cot(pi f/(2 f0))
imp.chi_quarter = -4*rho*(cfg.l_quarter + res_o.dl)*res_o.f_quarter ...
                  .* cot(pi*f./(2*res_o.f_quarter));

% Eq (7): Z = R + i chi
imp.freq_hz = f;
imp.Z_helm    = imp.R + 1i*imp.chi_helm;
imp.Z_quarter = imp.R + 1i*imp.chi_quarter;

% Eq (13): combined impedance of an array,  Z = (1/A SUM S_i/Z_i)^-1
sum_y = 0;
for i = 1:numel(cfg.array_area)
    if strcmpi(cfg.array_type{i}, 'helmholtz')
        Zi = imp.Z_helm;
    else
        Zi = imp.Z_quarter;
    end
    sum_y = sum_y + cfg.array_area(i)./Zi;
end
imp.Z_array = 1./(sum_y/cfg.a_wall);

%% ===== Eqs (14),(15) absorption =======================================
rc = rho*c;                                            % characteristic imp.
r_s = real(imp.Z_array)/rc;
x_s = imag(imp.Z_array)/rc;
% Eq (14): alpha = 4 (r/rc) / [(1 + r/rc)^2 + (x/rc)^2]
abs_.freq_hz    = f;
abs_.alpha      = 4*r_s ./ ((1 + r_s).^2 + x_s.^2);
% Eq (15): conductance  xi = (r/rc)/[(r/rc)^2 + (x/rc)^2]
abs_.conductance= r_s ./ (r_s.^2 + x_s.^2);
[abs_.alpha_max, ia] = max(abs_.alpha);
abs_.f_best     = f(ia);
abs_.alpha_at_target = interp1(f, abs_.alpha, ch.f_target, 'linear', NaN);
% Half-power absorption bandwidth
above = abs_.alpha >= abs_.alpha_max/2;
if any(above)
    abs_.bw_hz = f(find(above,1,'last')) - f(find(above,1,'first'));
else
    abs_.bw_hz = NaN;
end

%% ===== Eqs (16),(17) two-microphone transfer function =================
w0 = 2*pi*res_o.f_helm;
den = (w*rho*(cfg.l_orifice+res_o.dl).*(1 - w0^2./w.^2)).^2 + imp.R.^2;
num = w*rho*(cfg.l_orifice+res_o.dl).*(1 - w0^2./w.^2) + 1i*imp.R;
tf.freq_hz = f;
tf.p2_p1   = (-rho*c^2*cfg.a_orifice./(w*cfg.v_cavity)) .* num ./ den;
tf.mag_db  = 20*log10(abs(tf.p2_p1));
% Eq (17): at resonance  p2/p1 = -i w0 rho (l+dl)/R
Rr = interp1(f, imp.R, res_o.f_helm, 'linear', 'extrap');
tf.at_resonance = -1i*w0*rho*(cfg.l_orifice+res_o.dl)/Rr;
tf.q_resonance  = abs(tf.at_resonance);

%% ===== Eq (18) cold-to-hot tuning shift ===============================
c_cold = sqrt(cfg.gamma_cold*cfg.r_cold*cfg.t_cold);
tune.c_cold  = c_cold;
tune.c_hot   = c;
tune.f_ratio = (c/c_cold)*(cfg.l_quarter_cold + res_o.dl) ...
               /(cfg.l_quarter + res_o.dl);
tune.f_cold_test = res_o.f_quarter/tune.f_ratio;
% Length that must be set during cold flow to land on target when hot
tune.l_cold_setting = c_cold/(4*tune.f_cold_test) - res_o.dl;

res.cfg = cfg;  res.chamber = ch;  res.resonator = res_o;
res.impedance = imp;  res.absorption = abs_;  res.transfer = tf;
res.tuning = tune;
res.tuned_ok = abs(res_o.f_quarter - ch.f_target)/ch.f_target < 0.10;
end

% =========================================================================
function a = besselj_prime_zero(m, idx)
persistent tbl
if isempty(tbl)
    tbl = containers.Map('KeyType','double','ValueType','any');
    tbl(0) = [0, 3.8317, 7.0156, 10.1735];
    tbl(1) = [1.8412, 5.3314, 8.5363, 11.7060];
    tbl(2) = [3.0542, 6.7061, 9.9695, 13.1704];
    tbl(3) = [4.2012, 8.0152, 11.3459, 14.5858];
end
if isKey(tbl, m); v = tbl(m); a = v(min(idx,numel(v)));
else; a = m + 0.8086*m^(1/3) + (idx-1)*pi; end
end

% =========================================================================
function c = default_cfg()
c.gamma_gas  = 1.22;   c.r_gas = 8314/7.5;
c.t_chamber  = 3600;   c.p_chamber = 20.7e6;
c.mu_gas     = 9.0e-5;
c.r_chamber  = 0.15;   c.len_chamber = 0.50;
c.n_axial    = 2;  c.n_tang = 2;  c.n_radial = 2;
c.target_mode= 1;      % index into the sorted mode list (1T is usually first)
c.amp_lmn    = 0.01;
c.a_orifice  = 7.85e-5;   c.l_orifice = 0.010;
% Defaults tuned onto the first chamber mode (~2200 Hz at 3600 K), so the
% absorption peak lands on the target rather than far above it.  Retune with
% resonator.l_required / resonator.v_required when the engine changes.
c.v_cavity   = 1.57e-4;   c.l_quarter = 0.247;
c.eps_linear = 2.0;  c.eps_nonlin = 1.0;
c.f_sweep    = linspace(200, 8000, 800);
c.a_wall     = 0.10;                       % chamber wall area hosting devices
c.array_area = [7.85e-5, 7.85e-5];
c.array_type = {'helmholtz','quarter'};
c.gamma_cold = 1.4;   c.r_cold = 287;   c.t_cold = 293;
c.l_quarter_cold = 0.040;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
