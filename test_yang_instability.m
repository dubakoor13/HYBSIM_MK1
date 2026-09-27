function test_yang_instability()
% TEST_YANG_INSTABILITY  Verification suite for the Yang & Anderson (1995)
% combustion instability library.
%
% Checks that every module runs, that results are finite and physically
% signed, and that key equations reproduce known analytical limits.

fprintf('\n=== YANG INSTABILITY LIBRARY -- TEST SUITE ===\n\n');
np = 0;  nf = 0;

%% ---- 1. all modules execute and return finite results -----------------
group('1. Module execution');
mods = {'ch01','ch02','ch06','ch08','ch10','ch12','ch13','ch14','ch15', ...
        'ch18','ch20'};
R = struct();
for i = 1:numel(mods)
    try
        r = yang_instability_main('modules', mods(i), 'quiet', true);
        R.(mods{i}) = r.(mods{i});
        [ok, bad] = all_finite(r.(mods{i}));
        [np,nf] = chk(np, nf, ok, sprintf('%s runs and is finite', mods{i}), bad);
    catch ME
        [np,nf] = chk(np, nf, false, sprintf('%s runs', mods{i}), ME.message);
    end
end

%% ---- 2. Ch.1 acoustics against closed-form results --------------------
group('2. Ch.1 modal acoustics');
a = R.ch01;
c_expect = sqrt(1.22*(8314/7.5)*3600);
[np,nf] = chk(np, nf, rel(a.gas.a_sound, c_expect) < 1e-10, ...
              'sound speed = sqrt(gamma R T)');
% First longitudinal mode of a hard-walled tube: f = c/(2L)
f1L = c_expect/(2*0.50);
got = a.modes(1).freq_hz;
[np,nf] = chk(np, nf, rel(got, f1L) < 0.02, ...
              sprintf('1L mode = c/(2L)  (%.1f vs %.1f Hz)', got, f1L));
% First tangential mode of a cylinder: f = 1.8412 c/(2 pi R)
f1T = 1.8412*c_expect/(2*pi*0.15);
have1T = any(arrayfun(@(m) rel(m.freq_hz, f1T) < 0.02, a.modes));
[np,nf] = chk(np, nf, have1T, sprintf('1T mode = 1.8412 c/(2 pi R) = %.0f Hz', f1T));
% Damping must be negative, and mode frequencies must increase
[np,nf] = chk(np, nf, all([a.growth.alpha_vis] < 0), 'viscous damping is negative');
[np,nf] = chk(np, nf, all([a.growth.alpha_noz] <= 0), 'nozzle damping is non-positive');
[np,nf] = chk(np, nf, issorted([a.modes.freq_hz]), 'modes sorted by frequency');
% Axisymmetric heat release cannot drive a tangential mode
tang = arrayfun(@(m) m.m > 0, a.modes);
[np,nf] = chk(np, nf, all(abs([a.modes(tang).int_psi]) < 1e-12), ...
              'tangential modes have zero overlap with axisymmetric Q');
% Rayleigh: in-phase heat release must give positive alpha
[np,nf] = chk(np, nf, a.rayleigh(1).alpha > 0, ...
              'Rayleigh alpha > 0 for in-phase heat release');
% Time lag: cos(omega tau) > 0 must coincide with the destabilising flag
for i = 1:numel(a.timelag)
    okk = a.timelag(i).destab == (cos(a.timelag(i).phase_rad) > 0);
    if ~okk; break; end
end
[np,nf] = chk(np, nf, okk, 'time-lag destabilising window matches cos(omega tau) > 0');

%% ---- 3. Ch.1 n-tau response limits ------------------------------------
group('3. Ch.1 n-tau response');
% At omega*tau = 0 the response 1 - exp(-i omega tau) must vanish
r0 = yang_ch01_acoustics(struct('tau_lag', 0));
[np,nf] = chk(np, nf, abs(r0.timelag(1).resp) < 1e-12, ...
              'zero time lag gives zero response');
