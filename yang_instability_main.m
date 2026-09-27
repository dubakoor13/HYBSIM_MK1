function out = yang_instability_main(varargin)
% YANG_INSTABILITY_MAIN  Driver for the Yang & Anderson (1995) liquid rocket
% engine combustion instability library.
%
% Runs every chapter module against one consistent engine definition and
% prints a consolidated stability assessment.
%
%   out = yang_instability_main()                 % run all modules
%   out = yang_instability_main('modules', {'ch01','ch13'})
%   out = yang_instability_main('quiet', true)
%   out = yang_instability_main('plots', true)
%
% Module map (553 equations across 21 chapters):
%   ch01  yang_ch01_acoustics    Ch.1     modal acoustics, growth, Rayleigh
%   ch02  yang_ch02_engine_corr  Ch.2-5   engine empirical correlations
%   ch06  yang_ch06_atomization  Ch.6-7   coaxial injector atomization
%   ch08  yang_ch08_breakup      Ch.8-9   impinging jets, spray breakup
%   ch10  yang_ch10_damping      Ch.10-11 damping stats, vaporization
%   ch12  yang_ch12_injection    Ch.12    injection-coupled instability
%   ch13  yang_ch13_nonlinear    Ch.13    nonlinear limit cycles
%   ch14  yang_ch14_cavity       Ch.14    acoustic cavity design
%   ch15  yang_ch15_analytical   Ch.15-17 analytical stability models
%   ch18  yang_ch18_numerical    Ch.18-19 numerical / CFD source terms
%   ch20  yang_ch20_testing      Ch.20-21 spectral testing and scaling
clc

p = parse_args(varargin);
all_mods = {'ch01','ch02','ch06','ch08','ch10','ch12','ch13','ch14', ...
            'ch15','ch18','ch20'};
if isempty(p.modules); mods = all_mods; else; mods = p.modules; end

if ~p.quiet
    fprintf('\n================================================================\n');
    fprintf('  LIQUID ROCKET ENGINE COMBUSTION INSTABILITY\n');
    fprintf('  Yang & Anderson (1995), AIAA Progress Series Vol. 169\n');
    fprintf('  MATLAB implementation -- 21 chapters, 553 equations\n');
    fprintf('================================================================\n\n');
end

out = struct();
out.engine = p.engine;

for i = 1:numel(mods)
    m = mods{i};
    tic;
    switch m
        case 'ch01'; out.ch01 = yang_ch01_acoustics(cfg_ch01(p.engine));
        case 'ch02'; out.ch02 = yang_ch02_engine_corr(cfg_ch02(p.engine));
        case 'ch06'; out.ch06 = yang_ch06_atomization(struct());
        case 'ch08'; out.ch08 = yang_ch08_breakup(struct());
        case 'ch10'; out.ch10 = yang_ch10_damping(struct());
        case 'ch12'; out.ch12 = yang_ch12_injection(cfg_ch12(p.engine));
        case 'ch13'; out.ch13 = yang_ch13_nonlinear(cfg_ch13(p.engine));
        case 'ch14'; out.ch14 = yang_ch14_cavity(cfg_ch14(p.engine));
        case 'ch15'; out.ch15 = yang_ch15_analytical(cfg_ch15(p.engine));
        case 'ch18'; out.ch18 = yang_ch18_numerical(struct());
        case 'ch20'; out.ch20 = yang_ch20_testing(struct());
        otherwise; warning('yang:module','unknown module "%s"', m); continue;
    end
    out.timing.(m) = toc;
end

if ~p.quiet; report(out, mods); end
if p.plots;  make_plots(out, mods); end
end

% =========================================================================
function report(out, mods)

