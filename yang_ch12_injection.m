function res = yang_ch12_injection(cfg)
% YANG_CH12_INJECTION  Chapter 12 - high-frequency injection-coupled
% combustion instability (Hutt & Rucker, 1995), Eqs (1)-(22).
%
% Builds the lumped feed-system network: each manifold/orifice segment gets a
% capacitance C_i (Eq 4) and an inertance L_i with resistance R_i and the
% coupling coefficients xi, phi, D, U, G, H (Eq 8).  Assembling Eq (9) over
% all segments with the inlet/exit boundary conditions (Eqs 11,12) gives the
% feed-line admittance a_i(s) (Eq 10), from which the oxidizer and fuel
% admittances A_o, A_f (Eq 13), the injector admittance A_I (Eq 16), the
% burning admittance A_B (Eq 15) and the chamber response R_c (Eq 18) follow.
% The instability condition is the Nyquist criterion on Eq (19):
%   1 - R_c(s)[A_I(s) + A_B(s)] = 0,  i.e. |F| = 1 and arg F = +/- pi.
%
%   res = yang_ch12_injection(cfg)

if nargin < 1 || isempty(cfg); cfg = struct(); end
cfg = merge_defaults(cfg, default_cfg());

f  = cfg.f_sweep(:).';
s  = 1i*2*pi*f;
pc = cfg.p_chamber;

%% ===== per-segment lumped coefficients (Eqs 4, 8) ======================
% Segment data: length, flow area, inlet/exit areas, volume, density
ox   = build_segments(cfg.ox,   cfg.mdot_ox,   pc);
fu   = build_segments(cfg.fuel, cfg.mdot_fuel, pc);

%% ===== solve the segment chain for the feed admittance (Eqs 9,11,12) ===
% Eq (10): a_i(s) = pc mdot'_i(s) / (mdot_bar p'_c(s)).  Marching the
% tridiagonal system of Eq (9) from the (stiff) manifold inlet to the
% injector face gives the terminal admittance.
adm.ox   = chain_admittance(ox, s, cfg.mdot_ox,   pc, cfg.feed_model);
adm.fuel = chain_admittance(fu, s, cfg.mdot_fuel, pc, cfg.feed_model);
adm.model = cfg.feed_model;
% Where the feed line actually resonates.  With the distributed model this
% is the organ-pipe frequency of the duct, not the lumped Helmholtz value.
adm.f_res_ox   = feed_resonance(ox,   s, adm.ox);
adm.f_res_fuel = feed_resonance(fu,   s, adm.fuel);
adm.f_lumped_max_ox   = ox.f_lumped_max;
adm.f_lumped_max_fuel = fu.f_lumped_max;
adm.f_quarter_ox      = ox.f_quarter_wave;
adm.f_quarter_fuel    = fu.f_quarter_wave;

%% ===== injector and burning admittances (Eqs 13-17) ====================
% Eq (16): A_I = (r A_o e^{-s tau_o} + A_f e^{-s tau_f})/(r + 1),
%          r = mdot_ox/mdot_fuel
r_mix = cfg.mdot_ox/cfg.mdot_fuel;
A_o   = adm.ox;
A_f   = adm.fuel;
A_I   = (r_mix*A_o.*exp(-s*cfg.tau_ox) + A_f.*exp(-s*cfg.tau_fuel))/(r_mix+1);
% Eq (15): A_B = n (1 - e^{-s tau_b}), the pressure-sensitive burning term
A_B   = cfg.n_burn*(1 - exp(-s*cfg.tau_burn));

%% ===== chamber response (Eq 18) =======================================
% The chamber behaves as a damped acoustic resonator between the burning
% rate perturbation and the pressure it produces:
%   R_c(s) = p'_c mdot_bar/(mdot'_b pc)
om_c = 2*pi*cfg.f_chamber;
R_c  = cfg.gain_chamber*om_c^2 ./ (s.^2 + 2*cfg.zeta_chamber*om_c*s + om_c^2);