% At omega*tau = pi the real part must be 2n (maximum out-of-phase)
om1 = r0.modes(1).omega;
rp  = yang_ch01_acoustics(struct('tau_lag', pi/om1, 'n_interact', 1));
[np,nf] = chk(np, nf, rel(rp.timelag(1).resp_real, 2) < 1e-6, ...
              'omega*tau = pi gives Re{response} = 2n');
[np,nf] = chk(np, nf, abs(rp.timelag(1).resp_imag) < 1e-6, ...
              'omega*tau = pi gives Im{response} = 0');

%% ---- 4. Ch.2 engine correlations --------------------------------------
group('4. Ch.2-5 correlations');
b = R.ch02;
[np,nf] = chk(np, nf, rel(b.perf.eta_c_star, 1.0) < 0.02, ...
              'c* efficiency ~ 1 for a self-consistent throat');
[np,nf] = chk(np, nf, b.perf.isp > 350 && b.perf.isp < 470, ...
              sprintf('Isp in the LOX/LH2 band (%.0f s)', b.perf.isp));
[np,nf] = chk(np, nf, b.inj.mom_ratio > 0, 'momentum ratio positive');
[np,nf] = chk(np, nf, b.cav.f_quarter > 0 && b.cav.f_helm > 0, ...
              'resonator frequencies positive');
% Quarter-wave scaling: doubling the length must halve the frequency
b2 = yang_ch02_engine_corr(struct('l_quarter', 2*b.cfg.l_quarter));
[np,nf] = chk(np, nf, b2.cav.f_quarter < b.cav.f_quarter, ...
              'longer quarter-wave tube -> lower frequency');
% Henry's law must be linear in partial pressure
h1 = yang_ch02_engine_corr(struct('p_partial', 1e6));
h2 = yang_ch02_engine_corr(struct('p_partial', 2e6));
[np,nf] = chk(np, nf, rel(h2.storable.ppm_dissolved, 2*h1.storable.ppm_dissolved) < 1e-10, ...
              'Henry law linear in partial pressure');

%% ---- 5. Ch.6 atomization ----------------------------------------------
group('5. Ch.6-7 atomization');
d = R.ch06;
[np,nf] = chk(np, nf, d.smd.recommended > 1e-6 && d.smd.recommended < 1e-3, ...
              sprintf('recommended SMD is physical (%.1f um)', d.smd.recommended*1e6));
[np,nf] = chk(np, nf, d.dist.n_rr > 0.5 && d.dist.n_rr < 10, ...
              sprintf('Rosin-Rammler N in range (%.2f)', d.dist.n_rr));
[np,nf] = chk(np, nf, d.sheet.lambda > 0 && d.sheet.omega > 0, ...
              'sheet wavelength and growth rate positive');
% Higher relative velocity must produce a shorter dominant wavelength
d2 = yang_ch06_atomization(struct('v_gas', 600));
[np,nf] = chk(np, nf, d2.sheet.lambda < d.sheet.lambda, ...
              'higher shear -> shorter wavelength');
% Eq (11) root must lie in (0,1]
[np,nf] = chk(np, nf, d.sheet.f_ratio > 0 && d.sheet.f_ratio <= 1, ...
              'sheet F-ratio root in (0,1]');
% Number distribution must integrate to a positive, finite SMD
[np,nf] = chk(np, nf, d.dist.smd_discrete > 0 && isfinite(d.dist.smd_discrete), ...
              'discrete SMD from the N-T distribution is finite');

%% ---- 6. Ch.8 breakup --------------------------------------------------
group('6. Ch.8-9 breakup');
e = R.ch08;
[np,nf] = chk(np, nf, e.secondary.t_break > 0, 'breakup time positive');
[np,nf] = chk(np, nf, e.secondary.d_deform > e.cfg.d_drop0, ...
              'deformed diameter exceeds the initial diameter');