if isfield(out,'ch01')
    r = out.ch01;
    section('CH.1  MODAL ACOUSTICS AND LINEAR STABILITY');
    fprintf('  Sound speed        : %8.1f m/s\n', r.gas.a_sound);
    fprintf('  Mean density       : %8.3f kg/m^3\n', r.gas.rho_mean);
    fprintf('  %-10s %10s %11s %11s %11s  %s\n', ...
            'mode','f [Hz]','drive','damp','net [1/s]','verdict');
    for i = 1:numel(r.growth)
        g = r.growth(i);
        fprintf('  %-10s %10.1f %11.2f %11.2f %11.2f  %s\n', ...
                g.mode_id, g.freq_hz, g.alpha_drive, ...
                g.alpha_noz + g.alpha_vis, g.alpha_net, verdict(g.alpha_net));
    end
    w = r.worst_mode;
    fprintf('  Worst mode         : %s at %.1f Hz, alpha = %.2f 1/s\n', ...
            w.mode_id, w.freq_hz, w.alpha_net);
    if isfinite(w.t_double)
        fprintf('  Amplitude doubling : %.4f s\n', w.t_double);
    end
    fprintf('  Closed-loop peak   : %.1f Hz, gain %.2f\n', ...
            r.control.peak_hz, r.control.peak_gain);
end

if isfield(out,'ch02')
    r = out.ch02;
    section('CH.2-5  ENGINE CORRELATIONS');
    fprintf('  O/F ratio          : %8.3f\n', r.inj.mass_ratio);
    fprintf('  Velocity ratio     : %8.2f    %s\n', r.inj.vel_ratio,  pf(r.inj.screen_vel));
    fprintf('  Momentum ratio J   : %8.2f    %s\n', r.inj.mom_ratio,  pf(r.inj.screen_mom));
    fprintf('  dP/Pc (fuel)       : %8.3f    %s\n', r.inj.dp_ratio_fuel, pf(r.inj.screen_dp));
    fprintf('  Reardon time lag   : %8.3f ms -> %.0f Hz\n', ...
            r.inj.tau_reardon*1e3, r.inj.f_reardon);
    fprintf('  c* efficiency      : %8.3f\n', r.perf.eta_c_star);
    fprintf('  Isp                : %8.1f s\n', r.perf.isp);
    fprintf('  RD-0110 gain K_A   : %8.2f at %.0f Hz   %s\n', ...
            r.rd.k_a_max, r.rd.f_at_max, pf(r.rd.acceptable));
    fprintf('  Ingebo drop size   : %8.1f um\n', r.hc.d_ingebo*1e6);
    fprintf('  Drop Eotvos        : %8.2f (crit 16)  %s\n', ...
            r.storable.eotvos, tf_str(r.storable.breaks_up,'breaks up','intact'));
end

if isfield(out,'ch06')
    r = out.ch06;
    section('CH.6-7  COAXIAL ATOMIZATION');
    fprintf('  We (aerodynamic)   : %8.1f\n', r.nd.we_aero);
    fprintf('  Ohnesorge          : %8.4f\n', r.nd.oh);
    fprintf('  SMD Nukiyama-Tan.  : %8.1f um  %s\n', r.smd.nukiyama*1e6, ...
            rng_tag(r.validity.nukiyama));
    fprintf('  SMD Mayer          : %8.3f um  %s\n', r.smd.d_mayer*1e6, ...
            rng_tag(r.validity.mayer));
    fprintf('  SMD from wave      : %8.3f um  %s\n', r.smd.d32_wave*1e6, ...
            rng_tag(r.validity.wave));
    fprintf('  MMD Kim-Marshall   : %8.1f um  %s\n', r.smd.mmd_kim*1e6, ...
            rng_tag(r.validity.kim_marshall));
    fprintf('  D32 Vulcain corr.  : %8.1f um  %s\n', r.smd.d32_vulcain, ...
            rng_tag(r.validity.vulcain));
    fprintf('  --> recommended    : %8.1f um  (%s)\n', ...
            r.smd.recommended*1e6, r.smd.recommended_src);
    if r.validity.any_invalid
        fprintf('  NOTE: some correlations are extrapolated past their\n');
        fprintf('        calibration range at this shear level -- see res.validity\n');
    end
    fprintf('  Dominant wave      : lambda %.1f um, Omega %.3e 1/s\n', ...
            r.sheet.lambda*1e6, r.sheet.omega);
    fprintf('  Breakup length     : %8.1f mm, cone %.1f deg\n', ...
            r.cone.length*1e3, r.cone.angle_deg);
    fprintf('  Rosin-Rammler      : D = %.1f um, N = %.2f\n', ...
            r.dist.d_rr*1e6, r.dist.n_rr);
