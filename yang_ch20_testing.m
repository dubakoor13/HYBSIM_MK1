function res = yang_ch20_testing(cfg)
% YANG_CH20_TESTING  Chapters 20 & 21 - stability testing and scaling.
%   Ch.20 Denisov, Kadishevich, Povolotzky & Sarychev, Eqs (1)-(20)
%   Ch.21 Fisher, Dodd & Jensen, Eqs (1)-(30)
%
% Ch.20 implements the NIICHIMMASH spectral-statistics acceptance method:
% mean amplitude and regularity per spectral line (Eqs 1-3), the Student
% essentiality test (Eq 4), the Fisher functional-dependence test (Eq 5),
% the non-promising and parameter-preference conditions (Eqs 6-8), the
% amplitude-time law (Eq 9), amplitude ratios (Eqs 10-13), the probability
% and limit-amplitude extrapolation (Eqs 14-16), and the multi-factor
% limit-state probability with its confidence bound (Eqs 17,18), plus
% periodogram spectral estimation with chi-square confidence limits.
%
% Ch.21 implements the similarity groups and scaling laws used to design a
% subscale stability test article.
%
%   res = yang_ch20_testing(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

%% ======================================================================
%  CH.20 - SPECTRAL STATISTICS
%% ======================================================================
% Synthesise (or accept) a pressure record and its spectrogram.
if isempty(cfg.signal)
    [sig, t] = synth_record(cfg);
else
    sig = cfg.signal(:).';   t = (0:numel(sig)-1)/cfg.fs;
end
st.time = t;  st.signal = sig;  st.fs = cfg.fs;

% ---- periodogram, I_N(w) = (1/(2 pi N)) |SUM x_t e^{-i w t}|^2 ----------
n   = numel(sig);
nfft= 2^nextpow2(n);
X   = fft(sig - mean(sig), nfft);
f   = (0:nfft/2)*cfg.fs/nfft;
Ixx = abs(X(1:nfft/2+1)).^2/(2*pi*n);
st.freq_hz    = f;
st.periodogram= Ixx;

% ---- block-averaged spectra -> per-line amplitude statistics -----------
nb   = cfg.n_blocks;
blen = floor(n/nb);
amps = zeros(nb, numel(f));
for b = 1:nb
    seg = sig((b-1)*blen + (1:blen));
    Xb  = fft((seg - mean(seg)).*hann_win(blen), nfft);
    amps(b,:) = 2*abs(Xb(1:nfft/2+1))/blen;
end
st.block_amps = amps;

% Eq (1): mean amplitude of the lines that actually appear
%   A_bar_fi = SUM A_fi / N_fi
% Eq (2): regularity  R_fi = N_fi / n
% Eq (3): mean amplitude over all blocks  A_bar = SUM A_i / n
present = amps > cfg.amp_threshold;
st.n_present   = sum(present, 1);                      % N_fi
st.regularity  = st.n_present/nb;                      % Eq (2)
st.mean_present= sum(amps.*present, 1)./max(st.n_present, 1);  % Eq (1)
st.mean_all    = mean(amps, 1);                        % Eq (3)
st.std_line    = std(amps, 0, 1);

% Dominant spectral lines.  Sorting alone returns the same peak several
% times because leakage spreads a tone over adjacent bins, so enforce a
% minimum separation before accepting a line.
[pk, ip] = sort(st.mean_all, 'descend');
keep = [];
for i = 1:numel(ip)
    if numel(keep) >= cfg.n_lines; break; end
    if isempty(keep) || all(abs(f(ip(i)) - f(keep)) > cfg.line_sep_hz)
        keep(end+1) = ip(i); %#ok<AGROW>
    end
end
st.lines = struct([]);
for i = 1:numel(keep)
    j = keep(i);
    st.lines(i).freq_hz    = f(j);
    st.lines(i).amp_mean   = st.mean_all(j);
    st.lines(i).amp_present= st.mean_present(j);
    st.lines(i).regularity = st.regularity(j);
    st.lines(i).std        = st.std_line(j);
    % Regular high-amplitude lines are the ones the method flags.
    st.lines(i).flagged    = st.regularity(j) > cfg.reg_threshold ...
                             && st.mean_all(j) > cfg.amp_threshold;
end
st.peak_amp = pk(1);
st.peak_f   = f(keep(1));

%% ---- Eq (4): Student essentiality test between two configurations -----
g1 = cfg.group1;  g2 = cfg.group2;
tst.mean1 = mean(g1);  tst.mean2 = mean(g2);
tst.s1    = std(g1);   tst.s2    = std(g2);
tst.N1    = numel(g1); tst.N2    = numel(g2);
tst.dof   = tst.N1 + tst.N2 - 2;
tst.t_stat= abs(tst.mean1 - tst.mean2)/sqrt(tst.s1^2 + tst.s2^2);
tst.t_crit= student_inv(cfg.confidence, tst.dof);   % one-sided at gamma
tst.essential = (tst.t_stat - tst.t_crit) >= 0;        % Eq (4)

% Eq (5): Fisher test for a functional dependence X = f(phi_i)
p    = polyfit(cfg.phi_param(:), cfg.x_response(:), 1);
xfit = polyval(p, cfg.phi_param(:));
tst.s_x0    = std(cfg.x_response(:));
tst.s_resid = std(cfg.x_response(:) - xfit);
tst.f_stat  = tst.s_x0^2/max(tst.s_resid^2, eps);
tst.f_crit  = cfg.f_critical;
tst.functional = (tst.f_stat - tst.f_crit) >= 0;       % Eq (5)
tst.fit_slope  = p(1);   tst.fit_intercept = p(2);

% Eq (6): non-promising condition  [N2/(N1+N2)] M2 + (gamma - 1) <= 0
tst.non_promising = (tst.N2/(tst.N1+tst.N2))*cfg.m2_observed ...
                    + (cfg.confidence - 1) <= 0;
% Eqs (7),(8): preference between two candidate parameters a and b
tst.pref_a  = tst.t_stat;
tst.pref_b  = cfg.t_stat_alt;
tst.prefer_a= (tst.pref_a - tst.pref_b) > 0;

%% ---- Eqs (9)-(16): amplitude growth and limit amplitude ---------------
% Eq (9): A_tau = A_0 + B_0 tau^beta [1/(nu - R_fi^alpha)]
tau = cfg.tau_axis(:).';
Rfi = mean(st.regularity(keep));
amp_law = cfg.A0_law + cfg.B0_law*tau.^cfg.beta_law ...
          ./max(cfg.nu_law - Rfi^cfg.alpha_law, eps);
lim.tau        = tau;
lim.amp_law    = amp_law;
lim.regularity = Rfi;

% Eqs (10)-(13): amplitude differences and their ratio
lim.dA_1 = cfg.amp_set1(:).' - cfg.amp_set2(:).';      % Eq (10)
lim.dA_2 = cfg.amp_set3(:).' - cfg.amp_set4(:).';
lim.K_i  = lim.dA_1./max(lim.dA_2, eps);               % Eq (11)
lim.K_bar= mean(lim.K_i);                              % Eq (13)
lim.K_std= std(lim.K_i);

% Eq (14): P = phi_st(K_i/S_K; N)
lim.P = student_cdf(lim.K_bar/max(lim.K_std,eps), numel(lim.K_i)-1);
% Eq (15): 1 - P = exp(-lambda A)  ->  lambda from the observed pair
lim.lambda_decay = -log(max(1 - lim.P, eps))/max(st.peak_amp, eps);
% Eq (16): A_lim = A_p log(1-gamma)/log(1-P)
lim.A_limit = st.peak_amp*log(1 - cfg.confidence)/log(max(1 - lim.P, eps));
lim.margin  = lim.A_limit/max(st.peak_amp, eps);

% Eqs (17),(18): multi-factor limit-state probability
lim.q0 = prod(cfg.q_factors);                          % Eq (17)
lim.P_upper = 1 - prod(cfg.q_uncond.*cfg.p_factors);   % Eq (18)
lim.P_within= cfg.p_lower < lim.P_upper;

%% ---- chi-square confidence band on the spectral estimate --------------
nu_chi = 2*nb;
st.chi_lo = nu_chi/chi2_inv(1 - cfg.alpha_spec/2, nu_chi);
st.chi_hi = nu_chi/chi2_inv(cfg.alpha_spec/2, nu_chi);
st.psd_lower = st.mean_all*st.chi_lo;
st.psd_upper = st.mean_all*st.chi_hi;

%% ======================================================================
%  CH.21 - SCALING
%% ======================================================================
fs = cfg.full;   ss = cfg.sub;
sc.scale_ratio = ss.diam/fs.diam;

for k = 1:2
    if k == 1; e = fs; nm = 'full'; else; e = ss; nm = 'sub'; end
    s.name    = nm;
    s.c_eq    = sqrt(e.gamma*e.r_gas*e.t_c);                 % Eq (4)
    s.rho     = e.p_c/(e.r_gas*e.t_c);
    s.a_throat= pi/4*e.d_throat^2;
    s.vol     = pi/4*e.diam^2*e.length;
    s.l_star  = s.vol/s.a_throat;                            % Eq (8)
    s.c_star  = e.p_c*s.a_throat/e.mdot;                     % Eq (27)
    s.eta_c   = (s.c_star - e.c_star_leak)/e.c_star_ideal;   % Eq (26)
    s.thrust  = e.p_c*s.a_throat*e.c_f;                      % Eq (6)
    s.mdot_sc = e.p_c*s.a_throat/sqrt(e.t_c)*e.gamma_f;      % Eq (7)
    s.tau_ch  = s.l_star/s.c_eq;                             % Eq (11)
    s.u_mean  = e.mdot/(s.rho*pi/4*e.diam^2);
    % Eq (9): cylindrical chamber acoustic frequencies
    s.f_1T = s.c_eq/(2*pi)*sqrt((1.8412/(e.diam/2))^2);
    s.f_1R = s.c_eq/(2*pi)*sqrt((3.8317/(e.diam/2))^2);
    s.f_1L = s.c_eq/(2*e.length);
    % Eq (10): slab-chamber counterpart
    s.f_slab = s.c_eq/2*sqrt((1/e.diam)^2 + (1/e.length)^2);
    % Eqs (12)-(16): similarity groups
    s.reynolds = s.rho*s.u_mean*e.diam/e.mu;                 % Eq (12)
    s.weber    = s.rho*s.u_mean^2*e.d_drop/e.sigma;          % Eq (13)
    s.mach     = s.u_mean/s.c_eq;                            % Eq (14)
    s.strouhal = s.f_1T*e.diam/s.u_mean;                     % Eq (15)
    s.damkohler= s.tau_ch/e.tau_chem;                        % Eq (16)
    % Eqs (20)-(23): transport similarity numbers
    s.alpha_th = e.k_cond/(s.rho*e.cp);                      % Eq (20)
    s.lewis    = s.alpha_th/e.diffusivity;                   % Eq (21)
    s.prandtl  = e.mu*e.cp/e.k_cond;                         % Eq (22)
    s.schmidt  = e.mu/(s.rho*e.diffusivity);                 % Eq (23)
    % Eq (5): droplet-size scaling group
    s.d_p_scaled = e.d_jet*(s.rho/e.rho_liq)^e.exp_a ...
                   *(e.mu_liq/e.mu)^e.exp_b*s.weber^e.exp_c;
    % Eqs (28),(29): injector hydraulics
    s.cd_inj  = e.mdot_actual/e.mdot_ideal;                  % Eq (28)
    s.dp_inj  = e.p_manifold - e.p_c;                        % Eq (29)
    s.mr      = e.mdot_ox/e.mdot_fuel;                       % Eq (30)
    % Eqs (17),(18): cavity damping
    s.zeta_cav= e.r_cav/(2*e.m_eff*2*pi*s.f_1T);             % Eq (17)
    s.q_cav   = 1/(2*max(s.zeta_cav,eps));                   % Eq (18)
    % Eq (19): bomb overpressure scaling
    s.dp_bomb = sqrt(e.e_bomb/s.vol);                        % Eq (19)
    % Eq (25): dynamic stability margin
    s.dsm     = (e.p_trigger - e.p_c)/e.p_c;                 % Eq (25)
    if k == 1; sc.full = s; else; sc.sub = s; end
end

% Similarity fidelity: which groups the subscale article actually preserves
grp = {'mach','weber','strouhal','damkohler','reynolds','prandtl','lewis'};
sc.similarity = struct();
for i = 1:numel(grp)
    r = sc.sub.(grp{i})/sc.full.(grp{i});
    sc.similarity.(grp{i}) = r;
    sc.matched.(grp{i}) = abs(r - 1) < cfg.match_tol;
end
sc.f_ratio_1T = sc.sub.f_1T/sc.full.f_1T;
sc.l_star_ratio = sc.sub.l_star/sc.full.l_star;
% Eqs (2),(3): the subscale cavity must be retuned to the subscale frequency
sc.cav_l_quarter_sub = sc.sub.c_eq/(4*sc.sub.f_1T);
sc.cav_v_helm_sub    = cfg.a_orifice*sc.sub.c_eq^2 ...
                       /((2*pi*sc.sub.f_1T)^2*cfg.l_orifice);

res.cfg = cfg;  res.spectral = st;  res.tests = tst;  res.limit = lim;
res.scaling = sc;
end

% =========================================================================
function [x, t] = synth_record(cfg)
% Damped-random-excitation pressure record with two resonant lines, used
% when the caller supplies no measured signal.
t  = (0:1/cfg.fs:cfg.t_record-1/cfg.fs);
rng(cfg.seed);
x  = cfg.noise_level*randn(size(t));
for k = 1:numel(cfg.tone_hz)
    env = cfg.tone_amp(k)*(0.6 + 0.4*sin(2*pi*cfg.tone_mod(k)*t));
    x   = x + env.*sin(2*pi*cfg.tone_hz(k)*t + 2*pi*rand);
end
end

function w = hann_win(n)
w = 0.5*(1 - cos(2*pi*(0:n-1)/(n-1)));
end

function p = student_cdf(t, nu)
% Student t CDF via the regularized incomplete beta function.
if nu <= 0; p = 0.5; return; end
x = nu/(nu + t^2);
ib = betainc(x, nu/2, 0.5);
if t >= 0; p = 1 - 0.5*ib; else; p = 0.5*ib; end
end

function t = student_inv(p, nu)
% Inverse Student t by bisection on student_cdf.
lo = -50; hi = 50;
for k = 1:200
    mid = (lo+hi)/2;
    if student_cdf(mid, nu) < p; lo = mid; else; hi = mid; end
end
t = (lo+hi)/2;
end

function x = chi2_inv(p, nu)
% Inverse chi-square by bisection on the regularized lower incomplete gamma.
lo = 0; hi = 10*nu + 100;
for k = 1:300
    mid = (lo+hi)/2;
    if gammainc(mid/2, nu/2) < p; lo = mid; else; hi = mid; end
end
x = (lo+hi)/2;
end

% =========================================================================
function c = default_cfg()
c.signal = [];   c.fs = 20000;   c.t_record = 2.0;   c.seed = 7;
c.noise_level = 0.05;
c.tone_hz  = [1200 2400 3600];
c.tone_amp = [0.60 0.25 0.10];
c.tone_mod = [3 7 11];
c.n_blocks = 20;   c.n_lines = 6;   c.line_sep_hz = 150;
c.amp_threshold = 0.05;   c.reg_threshold = 0.5;
c.confidence = 0.95;   c.alpha_spec = 0.05;
c.group1 = [0.42 0.51 0.38 0.47 0.44 0.49];
c.group2 = [0.71 0.68 0.79 0.74 0.66 0.77];
c.phi_param  = [0.10 0.15 0.20 0.25 0.30 0.35];
c.x_response = [0.30 0.38 0.47 0.53 0.62 0.71];
c.f_critical = 4.28;   c.m2_observed = 0.8;   c.t_stat_alt = 1.5;
c.tau_axis = linspace(0, 5, 100);
c.A0_law = 0.05;  c.B0_law = 0.3;  c.beta_law = 0.7;
c.nu_law = 1.5;   c.alpha_law = 1.0;
c.amp_set1 = [0.8 0.9 0.7 0.85];   c.amp_set2 = [0.4 0.5 0.35 0.45];
c.amp_set3 = [0.6 0.7 0.55 0.65];  c.amp_set4 = [0.3 0.4 0.28 0.36];
c.q_factors = [0.90 0.85 0.92];
c.q_uncond  = [0.95 0.93 0.96];
c.p_factors = [0.10 0.12 0.08];
c.p_lower   = 0.05;
c.a_orifice = 7.85e-5;  c.l_orifice = 0.010;
c.match_tol = 0.10;

% Throat diameters are sized from A_t = mdot c*/Pc so the reported c* and
% efficiency are self-consistent, and the subscale throat area scales with
% the square of the linear scale ratio (1/3).
c.full = engine_defaults(0.30, 0.50, 0.1202, 100.0);
c.sub  = engine_defaults(0.10, 0.20, 0.0401, 11.1);
end

function e = engine_defaults(diam, len, dth, mdot)
e.diam = diam;  e.length = len;  e.d_throat = dth;  e.mdot = mdot;
e.p_c = 20.7e6;  e.t_c = 3600;  e.gamma = 1.22;  e.r_gas = 8314/7.5;
e.c_f = 1.7;  e.gamma_f = 0.65;  e.c_star_ideal = 2350;  e.c_star_leak = 20;
e.mu = 9.0e-5;  e.cp = 3500;  e.k_cond = 0.40;  e.diffusivity = 3.0e-5;
e.sigma = 0.013;  e.d_drop = 1.0e-4;  e.rho_liq = 1140;  e.mu_liq = 2.0e-4;
e.d_jet = 2.0e-3;  e.exp_a = -0.3;  e.exp_b = 0.1;  e.exp_c = -0.4;
e.tau_chem = 2.0e-4;
e.mdot_actual = 0.95;  e.mdot_ideal = 1.0;
e.p_manifold = 24.0e6;
e.mdot_ox = 0.75*mdot;  e.mdot_fuel = 0.25*mdot;
e.r_cav = 500;  e.m_eff = 0.01;  e.e_bomb = 50;
e.p_trigger = 24.0e6;
end

function a = merge_defaults(a, d)
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(a,f{i}); a.(f{i}) = d.(f{i});
    elseif isstruct(d.(f{i})) && isstruct(a.(f{i}))
        a.(f{i}) = merge_defaults(a.(f{i}), d.(f{i}));
    end
end
end