% Weber regime ladder must be monotonic in We
regs = {};
for we = [5 20 60 200 800]
    rr = yang_ch08_breakup(struct('u_rel', sqrt(we*0.030/(5.0*2.0e-4))));
    regs{end+1} = rr.secondary.regime; %#ok<AGROW>
end
[np,nf] = chk(np, nf, numel(unique(regs)) >= 4, ...
              'secondary breakup regime map spans multiple regimes');
% Implicit Eq (15) solution must satisfy its own equation
L = e.cfg.length_scale;  smd = e.turbulent.smd_initial;
dr = e.cfg.rho_gas/e.cfg.rho_liq;
lhs = smd/L*(1 + 0.04*dr*(e.cfg.u_mean/e.cfg.v_rms)^2*(L/smd)^(2/3))^(3/5);
rhs = 76*e.turbulent.we_lambda^(-0.69);
[np,nf] = chk(np, nf, rel(lhs, rhs) < 1e-6, ...
              'implicit SMD_i solution satisfies Eq (15)');

%% ---- 7. Ch.10 damping and vaporization --------------------------------
group('7. Ch.10-11 damping and vaporization');
g = R.ch10;
[np,nf] = chk(np, nf, rel(g.damping.q_factor, 50) < 0.05, ...
              sprintf('Q factor ~ 50 from the log decrement (%.1f)', g.damping.q_factor));
[np,nf] = chk(np, nf, rel(g.damping.decrement, 2*pi*g.damping.zeta) < 1e-6, ...
              'log decrement = 2 pi zeta');
[np,nf] = chk(np, nf, all(diff(g.vaporization.d_drop) <= 1e-12), ...
              'droplet diameter decreases monotonically');
[np,nf] = chk(np, nf, g.vaporization.d_drop(1) == g.cfg.d_drop_init, ...
              'vaporization starts at the initial diameter');
% Classical d^2 law: alpha_v = 1 must reproduce D^2 = Di^2 - Kv t exactly
g1 = yang_ch10_damping(struct('alpha_vap', 1));
err = max(abs(g1.vaporization.d_drop.^2 - g1.vaporization.d2_law));
[np,nf] = chk(np, nf, err < 1e-18, 'alpha_v = 1 recovers the classical d^2 law');
% Resonator peak absorption must occur at its own resonant frequency
[~, ia] = max(g.resonator.absorb);
[np,nf] = chk(np, nf, rel(g.resonator.freq_hz(ia), g.resonator.f0) < 0.10, ...
              'resonator absorbs most at f0');

%% ---- 8. Ch.13 nonlinear limit cycles ----------------------------------
group('8. Ch.13 limit cycles');
h = R.ch13;
[np,nf] = chk(np, nf, h.limit_cycle.exists, 'limit cycle exists for a1*a2 < 0');
[np,nf] = chk(np, nf, rel(h.sim.r1_final, h.limit_cycle.r1) < 0.05, ...
              'integrated r1 matches the analytical limit cycle');
[np,nf] = chk(np, nf, rel(h.sim.r2_final, abs(h.limit_cycle.r2)) < 0.05, ...
              'integrated r2 matches the analytical limit cycle');
[np,nf] = chk(np, nf, h.sim.converged, 'amplitude integration converged');
% A stable pair (both alpha < 0) must decay to zero
hs = yang_ch13_nonlinear(struct('alpha_1', -200, 'alpha_2', -300));
[np,nf] = chk(np, nf, hs.sim.r1_final < hs.cfg.r1_init, ...
              'both modes damped -> amplitude decays');
% Every response model must run
for m = {'quadratic','abs_u','p_abs_u','third','mean_flow'}
    try
        hm = yang_ch13_nonlinear(struct('model', m{1}));
        okm = isfinite(hm.sim.r1_final);
    catch; okm = false; end
    [np,nf] = chk(np, nf, okm, sprintf('response model "%s" integrates', m{1}));