end

if isfield(out,'ch08')
    r = out.ch08;
    section('CH.8-9  IMPINGING JETS AND SPRAY BREAKUP');
    fprintf('  Jet Weber          : %8.1f  (%s)\n', r.impinging.we_jet, r.impinging.regime);
    fprintf('  Breakup radius     : %8.2f mm\n', r.impinging.r_b*1e3);
    fprintf('  Sheet thickness    : %8.2f um\n', r.impinging.h_sheet*1e6);
    fprintf('  Squire wavelength  : %8.1f um, growth %.3e 1/s\n', ...
            r.impinging.lambda_squire*1e6, r.impinging.beta_squire);
    fprintf('  Ligament -> drop   : %8.1f um -> %.1f um\n', ...
            r.impinging.d_ligament*1e6, r.impinging.d_drop*1e6);
    fprintf('  Empirical drop     : %8.1f um\n', r.impinging.d_empirical*1e6);
    fprintf('  Cavitation number  : %8.2f   %s\n', r.impinging.cav_number, ...
            tf_str(r.impinging.cavitating,'CAVITATING','attached'));
    fprintf('  Secondary We       : %8.1f -> regime: %s\n', ...
            r.secondary.we, r.secondary.regime);
    fprintf('  Breakup time       : %8.3f ms\n', r.secondary.t_break*1e3);
    fprintf('  Post-breakup SMD   : %8.1f um\n', r.secondary.smd*1e6);
    fprintf('  Merged-breakup SMD : %8.1f um (theory %.1f um)\n', ...
            r.turbulent.smd_merged_emp*1e6, r.turbulent.smd_merged_th*1e6);
end

if isfield(out,'ch10')
    r = out.ch10;
    section('CH.10-11  DAMPING STATISTICS AND VAPORIZATION');
    fprintf('  Damping delta      : %8.2f 1/s, decrement %.4f\n', ...
            r.damping.delta, r.damping.decrement);
    fprintf('  Q factor           : %8.1f\n', r.damping.q_factor);
    fprintf('  Disturbance param  : %8.3f  %s\n', r.damping.n_disturb, ...
            tf_str(r.damping.triggered,'TRIGGERS','sub-threshold'));
    fprintf('  Resonator f0       : %8.1f Hz, Q = %.1f\n', ...
            r.resonator.f0, r.resonator.q);
    fprintf('  Droplet lifetime   : %8.3f ms\n', r.vaporization.lifetime*1e3);
    fprintf('  Heating time       : %8.3f ms (ratio %.2f)\n', ...
            r.vaporization.tau_heat*1e3, r.vaporization.heat_ratio);
    fprintf('  Response factor G  : %8.4f max at %.0f Hz  %s\n', ...
            r.vaporization.g_max, r.vaporization.f_g_max, ...
            tf_str(r.vaporization.driving_any,'DRIVING','negligible'));
    if ~r.vaporization.responsive
        fprintf('        (droplet heating time >> acoustic period: the\n');
        fprintf('         droplet cannot follow the oscillation, G -> 0)\n');
    end
    fprintf('  Supercritical      : %s\n', tf_str(r.vaporization.supercrit,'yes','no'));
end