%% ===== characteristic equation and Nyquist test (Eqs 19-22) ===========
F      = R_c.*(A_I + A_B);
loop.freq_hz  = f;
loop.F        = F;
loop.mag      = abs(F);
loop.phase_deg= unwrap(angle(F))*180/pi;
loop.A_I      = A_I;
loop.A_B      = A_B;
loop.R_c      = R_c;
% Eq (22): the two curves whose crossing marks neutral stability
loop.inv_Rc_mag = 1./abs(R_c);
loop.resp_mag   = abs(A_I + A_B);

% Eqs (19)-(21): the characteristic equation is 1 + F(s) = 0, so the system
% is unstable when the F(jw) locus encircles the -1 point.  BOTH conditions
% of Eqs (20) and (21) have to hold together:
%
%     |F(jw)| = 1     AND     arg F(jw) = +/- pi
%
% A large |F| on its own is NOT instability -- it only means the loop
% amplifies at that frequency.  What matters is |F| evaluated AT the phase
% crossover, which is exactly the classical gain margin.  Testing |F| > 1
% anywhere declares almost any resonant feed system unstable.
[loop.mag_max, im] = max(loop.mag);
loop.f_peak = f(im);

% --- phase crossovers: arg F = +/- 180 deg -------------------------------
% Work on the UNWRAPPED phase and look for crossings of every odd multiple
% of 180 deg.  The time delays make the phase march monotonically downward,
% so the locus crosses -180, -540, -900, ... in turn and each crossing is a
% candidate instability frequency.  (Detecting these on the wrapped phase
% is a trap: the wrap discontinuity IS the crossing, so any filter that
% rejects large jumps rejects exactly the points being looked for.)
ph = loop.phase_deg;
kmin = floor((min(ph) + 180)/360);
kmax = ceil( (max(ph) + 180)/360);
loop.f_phase_cross = [];
loop.mag_at_cross  = [];
for kk = kmin:kmax
    target = kk*360 - 180;
    idx = find(diff(sign(ph - target)) ~= 0);
    for k = 1:numel(idx)
        j  = idx(k);
        d1 = ph(j) - target;  d2 = ph(j+1) - target;
        if d1 == d2; wgt = 0; else; wgt = d1/(d1 - d2); end
        wgt = min(max(wgt, 0), 1);
        loop.f_phase_cross(end+1) = f(j) + wgt*(f(j+1) - f(j));  %#ok<AGROW>
        loop.mag_at_cross(end+1)  = loop.mag(j) ...
                                    + wgt*(loop.mag(j+1) - loop.mag(j));
    end
end
[loop.f_phase_cross, iord] = sort(loop.f_phase_cross);
loop.mag_at_cross = loop.mag_at_cross(iord);

% --- gain margin, defined at the phase crossover -------------------------
if isempty(loop.mag_at_cross)
    loop.gain_margin     = Inf;
    loop.gain_margin_db  = Inf;
    loop.f_gain_margin   = NaN;
    loop.nyquist_unstable= false;
else
    [mx, ix] = max(loop.mag_at_cross);
    loop.gain_margin     = 1/mx;
    loop.gain_margin_db  = -20*log10(max(mx, eps));
    loop.f_gain_margin   = loop.f_phase_cross(ix);
    loop.nyquist_unstable= mx > 1;      % Eqs (20) AND (21) both satisfied
end

% --- gain crossovers (|F| = 1) and the phase margin ----------------------
xi = find(diff(sign(loop.mag - 1)) ~= 0);
loop.f_neutral    = [];
loop.phase_at_gc  = [];
for k = 1:numel(xi)
    j = xi(k);
    w = (1 - loop.mag(j))/(loop.mag(j+1) - loop.mag(j));
    loop.f_neutral(end+1)   = f(j) + w*(f(j+1) - f(j));          %#ok<AGROW>
    loop.phase_at_gc(end+1) = loop.phase_deg(j) ...
                              + w*(loop.phase_deg(j+1) - loop.phase_deg(j));
end
if isempty(loop.phase_at_gc)
    loop.phase_margin = Inf;
else
    pm = 180 - abs(mod(loop.phase_at_gc + 180, 360) - 180);
    loop.phase_margin = min(pm);