end

%% ---- 9. Ch.14 cavity design -------------------------------------------
group('9. Ch.14 cavity');
k = R.ch14;
[np,nf] = chk(np, nf, k.tuned_ok, 'default cavity is tuned onto the target mode');
[np,nf] = chk(np, nf, all(k.absorption.alpha >= 0 & k.absorption.alpha <= 1.0001), ...
              'absorption coefficient stays within [0,1]');
[np,nf] = chk(np, nf, abs(k.absorption.f_best - k.chamber.f_target) ...
                      /k.chamber.f_target < 0.15, ...
              'absorption peak lands near the target mode');
% The design formula must be self-consistent: the required length retunes it
k2 = yang_ch14_cavity(struct('l_quarter', k.resonator.l_required));
[np,nf] = chk(np, nf, rel(k2.resonator.f_quarter, k.chamber.f_target) < 0.02, ...
              'l_required retunes the quarter-wave onto the target');
% Hotter gas must raise the tuning frequency
k3 = yang_ch14_cavity(struct('t_chamber', 3600*1.44));
[np,nf] = chk(np, nf, k3.resonator.f_quarter > k.resonator.f_quarter, ...
              'higher temperature -> higher tuning frequency');

%% ---- 10. Ch.15 analytical / Ch.18 numerical ---------------------------
group('10. Ch.15-19 analytical and numerical');
m = R.ch15;
[np,nf] = chk(np, nf, m.turbulence.mach > 0 && m.turbulence.mach < 1, ...
              'chamber Mach number is subsonic');
% Eq (70): the amplitude follows the sign of the net growth rate.  With the
% turbulence branch now built on the shared damping budget, a stable chamber
% must decay rather than grow.
lam_ls = m.turbulence.modes(1).growth;
if lam_ls > 0
    [np,nf] = chk(np, nf, m.turbulence.landau.amp(end) > m.cfg.a_init, ...
                  'Landau-Stuart grows when the net rate is positive');
    [np,nf] = chk(np, nf, ...
        rel(m.turbulence.landau.amp(end), m.turbulence.landau.a_sat) < 0.05, ...
        'Landau-Stuart saturates at sqrt(lambda/c)');
else
    [np,nf] = chk(np, nf, m.turbulence.landau.amp(end) < m.cfg.a_init, ...
                  'Landau-Stuart decays when the net rate is negative');
    [np,nf] = chk(np, nf, ~m.turbulence.landau.saturates, ...
                  'no saturation amplitude for a damped mode');
end
% Forcing a driven mode must reproduce the saturation branch.
mg = yang_ch15_analytical(struct('q_amp', 4.0e11, 'q_factor', 400));
if mg.turbulence.modes(1).growth > 0
    [np,nf] = chk(np, nf, ...
        rel(mg.turbulence.landau.amp(end), mg.turbulence.landau.a_sat) < 0.05, ...
        'driven case saturates at sqrt(lambda/c)');
end
n = R.ch18;
[np,nf] = chk(np, nf, n.spray.cd > 0 && n.spray.cd < 100, 'drag coefficient physical');
[np,nf] = chk(np, nf, n.spray.W_gas_vap > 0, 'gas gains the mass the liquid loses');
[np,nf] = chk(np, nf, rel(n.spray.W_gas_vap, -n.spray.W_liq_vap) < 1e-12, ...
              'vaporization mass source conserves mass');
[np,nf] = chk(np, nf, n.spray.f_gas == -n.spray.f_drag, ...
              'drag on the gas is equal and opposite to that on the drops');
% Cd must switch branches at Re = 1000 continuously enough to stay bounded
lo = yang_ch18_numerical(struct('u_drop', 119.9));
[np,nf] = chk(np, nf, lo.spray.cd > 0, 'Cd branch below Re = 1000 is positive');
% Euler flux consistency: E(1) must equal Q(2)
[np,nf] = chk(np, nf, rel(n.cfd.E(1), n.cfd.Q(2)) < 1e-12, ...
              'Euler flux E(1) = Q(2) = rho u');