if isfield(out,'ch12')
    r = out.ch12;
    section('CH.12  INJECTION-COUPLED INSTABILITY');
    fprintf('  Feed model         : %s\n', r.adm.model);
    fprintf('  Line sound speed   : %8.0f m/s ox, %.0f m/s fuel\n', ...
            r.ox.c_sound, r.fuel.c_sound);
    fprintf('  Lumped (Eq 9) valid: < %.0f Hz ox, < %.0f Hz fuel\n', ...
            r.adm.f_lumped_max_ox, r.adm.f_lumped_max_fuel);
    fprintf('  Line quarter-wave  : %8.0f Hz ox, %.0f Hz fuel\n', ...
            r.adm.f_quarter_ox, r.adm.f_quarter_fuel);
    fprintf('  Feed resonance ox  : %8.0f Hz (chamber %.0f Hz, sep %.0f%%)\n', ...
            r.margins.f_res_ox, r.margins.f_chamber, r.margins.sep_ox*100);
    fprintf('  Feed resonance fuel: %8.0f Hz (sep %.0f%%)\n', ...
            r.margins.f_res_fuel, r.margins.sep_fuel*100);
    fprintf('  Injector dP/Pc     : %8.3f ox, %.3f fuel\n', ...
            r.margins.dp_ratio_ox, r.margins.dp_ratio_fuel);
    fprintf('  |F| peak           : %8.3f at %.0f Hz  (amplification)\n', ...
            r.loop.mag_max, r.loop.f_peak);
    if isempty(r.loop.f_cross_reported)
        fprintf('  Phase crossovers   : none below %.0f Hz with usable gain\n', ...
                r.cfg.f_report_max);
    else
        fprintf('  Phase crossovers   : %s Hz\n', ...
                strjoin(arrayfun(@(x)sprintf('%.0f',x), ...
                r.loop.f_cross_reported, 'UniformOutput',false), ', '));
        fprintf('  |F| at crossover   : %s\n', ...
                strjoin(arrayfun(@(x)sprintf('%.2f',x), ...
                r.loop.mag_cross_reported, 'UniformOutput',false), ', '));
        if r.loop.n_cross_suppressed > 0
            fprintf('        (%d further crossings above %.0f Hz or below the\n', ...
                    r.loop.n_cross_suppressed, r.cfg.f_report_max);
            fprintf('         gain floor are omitted; they close the contour only)\n');
        end
    end
    if isfinite(r.loop.gain_margin_db)
        fprintf('  Gain margin        : %8.2f dB\n', r.loop.gain_margin_db);
    else
        fprintf('  Gain margin        :      inf (no phase crossover)\n');
    end
    if isfinite(r.loop.phase_margin)
        fprintf('  Phase margin       : %8.1f deg\n', r.loop.phase_margin);
    end
    fprintf('  Nyquist encircle.  : %8d\n', r.loop.encirclements);
    fprintf('  Feed system        : %s\n', ...
            tf_str(r.loop.unstable, ...
                   'UNSTABLE (encircles -1)', ...
                   'stable (Nyquist criterion)'));
    if r.loop.amplifies && ~r.loop.unstable
        fprintf('        note: |F| exceeds 1 at resonance, but the phase never\n');
        fprintf('        reaches +/-180 deg there, so the loop amplifies a\n');
        fprintf('        disturbance without sustaining one. |F|>1 alone is\n');
        fprintf('        not the instability criterion -- Eqs (20) AND (21).\n');
    end
end

if isfield(out,'ch13')
    r = out.ch13;
    section('CH.13  NONLINEAR LIMIT CYCLES');
    fprintf('  Response model     : %s\n', r.sim.model);
    fprintf('  Limit cycle exists : %s (alpha1*alpha2 < 0)\n', ...
            tf_str(r.limit_cycle.exists,'yes','no'));
    if r.limit_cycle.exists
        fprintf('  Analytic r1, r2    : %.4e , %.4e\n', ...
                r.limit_cycle.r1, r.limit_cycle.r2);
    end
    fprintf('  Integrated r1, r2  : %.4e , %.4e\n', ...
            r.sim.r1_final, r.sim.r2_final);
    fprintf('  Peak p'' amplitude  : %8.2f %% of Pc\n', r.sim.p_amp_pct);
    fprintf('  Converged          : %s\n', tf_str(r.sim.converged,'yes','no'));
    if r.sim.diverged
        fprintf('  DIVERGED: %s\n', r.sim.note);
    end
    if isnan(r.trigger.threshold)
        fprintf('  Trigger threshold  : none found in scan\n');
    else
        fprintf('  Trigger threshold  : %.3e\n', r.trigger.threshold);
    end
    fprintf('  Linearly unstable  : %s\n', tf_str(r.trigger.linearly_unstable,'yes','no'));
end