end

% --- Nyquist encirclement count -----------------------------------------
% The delays make 1 + F(s) transcendental, so count encirclements of -1
% rather than trusting a single margin.  The count is only meaningful on a
% CLOSED contour, which needs both ends pinned:
%   at s -> 0    A_B = n(1 - e^0) = 0 and R_c -> gain, so F(0) is real;
%   at s -> inf  R_c rolls off as 1/s^2, so F -> 0.
% The sweep therefore has to start near DC and run until |F| << 1, otherwise
% the open ends contribute a spurious fraction of a turn.  Verify both.
loop.contour_closed = (f(1) <= cfg.f_dc_tol) && (loop.mag(end) < 0.05);
if loop.contour_closed
    locus        = [conj(fliplr(F)), F];       % omega from -inf to +inf
    ang_about_m1 = unwrap(angle(locus + 1));
    % The Nyquist contour is traversed CLOCKWISE in the s-plane, so a
    % clockwise encirclement of -1 shows up as a DECREASING argument.  N is
    % counted clockwise-positive, hence the sign flip; getting this backwards
    % turns unstable systems into stable ones and vice versa.
    loop.encirclements = -round((ang_about_m1(end) - ang_about_m1(1))/(2*pi));
else
    loop.encirclements = NaN;   % contour not closed: count is meaningless
end

% The open-loop F has no right-half-plane poles (passive feed line, damped
% chamber), so the Nyquist criterion reduces to N = 0 for stability.
if isnan(loop.encirclements)
    loop.unstable = loop.nyquist_unstable;      % fall back to the margin test
else
    loop.unstable = loop.nyquist_unstable || loop.encirclements > 0;
end
loop.amplifies = loop.mag_max > 1;   % resonant amplification, not instability

% --- restrict the reported crossovers to the physically meaningful band ---
% The sweep runs to 80 kHz only so the Nyquist contour closes.  Crossovers
% up there carry vanishing gain and sit far above any frequency the injector
% or chamber model represents, so listing them is noise.
keep = loop.f_phase_cross <= cfg.f_report_max & loop.mag_at_cross > cfg.mag_floor;
loop.f_cross_reported   = loop.f_phase_cross(keep);
loop.mag_cross_reported = loop.mag_at_cross(keep);
loop.n_cross_suppressed = sum(~keep);

%% ===== wall friction closure (Eq 5) ===================================
% tau_w = (f/4)(rho u^2/2), used to set each segment's R_i.
fric.f_darcy = ox.f_friction;
fric.tau_wall= ox.f_friction/4*cfg.ox.rho*cfg.ox.u_mean^2/2;

%% ===== design margins ==================================================
% The stiffness of the injector -- its pressure drop relative to the chamber
% pressure -- is what decouples the feed system from the chamber.  This is
% the primary design lever for the mechanism of Ch.12.
marg.dp_ratio_ox   = cfg.ox.dp_injector/pc;
marg.dp_ratio_fuel = cfg.fuel.dp_injector/pc;
marg.f_res_ox      = adm.f_res_ox;
marg.f_res_fuel    = adm.f_res_fuel;
marg.f_chamber     = cfg.f_chamber;
% Coincidence of a feed resonance with the chamber mode is the classic
% injection-coupled trigger.
marg.sep_ox   = abs(adm.f_res_ox   - cfg.f_chamber)/cfg.f_chamber;
marg.sep_fuel = abs(adm.f_res_fuel - cfg.f_chamber)/cfg.f_chamber;
marg.coincident = marg.sep_ox < 0.15 || marg.sep_fuel < 0.15;

res.cfg  = cfg;
res.ox   = ox;   res.fuel = fu;
res.adm  = adm;  res.loop = loop;  res.friction = fric;  res.margins = marg;
res.unstable = loop.unstable;
end