[np,nf] = chk(np, nf, n.cfd.b_number > 0, 'Priem-Heidmann transfer number positive');

%% ---- 11. Ch.20 statistics and scaling ---------------------------------
group('11. Ch.20-21 testing and scaling');
q = R.ch20;
[np,nf] = chk(np, nf, abs(q.spectral.peak_f - 1200) < 60, ...
              sprintf('dominant line found at the injected tone (%.0f Hz)', q.spectral.peak_f));
freqs = [q.spectral.lines.freq_hz];
[np,nf] = chk(np, nf, numel(unique(round(freqs/100))) == numel(freqs), ...
              'spectral lines are distinct (leakage de-duplicated)');
[np,nf] = chk(np, nf, q.tests.t_crit > 0, 'Student critical value is positive');
[np,nf] = chk(np, nf, q.tests.essential, 'well-separated groups test as essential');
[np,nf] = chk(np, nf, q.tests.functional, 'a clean linear trend tests as functional');
[np,nf] = chk(np, nf, all(q.spectral.regularity >= 0 & q.spectral.regularity <= 1), ...
              'regularity stays in [0,1]');
% Scaling: acoustic frequency must scale inversely with size
[np,nf] = chk(np, nf, q.scaling.sub.f_1T > q.scaling.full.f_1T, ...
              'smaller chamber -> higher 1T frequency');
[np,nf] = chk(np, nf, rel(q.scaling.f_ratio_1T, 1/q.scaling.scale_ratio) < 1e-6, ...
              '1T frequency ratio = inverse of the length scale ratio');
[np,nf] = chk(np, nf, q.scaling.matched.mach, 'Mach number preserved in the subscale');
[np,nf] = chk(np, nf, rel(q.scaling.full.c_star, 2350) < 0.02, ...
              'full-scale c* matches the ideal value');

%% ---- 12. Ch.1 vs Ch.15 consistency ------------------------------------
group('12. Ch.1 / Ch.15 cross-consistency');
% Both chapters must describe the same chamber.  They share the mode solver
% and the growth budget, so:
%   (a) mode frequencies agree exactly;
%   (b) with the same combustion closure, the only difference is Mitchell's
%       Green's-function coupling term;
%   (c) switching that coupling off makes them numerically identical.
a1 = R.ch01;  m1 = R.ch15.mitchell;
n  = min(numel(a1.growth), numel(m1.modes));
% Unperturbed eigenfrequencies must be bit-identical: same solver, same modes.
fdiff = max(abs([a1.growth(1:n).freq_hz] - [m1.modes(1:n).freq0]));
[np,nf] = chk(np, nf, fdiff < 1e-9, ...
              sprintf('unperturbed frequencies identical (max diff %.2e Hz)', fdiff));
% The frequency each chapter REPORTS includes the Eq (56) combustion shift,
% which is closure-dependent and must stay small -- a large shift was the
% symptom of the original bug (it reached -8.7%).
shift = max(abs([m1.modes(1:n).freq_hz] - [m1.modes(1:n).freq0]) ...
            ./ [m1.modes(1:n).freq0]);
[np,nf] = chk(np, nf, shift < 0.01, ...
              sprintf('Eq (56) frequency shift stays under 1%% (%.3g%%)', shift*100));

for closure = {'prescribed','crocco'}
    o = yang_instability_main('modules', {'ch01','ch15'}, 'quiet', true, ...
                              'damping', struct('comb_model', closure{1}));
    aa = [o.ch01.growth.alpha_net];
    bb = [o.ch15.mitchell.modes.lambda];
    cc = [o.ch15.mitchell.modes.coupling];
    k  = min(numel(aa), numel(bb));
    resid = max(abs((bb(1:k) - aa(1:k)) - cc(1:k)));
    [np,nf] = chk(np, nf, resid < 1e-9, ...
        sprintf('closure "%s": Ch15 - Ch1 equals the coupling term (resid %.2e)', ...
                closure{1}, resid));
