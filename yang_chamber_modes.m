function [modes, gas] = yang_chamber_modes(cfg)
% YANG_CHAMBER_MODES  Normal acoustic modes of a hard-walled combustion
% chamber, shared by every chapter module that needs them.
%
% Solves the Helmholtz problem of Ch.1 Eqs (45),(46)
%       lap(psi_n) + k_n^2 psi_n = 0,      n . grad(psi_n) = 0
% with the closed-form eigenfunctions of Ch.13 Eqs (10)-(13), and evaluates
% the three integrals every stability calculation needs:
%
%   e_norm2        E_n^2 = INT psi_n^2 dV                        Ch.1 Eq (49)
%   int_psi        INT psi_n Qhat dV / INT Qhat dV * V, the overlap of the
%                  mode with the heat-release distribution        Ch.1 Eq (64)
%   int_psi2_exit  INT psi_n^2 dS over the nozzle end plane       Ch.1 Eq (70)
%
% Having one implementation means Ch.1, Ch.14 and Ch.15 cannot disagree
% about the mode set, the norms or the driving overlap.
%
%   [modes, gas] = yang_chamber_modes(cfg)

cfg = merge_defaults(cfg, modes_default_cfg());

%% --- mean gas state -----------------------------------------------------
gas.gamma      = cfg.gamma_gas;
gas.r_gas      = cfg.r_gas;
gas.p_mean     = cfg.p_mean;
gas.t_mean     = cfg.t_mean;
gas.a_sound    = sqrt(cfg.gamma_gas*cfg.r_gas*cfg.t_mean);
gas.rho_mean   = cfg.p_mean/(cfg.r_gas*cfg.t_mean);
gas.cv_gas     = cfg.r_gas/(cfg.gamma_gas - 1);
% Ch.1 Eq (28): mass-averaged specific heat of the two-phase mixture
gas.cv_mix     = (gas.cv_gas + cfg.load_liquid*cfg.cv_liquid)/(1 + cfg.load_liquid);

switch lower(cfg.geom_type)
    case 'cylindrical'
        gas.vol_chamber  = pi*cfg.rad_chamber^2*cfg.len_chamber;
        gas.area_exit    = pi*cfg.rad_chamber^2;
    case 'rectangular'
        gas.vol_chamber  = cfg.len_chamber*cfg.wid_chamber*cfg.hgt_chamber;
        gas.area_exit    = cfg.wid_chamber*cfg.hgt_chamber;
    otherwise
        error('yang_chamber_modes:geom', ...
              'geom_type must be cylindrical or rectangular');
end

%% --- enumerate modes ----------------------------------------------------
modes = struct([]);
k = 0;
switch lower(cfg.geom_type)
    case 'cylindrical'
        for l = 0:cfg.n_axial
            for m = 0:cfg.n_tang
                for sidx = 1:cfg.n_radial
                    if l == 0 && m == 0 && sidx == 1; continue; end   % bulk
                    alpha_ms = besselj_prime_zero(m, sidx);
                    kap      = alpha_ms/cfg.rad_chamber;
                    kn2      = (l*pi/cfg.len_chamber)^2 + kap^2;
                    k = k + 1;
                    modes(k).mode_id  = sprintf('L%dT%dR%d', l, m, sidx-1);
                    modes(k).l = l;  modes(k).m = m;  modes(k).s = sidx-1;
                    modes(k).kappa_ms = kap;
                    modes(k).alpha_ms = alpha_ms;
                    modes(k).k_wave   = sqrt(kn2);
                    modes(k).omega    = gas.a_sound*sqrt(kn2);
                    modes(k).freq_hz  = modes(k).omega/(2*pi);

                    % E_n^2 = INT psi^2 dV, separable and closed form
                    ax = cfg.len_chamber;  if l > 0; ax = ax/2; end
                    tg = 2*pi;             if m > 0; tg = pi;   end
                    if alpha_ms == 0
                        rad = cfg.rad_chamber^2/2;
                    else
                        Jm  = besselj(m, alpha_ms);
                        rad = 0.5*cfg.rad_chamber^2*(1 - m^2/alpha_ms^2)*Jm^2;
                    end
                    modes(k).e_norm2       = ax*tg*rad;
                    modes(k).int_psi2_exit = tg*rad;
                    modes(k).int_psi       = burn_overlap(l, m, alpha_ms, cfg, gas);
                end
            end
        end

    case 'rectangular'
        for l = 0:cfg.n_axial
            for m = 0:cfg.n_tang
                for s = 0:cfg.n_radial
                    if l == 0 && m == 0 && s == 0; continue; end
                    kn2 = pi^2*((l/cfg.len_chamber)^2 + (m/cfg.wid_chamber)^2 ...
                                + (s/cfg.hgt_chamber)^2);
                    k = k + 1;
                    modes(k).mode_id = sprintf('X%dY%dZ%d', l, m, s);
                    modes(k).l = l;  modes(k).m = m;  modes(k).s = s;
                    modes(k).kappa_ms = NaN;  modes(k).alpha_ms = 0;
                    modes(k).k_wave  = sqrt(kn2);
                    modes(k).omega   = gas.a_sound*sqrt(kn2);
                    modes(k).freq_hz = modes(k).omega/(2*pi);
                    fx = cfg.len_chamber;  if l > 0; fx = fx/2; end
                    fy = cfg.wid_chamber;  if m > 0; fy = fy/2; end
                    fz = cfg.hgt_chamber;  if s > 0; fz = fz/2; end
                    modes(k).e_norm2       = fx*fy*fz;
                    modes(k).int_psi2_exit = fy*fz;
                    modes(k).int_psi       = burn_overlap(l, m, 0, cfg, gas);
                end
            end
        end