if isfield(out,'ch14')
    r = out.ch14;
    section('CH.14  ACOUSTIC CAVITY DESIGN');
    fprintf('  Target mode        : %s at %.0f Hz\n', r.chamber.id_target, r.chamber.f_target);
    fprintf('  Helmholtz f0       : %8.1f Hz\n', r.resonator.f_helm);
    fprintf('  Quarter-wave f0    : %8.1f Hz\n', r.resonator.f_quarter);
    fprintf('  Required QW length : %8.1f mm (set %.1f mm)\n', ...
            r.resonator.l_required*1e3, r.cfg.l_quarter*1e3);
    fprintf('  Required Helm vol  : %8.2f cm^3\n', r.resonator.v_required*1e6);
    fprintf('  Peak absorption    : %8.3f at %.0f Hz\n', ...
            r.absorption.alpha_max, r.absorption.f_best);
    fprintf('  Absorption @target : %8.3f\n', r.absorption.alpha_at_target);
    fprintf('  Bandwidth (-3dB)   : %8.0f Hz\n', r.absorption.bw_hz);
    fprintf('  Cold-flow setting  : %8.1f mm at %.0f Hz\n', ...
            r.tuning.l_cold_setting*1e3, r.tuning.f_cold_test);
    fprintf('  Tuned to target    : %s\n', pf(r.tuned_ok));
end

if isfield(out,'ch15')
    r = out.ch15;
    section('CH.15-17  ANALYTICAL MODELS');
    fprintf('  Combustion closure : %s\n', r.mitchell.comb_model);
    fprintf('  %-10s %10s %11s %11s %11s %11s  %s\n', ...
            'mode','f [Hz]','drive','damp','coupling','lambda','verdict');
    for i = 1:numel(r.mitchell.modes)
        m = r.mitchell.modes(i);
        dmp = m.damp_nozzle + m.damp_cavity + m.damp_baffle + m.damp_visc;
        fprintf('  %-10s %10.1f %11.2f %11.2f %11.2f %11.2f  %s\n', ...
                m.id, m.freq_hz, m.drive_comb, dmp, m.coupling, ...
                m.lambda, verdict(m.lambda));
    end
    fprintf('  Mach number        : %8.4f\n', r.turbulence.mach);
    fprintf('  Turbulent shift    : %8.4f %% (mode 1)\n', ...
            r.turbulence.modes(1).freq_shift*100);
    fprintf('  Landau growth      : %8.2f 1/s, saturates: %s\n', ...
            r.turbulence.modes(1).growth, ...
            tf_str(r.turbulence.landau.saturates,'yes','no'));
    if r.turbulence.landau.saturates
        fprintf('  Saturation amp     : %8.4e\n', r.turbulence.landau.a_sat);
    end
    fprintf('  Priem R_p peak     : %8.3f at %.0f Hz\n', ...
            r.priem.R_max, r.priem.f_at_max);
    fprintf('  Global response R_c: %8.3f  %s\n', r.priem.R_c_global, ...
            tf_str(r.priem.driving,'DRIVING','damping'));
end

if isfield(out,'ch18')
    r = out.ch18;
    section('CH.18-19  NUMERICAL SOURCE TERMS');
    fprintf('  Droplet diameter   : %8.1f um\n', r.spray.d_drop*1e6);
    fprintf('  Droplet Re / Cd    : %8.1f / %.4f\n', r.spray.re_m, r.spray.cd);
    fprintf('  Drag on gas        : %8.3e N/m^3\n', r.spray.f_gas);
    fprintf('  Vaporization src   : %8.3e kg/m^3/s\n', r.spray.W_gas_vap);
    fprintf('  Reaction rate      : %8.3e kmol/m^3/s\n', r.spray.omega_dot);
    fprintf('  Heat release       : %8.3e W/m^3\n', r.spray.heat_release);
    fprintf('  SGS viscosity      : %8.3e Pa.s\n', r.spray.mu_turb);
    fprintf('  Wall shear         : %8.1f Pa (beta_f %.3f)\n', ...
            r.wall.tau_w, r.wall.beta_f);
    fprintf('  Bomb overpressure  : %8.1f %%\n', r.bomb.overpressure_pct);
    fprintf('  Priem-Heidmann B   : %8.4f, mdot %.3e kg/s\n', ...
            r.cfd.b_number, r.cfd.mdot_vap);
    fprintf('  Response peak      : %8.3f at %.0f Hz\n', r.cfd.resp_peak, r.cfd.f_peak);