end

% With the coupling off and the closure matched, the two must coincide.
o0 = yang_instability_main('modules', {'ch01','ch15'}, 'quiet', true, ...
                           'damping', struct('comb_model','prescribed'));
m0 = yang_ch15_analytical(struct('comb_model','prescribed','green_coupling',0));
aa = [o0.ch01.growth.alpha_net];
bb = [m0.mitchell.modes.lambda];
k  = min(numel(aa), numel(bb));
d0 = max(abs(bb(1:k) - aa(1:k)));
[np,nf] = chk(np, nf, d0 < 1e-9, ...
    sprintf('coupling off + matched closure -> identical (max diff %.2e)', d0));

% The Ch.16 turbulence branch must build on that budget, not replace it:
% its mean-field term is the Ch.15 growth rate itself.
tb = R.ch15.turbulence.modes;
[np,nf] = chk(np, nf, ...
    abs(tb(1).lambda_lin - m1.modes(1).lambda) < 1e-12, ...
    'Ch.16 mean-field growth rate is the Ch.15 budget, not a separate estimate');
[np,nf] = chk(np, nf, all([tb.stable]) == all([m1.modes.stable]), ...
    'turbulence branch agrees with the base budget on stability');

% Guard the sign bug that caused the original disagreement: the driving term
% is the REAL part of the n-tau response, n(1-cos wt), never the imaginary
% part n sin(wt).
gb = yang_growth_budget(a1.modes(1), a1.gas, ...
                        struct('comb_model','crocco','tau_lag',0,'n_interact',1));
[np,nf] = chk(np, nf, abs(gb.alpha_drive) < 1e-9, ...
              'crocco drive vanishes at zero lag (real part, not imaginary)');
om1 = a1.modes(1).omega;
gp  = yang_growth_budget(a1.modes(1), a1.gas, ...
                         struct('comb_model','crocco','tau_lag',pi/om1, ...
                                'n_interact',1));
[np,nf] = chk(np, nf, gp.alpha_drive > 0, ...
              'crocco drive is positive at omega*tau = pi (max in-phase)');

%% ---- 13. Ch.12 injection-coupled feed system --------------------------
group('13. Ch.12 feed system / Nyquist');
c12 = R.ch12;

% The old "|F| > 1 anywhere" criterion is wrong: amplification without a
% +/-180 deg phase crossover is not instability (Eqs 20 AND 21 both matter).
[np,nf] = chk(np, nf, c12.loop.mag_max > 1 && ~isempty(c12.loop.f_phase_cross), ...
    'default engine amplifies (|F|>1) AND has a genuine phase crossover');

% Gain margin, phase margin and the Nyquist encirclement count must all
% agree on the verdict for a system with no open-loop RHP poles.
margin_says_unstable = isfinite(c12.loop.gain_margin_db) ...
                       && c12.loop.gain_margin_db < 0;
[np,nf] = chk(np, nf, margin_says_unstable == c12.loop.nyquist_unstable, ...
    'gain-margin test and Eqs(20)&(21) test agree on stability');
[np,nf] = chk(np, nf, c12.loop.contour_closed, ...
    'Nyquist contour is closed (sweep reaches DC and rolls off)');
[np,nf] = chk(np, nf, (c12.loop.encirclements > 0) == c12.loop.unstable, ...
    'encirclement count and reported verdict agree');