end

[~, ord] = sort([modes.freq_hz]);
modes = modes(ord);
if numel(modes) > cfg.n_modes_keep
    modes = modes(1:cfg.n_modes_keep);
end
end

% =========================================================================
function ov = burn_overlap(l, m, alpha_ms, cfg, gas)
% Overlap of a mode with the heat-release distribution, the factor that
% multiplies the heat-release amplitude in the growth constant of Eq (75).
%
% The burning zone is axisymmetric and sits a short distance downstream of
% the injector face:
%   Qhat(x,r) = exp(-((x - x_burn)/w_burn)^2) exp(-(r/r_burn)^2)
% A tangential mode (m > 0) integrates to zero against an axisymmetric
% source, which is why transverse modes need asymmetry to be driven.

if m > 0
    ov = 0;
    return;
end

nx = 400;
x  = linspace(0, cfg.len_chamber, nx);
qx = exp(-((x - cfg.x_burn)/cfg.w_burn).^2);
px = cos(l*pi*x/cfg.len_chamber);
ax_ratio = trapz(x, qx.*px)/trapz(x, qx);

nr = 200;
r  = linspace(0, cfg.rad_chamber, nr);
qr = exp(-(r/cfg.r_burn).^2);
if alpha_ms == 0
    pr = ones(size(r));
else
    pr = besselj(0, alpha_ms*r/cfg.rad_chamber);
end
rad_ratio = trapz(r, qr.*pr.*r)/trapz(r, qr.*r);

ov = ax_ratio*rad_ratio*gas.vol_chamber;
end

% =========================================================================
function a = besselj_prime_zero(m, idx)
% idx-th non-negative root of J_m'(x) = 0, the hard-wall radial eigenvalue.
% idx = 1 returns 0 for m = 0 (the uniform radial profile).
persistent tbl
if isempty(tbl)
    tbl = containers.Map('KeyType','double','ValueType','any');
    tbl(0) = [0, 3.8317, 7.0156, 10.1735, 13.3237];
    tbl(1) = [1.8412, 5.3314, 8.5363, 11.7060, 14.8636];
    tbl(2) = [3.0542, 6.7061, 9.9695, 13.1704, 16.3475];
    tbl(3) = [4.2012, 8.0152, 11.3459, 14.5858, 17.7887];
    tbl(4) = [5.3175, 9.2824, 12.6819, 15.9641, 19.1960];
end
if isKey(tbl, m)
    v = tbl(m);
    a = v(min(idx, numel(v)));
else
    a = m + 0.8086*m^(1/3) + (idx-1)*pi;    % McMahon asymptote
end
end

% =========================================================================
function c = modes_default_cfg()
c.geom_type   = 'cylindrical';
c.len_chamber = 0.50;
c.rad_chamber = 0.15;
c.wid_chamber = 0.30;
c.hgt_chamber = 0.30;
c.p_mean      = 20.7e6;
c.t_mean      = 3600;
c.gamma_gas   = 1.22;
c.r_gas       = 8314/7.5;
c.cv_liquid   = 1700;
c.load_liquid = 0.05;
c.n_axial     = 2;
c.n_tang      = 2;
c.n_radial    = 2;
c.n_modes_keep= 8;
c.x_burn      = 0.08;
c.w_burn      = 0.06;
c.r_burn      = 0.10;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f); if ~isfield(a,f{i}); a.(f{i}) = d.(f{i}); end; end
end