end

if isfield(out,'ch20')
    r = out.ch20;
    section('CH.20-21  SPECTRAL TESTING AND SCALING');
    fprintf('  Dominant line      : %8.0f Hz, amp %.4f, regularity %.2f\n', ...
            r.spectral.peak_f, r.spectral.peak_amp, r.spectral.lines(1).regularity);
    fprintf('  Flagged lines      :');
    any_flag = false;
    for i = 1:numel(r.spectral.lines)
        if r.spectral.lines(i).flagged
            fprintf(' %.0fHz', r.spectral.lines(i).freq_hz); any_flag = true;
        end
    end
    if ~any_flag; fprintf(' none'); end
    fprintf('\n');
    fprintf('  Student t / crit   : %8.3f / %.3f  -> %s\n', ...
            r.tests.t_stat, r.tests.t_crit, ...
            tf_str(r.tests.essential,'ESSENTIAL difference','not significant'));
    fprintf('  Fisher F / crit    : %8.2f / %.2f  -> %s\n', ...
            r.tests.f_stat, r.tests.f_crit, ...
            tf_str(r.tests.functional,'functional dependence','no dependence'));
    fprintf('  Limit amplitude    : %8.4f (margin x%.2f)\n', ...
            r.limit.A_limit, r.limit.margin);
    fprintf('  Scale ratio        : %8.3f\n', r.scaling.scale_ratio);
    fprintf('  Full 1T / 1L       : %8.0f / %.0f Hz\n', ...
            r.scaling.full.f_1T, r.scaling.full.f_1L);
    fprintf('  Sub  1T / 1L       : %8.0f / %.0f Hz\n', ...
            r.scaling.sub.f_1T, r.scaling.sub.f_1L);
    fprintf('  L* ratio           : %8.3f\n', r.scaling.l_star_ratio);
    g = fieldnames(r.scaling.matched);
    fprintf('  Similarity matched :');
    for i = 1:numel(g)
        if r.scaling.matched.(g{i}); fprintf(' %s', g{i}); end
    end
    fprintf('\n');
    fprintf('  Subscale QW length : %8.1f mm\n', r.scaling.cav_l_quarter_sub*1e3);
end

%% ---- Ch.1 vs Ch.15 cross-check ----------------------------------------
if isfield(out,'ch01') && isfield(out,'ch15')
    section('CH.1 vs CH.15 CROSS-CHECK');
    a = out.ch01;  m = out.ch15.mitchell;
    fprintf('  Both chapters now share yang_chamber_modes and\n');
    fprintf('  yang_growth_budget, so any difference is a modelling choice.\n\n');
    fprintf('  %-10s %11s %11s %11s %11s\n', ...
            'mode','Ch1 f [Hz]','Ch15 f [Hz]','Ch1 alpha','Ch15 lambda');
    n = min(numel(a.growth), numel(m.modes));
    for i = 1:n
        fprintf('  %-10s %11.1f %11.1f %11.2f %11.2f\n', ...
                a.growth(i).mode_id, a.growth(i).freq_hz, m.modes(i).freq_hz, ...
                a.growth(i).alpha_net, m.modes(i).lambda);
    end
    df = max(abs([a.growth(1:n).freq_hz] - [m.modes(1:n).freq_hz]) ...
             ./ [a.growth(1:n).freq_hz]);
    fprintf('\n  Max frequency disagreement : %.3f %%\n', df*100);
    fprintf('  Ch.1 closure  : %s (Eq 75, prescribed heat release)\n', ...
            a.growth(1).budget.comb_model);
    fprintf('  Ch.15 closure : %s (Eq 33, pressure-coupled n-tau)\n', ...
            m.comb_model);
    if ~strcmp(a.growth(1).budget.comb_model, m.comb_model)
        fprintf('  The remaining spread in alpha is the closure difference:\n');
        fprintf('    Eq (75)  drive ~ cos(w*tau)      -- sign alternates with lag\n');
        fprintf('    Eq (79a) drive ~ n(1-cos(w*tau)) -- never negative\n');
        fprintf('  Run with ''comb_model'' set the same in both to compare\n');
        fprintf('  like for like; then only the Green''s coupling differs.\n');
    end