% Sign convention check: raising the injector dP raises its resistance
% (R = 2 dP/Q), which raises the line impedance Z and so must MONOTONICALLY
% shrink the terminal admittance |a(s)| = (pc/mdot) rho/|Z| -- proving the
% dP -> R -> Z -> a chain, and its sign, were not silently flipped.
% NOTE: |F| = |R_c (A_I+A_B)| itself is NOT guaranteed to fall, because A_I
% and A_B combine as complex vectors -- shrinking |A_I| can change its phase
% enough to add more constructively with A_B than it did before, which is
% exactly the interference this Nyquist analysis exists to catch. So the
% monotonic quantity to test is |A_o|/|A_I|, not the diluted loop gain |F|.
decoupled = yang_ch12_injection(struct( ...
    'ox',   struct('dp_injector', 3.0e7), ...
    'fuel', struct('dp_injector', 3.5e7)));
[np,nf] = chk(np, nf, max(abs(decoupled.adm.ox)) < max(abs(c12.adm.ox)), ...
    'raising ox injector dP monotonically shrinks |A_o|');
[np,nf] = chk(np, nf, max(abs(decoupled.adm.fuel)) < max(abs(c12.adm.fuel)), ...
    'raising fuel injector dP monotonically shrinks |A_f|');
[np,nf] = chk(np, nf, decoupled.ox.r_injector > 9*c12.ox.r_injector, ...
    'injector resistance scales linearly with dp_injector');

% In the limit of an enormous injector dP the orifice impedance swamps
% everything upstream, so A_I -> 0 and F -> R_c*A_B exactly -- a clean,
% model-independent check that the feed path is being added, not ignored.
extreme = yang_ch12_injection(struct( ...
    'ox',   struct('dp_injector', 3.0e9), ...
    'fuel', struct('dp_injector', 3.0e9)));
[np,nf] = chk(np, nf, max(abs(extreme.loop.A_I)) < 1e-2, ...
    sprintf('an extreme injector dP drives A_I to ~0 (max %.2e)', ...
            max(abs(extreme.loop.A_I))));
Fexp = extreme.loop.R_c .* extreme.loop.A_B;
[np,nf] = chk(np, nf, max(abs(extreme.loop.F - Fexp)) < 1e-2*max(abs(Fexp)), ...
    'with A_I~0, F reduces to R_c*A_B as Eq (19) requires');

% Lumped (Eq 9 as written) is only valid on a short line; at the chamber
% mode frequency here it is already 5x past its own validity ceiling, so
% the transmission-line and lumped models must diverge substantially there
% -- silently trusting the lumped ladder at 2200+ Hz is exactly the bug that
% invented a false 1 Hz "feed resonance" during development.
[np,nf] = chk(np, nf, c12.adm.f_lumped_max_ox < c12.cfg.f_chamber/2, ...
    'lumped-model ceiling sits well below the chamber mode (transmission-line needed)');
% Compare the raw terminal admittance (not the diluted loop gain |F|, which
% is swamped by R_c and A_B and stays similar between feed models even when
% the duct physics differs -- see the interference note above) at a
% frequency safely below the ceiling, where the two models must nearly
% agree, and at the chamber mode, well past it, where they must not.
lumped_case = yang_ch12_injection(struct('feed_model', 'lumped'));
f_low = 0.3*c12.adm.f_lumped_max_ox;                   % inside validity
[~, i_tl_lo] = min(abs(c12.loop.freq_hz - f_low));
[~, i_lp_lo] = min(abs(lumped_case.loop.freq_hz - f_low));
d_low  = abs(abs(c12.adm.ox(i_tl_lo)) - abs(lumped_case.adm.ox(i_lp_lo))) ...
         /max(abs(c12.adm.ox(i_tl_lo)), eps);
[np,nf] = chk(np, nf, d_low < 0.10, ...
    sprintf('models agree well below the lumped ceiling (%.1f%% diff)', d_low*100));