% =========================================================================
function seg = build_segments(sd, mdot, pc)
% Coefficients of Eqs (4) and (8) for each lumped feed-system segment, plus
% the physical ladder elements the recursion actually integrates.
%
% The book's C_i, L_i, R_i etc. are nondimensional and are kept for fidelity
% and reporting; the numerics use the dimensional equivalents:
%
%   z_series  inertance   rho l / A        [kg/m^4]      -> Z = z_series * s
%   r_series  resistance  2 dP / Q         [Pa s/m^3]
%   c_shunt   compliance  V / K_bulk       [m^3/Pa]      -> Y = c_shunt * s
%
n = numel(sd.length);
seg.n_duct = n;
seg.n      = n;
seg.rho    = sd.rho;
seg.length = sd.length;
seg.f_friction = sd.f_friction;
q_vol   = mdot/sd.rho;                       % mean volumetric flow [m^3/s]
% Manifold source impedance: a stiff plenum, small but non-zero.
seg.z_manifold = sd.z_manifold;
% Acoustic speed in the line: c = sqrt(K/rho), and dpdrho_inv = 1/K.
seg.c_sound = sqrt(1/(sd.rho*sd.dpdrho_inv));

for i = 1:n
    A_i = sd.area(i);
    % --- distributed (transmission-line) properties ---
    seg.z_char(i)   = sd.rho*seg.c_sound/A_i;                  % rho c / A
    dp_i            = sd.f_friction*(sd.length(i)/sd.diam(i)) ...
                      *sd.rho*(q_vol/A_i)^2/2;                 % Eqs (5),(6)
    % Linearised resistance of a square-law element: dP ~ Q^2 -> R = 2 dP/Q
    r_i             = 2*dp_i/max(q_vol, eps);
    seg.r_series(i) = r_i;
    % Distributed attenuation equivalent to that resistance
    seg.alpha_loss(i) = r_i/(2*seg.z_char(i)*sd.length(i));
    % --- lumped equivalents, kept for Eq (9) fidelity and reporting ---
    seg.z_series(i) = sd.rho*sd.length(i)/A_i;                 % inertance
    seg.c_shunt(i)  = sd.volume(i)*sd.dpdrho_inv;              % V/K_bulk
end
% The injector orifice carries the design pressure drop.  It is short
% compared with every wavelength of interest, so it stays lumped.
seg.z_injector  = sd.rho*sd.length_injector/sd.area_injector;
seg.r_injector  = 2*sd.dp_injector/max(q_vol, eps);
seg.dp_injector = sd.dp_injector;
% Ceiling of the lumped approximation: the longest duct must stay short
% compared with a wavelength.  Above this the ladder form of Eq (9) is not
% trustworthy and the transmission-line model must be used.
seg.f_lumped_max = seg.c_sound/(10*max(sd.length));
% First distributed (organ-pipe) resonance of the line
seg.f_quarter_wave = seg.c_sound/(4*sum(sd.length));

for i = 1:n
    l  = sd.length(i);   S  = sd.area(i);
    Si = sd.area_in(i);  Se = sd.area_out(i);
    V  = sd.volume(i);   rho= sd.rho;
    rho_next = sd.rho;
    % Eq (4): C_{i+1} = pc V_{i+1}/mdot * (drho/dp)
    seg.C(i)   = pc*V/mdot*sd.dpdrho_inv;
    % Eq (8a): L_i = l_i mdot/(S_i pc)
    seg.L(i)   = l*mdot/(S*pc);
    % Eq (8c): xi_i = 2 mdot^2/(pc rho_{i+1} S_E S_i)
    seg.xi(i)  = 2*mdot^2/(pc*rho_next*Se*S);
    % Eq (8d): phi_i = 2 mdot^2/(pc rho_i S_I S_i)
    seg.phi(i) = 2*mdot^2/(pc*rho*Si*S);
    % Mean pressure drop across the segment, from Eq (6)
    dp         = sd.f_friction*(l/sd.diam(i))*(mdot/S)^2/(2*rho);
    seg.dp(i)  = dp;
    % Eq (8b): R_i = 2 dp/pc + phi_i - xi_i
    seg.R(i)   = 2*dp/pc + seg.phi(i) - seg.xi(i);
    % Eqs (8e)-(8h): compressibility couplings
    seg.D(i)   = seg.R(i)*pc/(2*(rho+rho_next))*sd.dpdrho_inv;
    seg.U(i)   = seg.D(i);
    seg.G(i)   = seg.phi(i)*pc/(2*rho)*sd.dpdrho_inv;
    seg.H(i)   = seg.xi(i)*pc/(2*rho_next)*sd.dpdrho_inv;
