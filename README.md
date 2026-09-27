# YANG_INSTAB — Liquid Rocket Engine Combustion Instability

MATLAB implementation of Yang, V. & Anderson, W.E. (eds.), *Liquid Rocket Engine
Combustion Instability*, AIAA Progress in Astronautics and Aeronautics Vol. 169
(1995). 21 chapters, 553 equations, organised as 11 runnable modules.

## Quick start

```matlab
yang_instability_main();                              % run everything
yang_instability_main('modules', {'ch01','ch13'});    % selected chapters
yang_instability_main('plots', true);                 % with figures
out = yang_instability_main('quiet', true);           % results only
test_yang_instability();                              % verification suite
```

Each module also runs standalone and takes a config struct:

```matlab
r = yang_ch01_acoustics(struct('tau_lag', 0.5e-3, 'q_amp', 8e9));
r = yang_ch13_nonlinear(struct('model', 'p_abs_u'));
```

Any field you omit falls back to a documented default.

## Modules

| File | Chapters | Contents |
|---|---|---|
| `yang_chamber_modes.m` | shared | Helmholtz eigenproblem, mode norms `E_n²`, heat-release overlap integrals — used by Ch.1 and Ch.15 |
| `yang_growth_budget.m` | shared | The one definition of combustion driving and all four damping terms |
| `yang_ch01_acoustics.m` | 1 | Oscillator model, two-phase conservation, modal expansion, growth constants, Rayleigh criterion, n-τ response, nozzle admittance, delayed-feedback control |
| `yang_ch02_engine_corr.m` | 2–5 | Injector velocity/momentum ratios, Reardon time lag, c*/Isp, RD-0110 amplitude-frequency characteristic, Henry's law, Eötvös breakup |
| `yang_ch06_atomization.m` | 6–7 | Nukiyama-Tanasawa, Mayer, Dickerson-Schuman, viscous sheet breakup, Reitz, Rosin-Rammler, Abramovitch profiles, Kim-Marshall, simulant corrections, Vulcain D32 |
| `yang_ch08_breakup.m` | 8–9 | Impinging-jet sheet, Hasson-Peck thickness, Squire waves, viscous dispersion, ligament→drop, secondary breakup regimes, Faeth turbulent primary breakup |
| `yang_ch10_damping.m` | 10–11 | Damping decrement, correlation envelopes, impulse response, Helmholtz resonator dynamics, generalized d² law, vaporization response factor G |
| `yang_ch12_injection.m` | 12 | Feed-system segment network, admittances A_o/A_f/A_I/A_B, chamber response R_c, Nyquist stability on `1 − R_c(A_I+A_B) = 0` |
| `yang_ch13_nonlinear.m` | 13 | Averaged amplitude/phase equations, five combustion-response laws, limit cycles, triggering thresholds, modal energies |
| `yang_ch14_cavity.m` | 14 | Chamber resonances, Helmholtz/quarter-wave tuning, orifice impedance, absorption coefficient, two-microphone transfer function, cold-to-hot retuning |
| `yang_ch15_analytical.m` | 15–17 | Mitchell Green's-function eigenvalues, baffle dissipation, Kim turbulence-corrected dispersion, Landau-Stuart saturation, Priem combustion response profiles |
| `yang_ch18_numerical.m` | 18–19 | Spray source terms, Arrhenius chemistry, drag closure, Deardorff SGS, lateral-flow sources, wall friction, bomb disturbance, Euler flux vectors, Priem-Heidmann vaporization, linearised response coefficients |
| `yang_ch20_testing.m` | 20–21 | Spectral line statistics, Student/Fisher acceptance tests, limit-amplitude extrapolation, similarity groups, full-to-subscale scaling |

`yang_instability.m` is the original equation catalogue (symbolic reference,
not executable as an algorithm). The modules above supersede it.

## Verification

`test_yang_instability.m` — 105 checks, all passing. It verifies module
execution and finiteness, then checks equations against closed-form limits:

- `1L = c/(2L)` and `1T = 1.8412c/(2πR)` chamber modes
- n-τ response limits at `ωτ = 0` and `ωτ = π`
- axisymmetric heat release gives zero overlap with tangential modes
- `α_v = 1` recovers the classical d² law exactly
- log decrement `= 2πζ`; Q ≈ 50
- integrated limit cycle matches the analytical `r₁₀`, `r₂₀`
- implicit SMD equation satisfies its own residual
- `l_required` retunes the quarter-wave onto the target mode
- mass conservation and Newton's third law in the spray source terms
- 1T frequency ratio equals the inverse length-scale ratio
- Ch.1 and Ch.15 report identical eigenfrequencies
- under a matched closure, `λ_Ch15 − α_Ch1` equals the coupling term exactly
- with coupling off, the two chapters coincide
- the Crocco drive is the *real* part: it vanishes at zero lag and peaks at
  `ωτ = π` (the guard against the sign bug described below)
- raising injector `dP` monotonically shrinks the feed-line admittance,
  and in the extreme limit `F` reduces exactly to `R_c·A_B` (Eq 19)
- the Nyquist contour closes, its encirclement count agrees with the
  gain-margin test, and reported phase crossovers sit at genuine ±180°
  points, not phase-wrap artifacts
- the transmission-line and lumped feed models agree below the lumped
  ceiling and diverge increasingly above it

## Notes on fidelity

Three things are worth knowing before trusting a number:

**Dimensional correlations.** Nukiyama-Tanasawa and the Rosin-Rammler
parameter fits are stated in cgs/microns in the source. They are evaluated in
their native units with explicit conversion, not by substituting SI values.

**Range flags.** At LOX/H₂ shear-coaxial conditions (V_r ≈ 275 m/s, We_ae ≈
9×10⁴) several atomization correlations are far outside the range they were
calibrated on. `res.validity` flags each one and the driver prints
`[out of range]`; `smd.recommended` uses only the correlations still in range.
Do not read a flagged value as a prediction.

**Model truncation.** The Ch.13 second-order averaged equations have no
saturating term, so for some coefficient sets the amplitude genuinely diverges
in finite time rather than reaching a limit cycle. That is a property of the
truncation, not a solver failure. The integration stops at a physical ceiling
and sets `sim.diverged` with an explanatory note — use `model:'third'` for a
bounded cycle.

Defaults describe a generic RL10-class LOX/LH2 engine: Pc = 20.7 MPa,
Tc = 3600 K, 100 kg/s at O/F = 3, 0.30 m × 0.50 m chamber. The throat area is
sized from `A_t = ṁc*/Pc` so c* efficiency and Isp come out self-consistent
(412 s). Change these via the `engine` option or per-module configs.

## Shared core: why Ch.1 and Ch.15 agree

Ch.1 (Culick & Yang) and Ch.15 (Mitchell) analyse the same chamber by
different routes. They are held consistent by two shared files:

- **`yang_chamber_modes.m`** — the Helmholtz eigenproblem (Eqs 45, 46), the
  norms `E_n²` (Eq 49), and the overlap of each mode with the heat-release
  distribution. Ch.1 and Ch.15 use one mode set at identical frequencies.
- **`yang_growth_budget.m`** — the single definition of every driving and
  damping term: combustion (Eq 75 or Eqs 79a/83), nozzle admittance
  (Eqs 70, 72, 34), cavity admittance (Eqs 36–38), baffle dissipation
  (Eqs 39–43), and residual Q-factor losses.

With the same combustion closure, `λ_Ch15 − α_Ch1` equals Mitchell's
Green's-function coupling term **to machine precision (~4×10⁻¹⁴)** — that
coupling is the entire difference between the two formulations, which is
exactly what it should be. Set `green_coupling = 0` and they coincide.

The two default to different closures because their source chapters do:

| | closure | driving term | behaviour |
|---|---|---|---|
| Ch.1 | `prescribed` (Eq 75) | `cos(ωτ)` | sign alternates with lag (Eq 76) |
| Ch.15 | `crocco` (Eq 33) | `n(1−cos ωτ)` | never negative |

Force both onto one closure to compare like for like:

```matlab
yang_instability_main('damping', struct('comb_model', 'crocco'));
```

Damping hardware must also be set for both at once — configuring cavities or
baffles in only one chapter is what made them disagree originally:

```matlab
yang_instability_main('damping', struct('n_blades', 6, 'area_cavity', 2e-3));
```

## Ch.12: what "unstable" now means

Ch.12 originally declared instability whenever `|F| > 1` anywhere in the
sweep. That is only half of Eqs (20)-(21): the Nyquist criterion needs
`|F| = 1` **and** `arg F = ±180°` at the *same* frequency — a loop can
amplify a disturbance (`|F| > 1`) without ever sustaining one, if the phase
never lines up. The module now:

- tracks phase crossovers on the **unwrapped** phase (the wrap point is
  itself a crossing, not something to filter out),
- reports the gain margin **at the crossover**, not the raw peak `|F|`,
- counts Nyquist encirclements of −1 on a **closed** contour (the sweep
  must reach DC and roll off, checked via `loop.contour_closed`), with the
  clockwise-positive sign convention verified against a monotonic case,
- models each feed duct as a **transmission line**, not a lumped ladder.
  The lumped form of Eq (9) is only valid while the duct is short compared
  with its acoustic wavelength (`l < λ/10`); for the shipped LOX/H₂ lines
  that ceiling is ~450–600 Hz, while the coupling of interest sits at
  ~2200 Hz — nearly 5× past it. Using the lumped form there invented a
  false "feed resonance" at ~1 Hz. `res.adm.f_lumped_max_*` reports the
  ceiling; set `feed_model = 'lumped'` only below it.

With these fixes the default engine is still flagged unstable — a genuine
result, not a leftover artifact: the transmission-line model finds a real
phase crossover at 2502 Hz with `|F| = 3.18` (gain margin −10 dB) and 4
net Nyquist encirclements, driven by the fuel line's organ-pipe resonance
at 1996 Hz sitting within 10% of the chamber's 2206 Hz mode.

Note that raising injector `dP/Pc` — the standard mitigation — does not
monotonically lower the loop gain `|F|`, because `A_I` and `A_B` combine as
complex vectors: shrinking `|A_I|`'s magnitude can shift its phase enough
to add more constructively with `A_B`. What *is* guaranteed is that raising
`dP` shrinks `|A_I|` itself and, in the limit, decouples the feed path
entirely (`F → R_c·A_B`). Whether that helps depends on where the new
resonance lands relative to the chamber mode — check `res.margins.sep_ox`
/ `sep_fuel` after changing it, don't assume monotone improvement.

## Interpreting the consolidated verdict

The driver aggregates indicators across modules and prints a Ch.1/Ch.15
cross-check table. With the shipped defaults both chapters report every mode
stable at identical frequencies, and the only flagged indicator is Ch.12 as
described above. Treat the union of indicators as the screening result.