end

%% ---- consolidated verdict ---------------------------------------------
section('CONSOLIDATED STABILITY ASSESSMENT');
flags = {};
if isfield(out,'ch01') && ~out.ch01.chamber_stable
    flags{end+1} = sprintf('Ch.1 linear acoustics: mode %s growing at %.1f 1/s', ...
                           out.ch01.worst_mode.mode_id, out.ch01.worst_mode.alpha_net);
end
if isfield(out,'ch12') && out.ch12.loop.unstable
    flags{end+1} = sprintf(['Ch.12 feed coupling: |F| = %.2f at the %.0f Hz ' ...
                            'phase crossover (%d encirclement(s))'], ...
                           1/out.ch12.loop.gain_margin, ...
                           out.ch12.loop.f_gain_margin, ...
                           out.ch12.loop.encirclements);
end
if isfield(out,'ch13') && out.ch13.sim.p_amp_pct > 5
    flags{end+1} = sprintf('Ch.13 limit cycle: %.1f%% of Pc', out.ch13.sim.p_amp_pct);
end
if isfield(out,'ch15') && ~out.ch15.stable
    flags{end+1} = 'Ch.15/16 analytical model: positive growth rate';
end
if isfield(out,'ch10') && out.ch10.vaporization.driving_any
    flags{end+1} = sprintf('Ch.11 vaporization response G = %.3f (driving)', ...
                           out.ch10.vaporization.g_max);
end

if isempty(flags)
    fprintf('  STABLE -- no module reported a growing mode.\n');
else
    fprintf('  UNSTABLE -- %d indicator(s):\n', numel(flags));
    for i = 1:numel(flags); fprintf('    %d. %s\n', i, flags{i}); end
    fprintf('\n  Mitigation paths (Ch.1 Sec. V, Ch.14):\n');
    fprintf('    - shorten the combustion time lag (finer atomization, higher dP)\n');
    fprintf('    - retune acoustic cavities onto the driven mode (Ch.14)\n');
    fprintf('    - add baffles to raise blade dissipation (Ch.15 Eqs 39-43)\n');
    fprintf('    - raise injector dP/Pc to decouple the feed system (Ch.12)\n');
end
fprintf('\n  Modules run: %s\n', strjoin(mods, ', '));
fprintf('================================================================\n\n');
end

% =========================================================================
function make_plots(out, ~)
if isfield(out,'ch01')
    figure('Name','Ch.1 Modal stability');
    subplot(2,1,1);
    bar([out.ch01.growth.alpha_net]); grid on;
    set(gca,'XTickLabel',{out.ch01.growth.mode_id});
    ylabel('\alpha_n [1/s]'); title('Net growth constant by mode');
    yline(0,'r--','LineWidth',1.5);
    subplot(2,1,2);
    semilogx(out.ch01.control.freq_hz, out.ch01.control.gain_db); grid on;
    xlabel('Frequency [Hz]'); ylabel('|P/F_e| [dB]');
    title('Closed-loop response');
end
if isfield(out,'ch13')
    figure('Name','Ch.13 Limit cycle');
    subplot(2,1,1);
    plot(out.ch13.sim.time*1e3, out.ch13.sim.r1, ...
         out.ch13.sim.time*1e3, out.ch13.sim.r2); grid on;
    xlabel('t [ms]'); ylabel('amplitude'); legend('r_1','r_2');
    title(sprintf('Amplitude evolution (%s)', out.ch13.sim.model));
    subplot(2,1,2);
    plot(out.ch13.sim.time*1e3, out.ch13.sim.p_head/1e6); grid on;
    xlabel('t [ms]'); ylabel("p' at head end [MPa]");
end
if isfield(out,'ch14')
    figure('Name','Ch.14 Cavity absorption');
    plot(out.ch14.absorption.freq_hz, out.ch14.absorption.alpha); grid on; hold on;
    xline(out.ch14.chamber.f_target,'r--','target mode');
    xlabel('Frequency [Hz]'); ylabel('\alpha'); title('Absorption coefficient');