end
end

% =========================================================================
function f0 = feed_resonance(seg, s, a_line)
% Frequency at which the feed line responds most strongly, taken from the
% computed admittance rather than from a lumped formula -- with a
% distributed line the response is a series of organ-pipe resonances, and
% the lumped Helmholtz estimate 1/(2 pi sqrt(LC)) is only the first of them
% and only when the line is acoustically short.
% The admittance magnitude is largest at DC -- a resistive line is nearly a
% short there -- so a plain max() returns the first sample, not a resonance.
% Look for an interior local maximum instead.
f    = imag(s)/(2*pi);
band = find(f > 0.5*seg.f_quarter_wave & f < 6*seg.f_quarter_wave);
if numel(band) < 3
    f0 = NaN;  return;
end
mag  = abs(a_line(band));
fb   = f(band);
isloc = [false, mag(2:end-1) > mag(1:end-2) & mag(2:end-1) > mag(3:end), false];
if ~any(isloc)
    [~, ix] = max(mag);           % no interior peak: fall back to the max
else
    cand    = find(isloc);
    [~, jj] = max(mag(cand));
    ix      = cand(jj);
end
f0 = fb(ix);
end

% =========================================================================
function a_term = chain_admittance(seg, s, mdot, pc, model)
% Terminal admittance of the feed line, Eq (10):
%     a(s) = pc mdot'(s) / (mdot_bar p'_c(s))
%
% Equation (9) is the tridiagonal form of a hydraulic LADDER network: each
% duct becomes one lumped inertance, resistance and compliance.  Two things
% are wrong with using it directly here.
%
% 1. Conditioning.  Assembling and inverting that matrix is badly scaled --
%    for a liquid line the compliance is ~1e-13 m^3/Pa, so the 1/C entries
%    are ~1e13 next to L*s^2 entries of ~1e5.  The solve only stays quiet
%    with the nearlySingularMatrix warning suppressed.
%
% 2. Validity.  A lumped element is only meaningful while the duct is short
%    compared with the acoustic wavelength in it (l < lambda/10).  For the
%    LOX line, c = sqrt(K/rho) = 1389 m/s over 0.35 m, so the lumped form
%    dies above ~400 Hz -- yet the coupling of interest sits near 2200 Hz.
%    A lumped model run five times past its ceiling invents resonances.
%
% Both are fixed by treating each duct as what it physically is: a
% distributed transmission line.  The impedance seen looking upstream
% transforms through a uniform duct exactly as
%
%     Z <- Z_c (Z + Z_c tanh(gamma l)) / (Z_c + Z tanh(gamma l))
%
% with characteristic impedance Z_c = rho c / A and propagation constant
% gamma = s/c + loss.  This is exact at every frequency, needs no matrix,
% and collapses to the ladder recursion of Eq (9) when gamma*l << 1.
%
% model: 'transmission' (default, exact) | 'lumped' (Eq 9 as written)

if nargin < 5 || isempty(model); model = 'transmission'; end
n      = seg.n_duct;
a_term = zeros(size(s));

for k = 1:numel(s)
    sk = s(k);
    Z  = seg.z_manifold;         % stiff plenum at the upstream end
    for i = 1:n
        switch model
            case 'transmission'
                Zc = seg.z_char(i);
                % Propagation constant with a distributed loss term set by
                % the segment's friction resistance.
                gl = (sk/seg.c_sound + seg.alpha_loss(i))*seg.length(i);
                t  = tanh(gl);
                Z  = Zc*(Z + Zc*t)/(Zc + Z*t);
            case 'lumped'
                Z = Z + seg.z_series(i)*sk + seg.r_series(i);
                Y = seg.c_shunt(i)*sk;
                if Y ~= 0; Z = 1/(1/Z + Y); end
            otherwise
                error('yang_ch12:model', 'unknown feed model "%s"', model);
        end
    end
    % The injector orifice is short compared with every wavelength of
    % interest, so it stays lumped: inertance plus the design pressure drop.
    Z = Z + seg.z_injector*sk + seg.r_injector;
    % Volume-flow admittance -> mass flow -> the nondimensional form of Eq (10)
    a_term(k) = (pc/mdot)*seg.rho/Z;