f_probe = c12.cfg.f_chamber;                            % ~5x past the ceiling
[~, i_tl] = min(abs(c12.loop.freq_hz - f_probe));
[~, i_lp] = min(abs(lumped_case.loop.freq_hz - f_probe));
d_high = abs(abs(c12.adm.ox(i_tl)) - abs(lumped_case.adm.ox(i_lp))) ...
         /max(abs(c12.adm.ox(i_tl)), eps);
[np,nf] = chk(np, nf, d_high > d_low, ...
    sprintf('model divergence grows past the lumped ceiling (%.1f%% -> %.1f%%)', ...
            d_low*100, d_high*100));

% Feed resonance must be an interior peak of |a(s)|, not the DC value (the
% original feed_resonance() bug always returned ~1 Hz because admittance is
% largest at DC for a resistive line).
[np,nf] = chk(np, nf, c12.adm.f_res_ox > 100, ...
    sprintf('ox feed resonance is an interior peak, not DC (%.0f Hz)', c12.adm.f_res_ox));
[np,nf] = chk(np, nf, c12.adm.f_res_fuel > 100, ...
    sprintf('fuel feed resonance is an interior peak, not DC (%.0f Hz)', c12.adm.f_res_fuel));

% Reported phase crossovers must be genuine +/-180 deg crossings, not
% artifacts of the phase-wrap discontinuity.
for ii = 1:numel(c12.loop.f_cross_reported)
    [~, jj] = min(abs(c12.loop.freq_hz - c12.loop.f_cross_reported(ii)));
    ph_near = c12.loop.phase_deg(max(jj-2,1):min(jj+2,end));
    ok_cross = min(ph_near) < -170 || max(ph_near) > 170 || ...
               (max(ph_near) - min(ph_near)) > 150;
end
if numel(c12.loop.f_cross_reported) > 0
    [np,nf] = chk(np, nf, ok_cross, ...
        'reported phase crossovers sit near a genuine +/-180 deg point');
end

%% ---- summary ----------------------------------------------------------
fprintf('\n================================================\n');
if nf == 0
    fprintf('  ALL %d TESTS PASSED\n', np);
else
    fprintf('  %d passed, %d FAILED (of %d)\n', np, nf, np+nf);
end
fprintf('================================================\n\n');
end

% =========================================================================
function [np, nf] = chk(np, nf, cond, name, detail)
if nargin < 5; detail = ''; end
if cond
    fprintf('  [PASS] %s\n', name);  np = np + 1;
else
    fprintf('  [FAIL] %s', name);
    if ~isempty(detail); fprintf('   <- %s', detail); end
    fprintf('\n');  nf = nf + 1;
end
end

function group(t)
fprintf('\n%s\n', t);
fprintf('  %s\n', repmat('-', 1, numel(t)));
end

function r = rel(a, b)
r = abs(a - b)/max(abs(b), eps);
end

function [ok, bad] = all_finite(s, prefix)
% Recursively confirm every numeric leaf is finite, except for the fields
% where a non-finite value is the correct answer:
%   t_double    Inf when a mode is stable and never doubles
%   n_neutral   NaN where the neutral-stability curve asymptotes
%   r1, r2      NaN when no limit cycle exists
%   r_half      NaN when the profile never crosses half its centreline value
%   chi_quarter Inf at the cotangent poles of the quarter-wave reactance
allow = {'t_double','n_neutral','r1','r2','r_half','chi_quarter', ...
         'Z_quarter','f_neutral','threshold'};
if nargin < 2; prefix = ''; end
ok = true;  bad = '';
if isstruct(s)
    for i = 1:numel(s)
        f = fieldnames(s);
        for j = 1:numel(f)
            if any(strcmp(f{j}, allow)); continue; end
            [o, b] = all_finite(s(i).(f{j}), [prefix '.' f{j}]);
            if ~o; ok = false; bad = b; return; end
        end
    end
elseif isnumeric(s) && ~isempty(s)
    if ~all(isfinite(s(:)))
        ok = false;  bad = sprintf('non-finite at %s', prefix);
    end
end
end