end
if isfield(out,'ch12')
    figure('Name','Ch.12 Feed-system loop');
    semilogy(out.ch12.loop.freq_hz, out.ch12.loop.mag); grid on; hold on;
    yline(1,'r--','|F| = 1');
    xlabel('Frequency [Hz]'); ylabel('|F|'); title('Characteristic loop gain');
end
if isfield(out,'ch20')
    figure('Name','Ch.20 Spectrum');
    semilogy(out.ch20.spectral.freq_hz, out.ch20.spectral.mean_all); grid on;
    xlabel('Frequency [Hz]'); ylabel('mean line amplitude');
    title('Block-averaged spectrum'); xlim([0 6000]);
end
end

% =========================================================================
function c = cfg_ch01(e)
c = struct('len_chamber',e.len,'rad_chamber',e.rad,'p_mean',e.pc, ...
           't_mean',e.tc,'gamma_gas',e.gamma,'r_gas',e.rgas, ...
           'tau_lag',e.tau,'n_interact',e.n_int);
c = add_shared(c, e);
end

function c = add_shared(c, e)
% Damping hardware and the combustion closure must reach Ch.1 and Ch.15
% identically, or the two chapters silently describe different engines.
f = {'n_blades','area_blade','eps_u_blade','area_cavity','psi2_at_cavity', ...
     'q_factor','q_amp','mach_exit','comb_model'};
for i = 1:numel(f)
    if isfield(e, f{i}) && ~isempty(e.(f{i})); c.(f{i}) = e.(f{i}); end
end
end
function c = cfg_ch02(e)
c = struct('p_chamber',e.pc,'t_chamber',e.tc,'gamma_gas',e.gamma, ...
           'r_gas',e.rgas,'r_chamber',e.rad);
end
function c = cfg_ch12(e)
c = struct('p_chamber',e.pc,'tau_burn',e.tau);
end
function c = cfg_ch13(e)
c = struct('p_mean',e.pc,'gamma_gas',e.gamma,'len_chamber',e.len);
end
function c = cfg_ch14(e)
c = struct('p_chamber',e.pc,'t_chamber',e.tc,'gamma_gas',e.gamma, ...
           'r_gas',e.rgas,'r_chamber',e.rad,'len_chamber',e.len);
end
function c = cfg_ch15(e)
c = struct('p_chamber',e.pc,'t_chamber',e.tc,'gamma_gas',e.gamma, ...
           'r_gas',e.rgas,'r_chamber',e.rad,'len_chamber',e.len, ...
           'tau_lag',e.tau,'n_interact',e.n_int);
c = add_shared(c, e);
end

% =========================================================================
function p = parse_args(args)
p.modules = {};
p.quiet   = false;
p.plots   = false;
p.engine  = struct('len',0.50,'rad',0.15,'pc',20.7e6,'tc',3600, ...
                   'gamma',1.22,'rgas',8314/7.5,'tau',1.0e-3,'n_int',0.6);
for i = 1:2:numel(args)
    k = lower(args{i});  v = args{i+1};
    switch k
        case 'modules'; p.modules = v;
        case 'quiet';   p.quiet   = v;
        case 'plots';   p.plots   = v;
        case {'engine','damping'}
                        % 'damping' is an alias that reaches both Ch.1 and
                        % Ch.15 through add_shared, so damping hardware and
                        % the combustion closure can never be set for only
                        % one of them.
                        f = fieldnames(v);
                        for j = 1:numel(f); p.engine.(f{j}) = v.(f{j}); end
        otherwise; warning('yang:arg','unknown option "%s"', k);
    end
end
end

function section(t)
fprintf('----------------------------------------------------------------\n');
fprintf('%s\n', t);
fprintf('----------------------------------------------------------------\n');
end
function s = verdict(a)
if a > 0; s = 'UNSTABLE'; elseif a > -1; s = 'marginal'; else; s = 'stable'; end
end
function s = pf(b);  if b; s = 'PASS'; else; s = 'FAIL'; end;  end
function s = rng_tag(v); if v.valid; s = ''; else; s = '[out of range]'; end; end
function s = tf_str(b, y, n);  if b; s = y; else; s = n; end;  end