end
end

% =========================================================================
function c = default_cfg()
c.p_chamber = 20.7e6;
c.mdot_ox   = 75;    c.mdot_fuel = 25;
% The sweep must reach near DC and run out to where |F| has rolled off, or
% the Nyquist contour is not closed and the encirclement count is invalid.
% Log spacing keeps resolution at both ends; the linear block resolves the
% resonant peak.
c.f_sweep   = unique([logspace(0, 2, 120), linspace(100, 9000, 1400), ...
                      logspace(log10(9000), log10(80000), 400)]);
c.f_dc_tol  = 2;        % Hz; sweep must start at or below this to close the contour
c.f_report_max = 12000; % Hz; above this the injector/chamber models say nothing
c.mag_floor    = 0.01;  % ignore phase crossovers with negligible gain
% Feed-line model: 'transmission' is exact at all frequencies; 'lumped' is
% Eq (9) as written and is only valid below adm.f_lumped_max_*.
c.feed_model   = 'transmission';

% --- oxidiser line: manifold -> distribution passage -> injector ---------
c.ox.length   = [0.30 0.05];
c.ox.diam     = [0.05 0.02];
c.ox.area     = pi/4*c.ox.diam.^2;
c.ox.area_in  = c.ox.area;
c.ox.area_out = c.ox.area;
c.ox.volume   = c.ox.area.*c.ox.length;
c.ox.rho      = 1140;
c.ox.f_friction = 0.02;
c.ox.u_mean   = 20;
c.ox.dpdrho_inv = 1/2.2e9;              % 1/K_bulk for LOX  [m^3/Pa per m^3]
c.ox.z_manifold = 1.0e3;                % stiff plenum source impedance
% Injector orifice, sized from the design pressure drop:
%   Q = Cd A sqrt(2 dP/rho)  ->  A = Q/(Cd sqrt(2 dP/rho))
c.ox.dp_injector     = 3.0e6;           % Pa
c.ox.length_injector = 0.020;           % m
c.ox.area_injector   = (75/1140)/(0.75*sqrt(2*3.0e6/1140));

% --- fuel line (gaseous hydrogen side) ----------------------------------
c.fuel.length   = [0.40 0.06];
c.fuel.diam     = [0.06 0.025];
c.fuel.area     = pi/4*c.fuel.diam.^2;
c.fuel.area_in  = c.fuel.area;
c.fuel.area_out = c.fuel.area;
c.fuel.volume   = c.fuel.area.*c.fuel.length;
c.fuel.rho      = 5.0;
c.fuel.f_friction = 0.025;
c.fuel.u_mean   = 200;
c.fuel.dpdrho_inv = 1/(1.4*20.7e6);     % gas compliance, 1/(gamma p)
c.fuel.z_manifold = 5.0e2;
c.fuel.dp_injector     = 3.5e6;
c.fuel.length_injector = 0.030;
c.fuel.area_injector   = (25/5.0)/(0.80*sqrt(2*3.5e6/5.0));

c.tau_ox   = 0.8e-3;   c.tau_fuel = 0.5e-3;
c.n_burn   = 0.5;      c.tau_burn = 1.0e-3;
% Chamber acoustic response.  zeta must match the chamber's actual acoustic
% damping, alpha/omega -- Ch.1 gives alpha = -248 1/s at omega = 13864 rad/s
% for the 1L mode, i.e. zeta = 0.018.  Using an arbitrarily small zeta
% inflates |R_c| at resonance and with it the whole loop gain.
c.f_chamber= 2206.5;   c.zeta_chamber = 0.018;  c.gain_chamber = 1.0;
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
