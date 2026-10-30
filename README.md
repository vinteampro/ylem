# Ylem: The First 400,000 Years

*A meditation built on real physics.*

**English** · [Русский](README.ru.md)

A meditative game about the birth of matter. You steer the young Universe — its expansion
rate and matter density — and watch quarks gather into protons, protons and neutrons fuse
into helium, and nuclei capture electrons to become the first atoms.

About 5 minutes, from the first microsecond to the Dark Ages. English and Russian.

**Play it on itch.io: [vinteam.itch.io/ylem](https://vinteam.itch.io/ylem)** — as a download for
Windows and Linux, or in the browser (also at [ylem.live](https://ylem.live)). The downloads look
better: in the browser (WebGL) the glow is only approximated.

## Running from source

Open the folder in [Godot 4.7](https://godotengine.org/download/): Import → choose
`project.godot`, then press **F5**. To build Windows, Linux or web versions, see "Building".

## Controls

**Levers**

| | |
|---|---|
| **Expansion rate** | slower — neutrons have time to decay, less helium; faster — more helium; below zero — contraction and reheating. You see it at once: particles stream from the centre, brightness and pitch change |
| **Matter density** | denser — more particles, deuterium burns almost entirely; sparser — fewer particles, more deuterium survives |
| **Flow of time** | from pause to ×2 |
| **Let go** | the levers drift back to the values of our Universe |
| Near our Universe's value | the slider snaps to it with a soft click |
| Double-click a slider | reset to our Universe's value |
| Mouse wheel over a slider | step; with Shift — fine step |

You can hear and see the expansion rate: while you drag the slider, the H-alpha line sounds
and slides down as expansion speeds up (redshift) and up as it slows (blueshift), and the
frame briefly turns red or blue. The music is always slightly pitch-shifted. Density changes
how "crowded" the sound is: denser — duller and drier, sparser — with a long echo.

During nucleosynthesis the composition panel shows a **forecast** ("24.9% → 31.2%", a diamond
on the bar) and a tick for our Universe's value. The ring around the neutron row is their
decay clock.

**Hand and camera**

| | |
|---|---|
| Hold LMB | compress and swirl the plasma: reactions happen under your hand |
| Hold RMB | rarefy |
| Click a particle | follow it and read its story (Esc — let go) |
| Mouse wheel | zoom in / out |
| Middle button, arrows, WASD | pan |
| Space | pause |
| H | hide the interface |
| F / F11 | fullscreen |
| English / Русский | language button in the levers panel (system language by default) |

Your touches are **density fluctuations**. Where you compressed the plasma, cold spots appear
in the cosmic microwave background after recombination (the Sachs–Wolfe effect), and in the
Dark Ages gravity pulls matter there — future sites of the first stars. This is artistic
licence: the model counts the reactions, the hand only decides where a flash is shown
(see "Simplified").

At the end the game compares your composition with our Universe.

The game starts with a faint point of light in the dark. Click it rapidly to wake it up and
trigger the Big Bang (or press Enter).

## Scientific data

### Inputs

| Quantity | In the model | Source |
|---|---|---|
| Neutron lifetime | 878.4 s | PDG 2024 |
| Baryons per photon η | 6.12×10⁻¹⁰ (Ωb·h² = 0.02237) | Planck 2018 |
| H₀, Ωm | 67.4 km/s/Mpc, 0.315 | Planck 2018 |
| Effective number of neutrinos N_eff | 3.044 | Standard Model (Froustey et al. 2020; Bennett et al. 2021) |
| CMB temperature | 2.7255 K | FIRAS |
| Quark–hadron transition | 156.5 MeV | HotQCD (lattice QCD), 2019 |
| Rates of 18 nuclear reactions | fits and tables | NACRE 1999, Coc et al. 2015, Serpico et al. 2004, Ando et al. 2006, Cyburt & Davids 2008, Hou et al. 2015, CF88 — as implemented in AlterBBN 2.2 |

The model has no fudge factors.

### Check against AlterBBN

`tools/sim_check.gd` runs the model on a grid of η (×0.1 to ×10) and neutrino number
(ΔN from −2 to +6) and compares it with the open-source code
[AlterBBN 2.2](https://alterbbn.hepforge.org/) (Arbey et al., CPC 183 (2012) 1822),
built with the same η, N_ν = 3.044 and τ_n = 878.4 s.
Tolerances: Yp ±0.0025, D/H and ³He/H ±6%, ⁷Li/H ±12%. All 10 grid points are within tolerance:

| η×, ΔN | Yp, model / AlterBBN | D/H | ³He/H | ⁷Li/H |
|---|---|---|---|---|
| 0.1, 0 | 0.2054 / 0.2065 | 9.81 / 9.84 ×10⁻⁴ | 5.43 / 5.41 ×10⁻⁵ | 1.24 / 1.24 ×10⁻⁹ |
| 1, 0 | 0.2457 / 0.2469 | 2.44 / 2.42 ×10⁻⁵ | 1.03 / 1.03 ×10⁻⁵ | 5.40 / 5.50 ×10⁻¹⁰ |
| 10, 0 | 0.2658 / 0.2670 | 6.34 / 6.13 ×10⁻⁹ | 3.88 / 3.89 ×10⁻⁶ | 6.67 / 6.72 ×10⁻⁹ |
| 1, +3 | 0.2790 / 0.2802 | 3.42 / 3.41 ×10⁻⁵ | 1.16 / 1.16 ×10⁻⁵ | 4.15 / 4.20 ×10⁻¹⁰ |

It also checks that the in-game forecast (coarse step 0.05) differs from the exact run by
less than 0.001 in Yp and 3% in D/H.

### Results for our Universe's parameters

| | Model | Reality |
|---|---|---|
| Helium-4, mass fraction | 24.57% | AlterBBN 24.69%, PRIMAT 24.71%; observed 24.5 ± 0.3% (PDG 2024) |
| D/H | 2.44×10⁻⁵ | AlterBBN 2.42×10⁻⁵; observed (2.547 ± 0.029)×10⁻⁵ (PDG 2024) |
| ³He/H | 1.03×10⁻⁵ | AlterBBN 1.03×10⁻⁵ |
| ⁷Li/H | 5.4×10⁻¹⁰ | AlterBBN 5.5×10⁻¹⁰; 1.6×10⁻¹⁰ in old stars — the "lithium problem" |
| T_ν/T after e± annihilation | 0.7148 | (4/11)^⅓ = 0.7138 |
| Hadronization | ~20 μs | ~10–20 μs |
| Helium synthesis (half of the final amount) | ~4 min | 3–4 min |
| Half of hydrogen neutral | z ≈ 1270 | z ≈ 1270 |
| Last scattering surface (peak of the visibility function) | z* ≈ 1096, ~368 kyr | Planck 2018: z* = 1089.8 |
| Residual ionization | 3×10⁻⁴ | ~2–3×10⁻⁴ |

**Why 24.57% helium rather than 24.7%.** Helium is set almost entirely by the neutron-to-proton
ratio when the weak reactions freeze out. Here those reactions are computed in the Born
approximation with the Coulomb correction and normalized to the neutron lifetime. Precise codes
also add radiative corrections, finite nucleon mass corrections and neutrino heating from e±
annihilation. Hence a shift of −0.0012, the same across the whole grid. Observations
(24.5 ± 0.3%) agree with both the model and the precise codes.

**Why z* = 1096 rather than 1090.** Hydrogen recombines through Peebles' three-level atom
without the RECFAST/HyRec corrections, helium through Saha. This makes recombination slightly
earlier, by about 0.5% in redshift.

**How it works:**
- *Expansion* — the Friedmann equation H² = 8πG/3·ρ, where ρ includes photons, e± and muons
  (exact Fermi–Dirac integrals), quarks and hadrons, neutrinos (N_eff = 3.044), matter and Λ.
  Temperature follows from entropy conservation, so e± annihilation heats the photons but not
  the decoupled neutrinos.
- *Weak n ⇄ p reactions* — integrals over e±, ν and ν̄ spectra at their own temperatures
  (6 processes including decay), with the Fermi function.
- *Nuclei* — 8 species (n, p, D, T, ³He, ⁴He, ⁷Li, ⁷Be), 18 reactions, reverse rates from
  detailed balance. The system is stiff, so the step is implicit: a two-stage second-order SDIRK2
  scheme with Newton's method. Above 27 billion K nuclei do not survive; only n ⇄ p is computed.
- *Recombination* — hydrogen per Peebles (through the n = 2 level), helium per Saha. The moment
  of transparency is the peak of the visibility function g = τ'·e^(−τ).
- *Dark Ages* — clump contrast grows with the scale factor (δ ∝ a).

**Simplified:**
- the quark–hadron transition is a smooth blend of a pion gas and the quark–gluon plasma, and
  hadronization is a phenomenological curve (it does not affect nucleosynthesis);
- neutrinos decouple instantly at 2 MeV; incomplete decoupling is included only through N_eff;
- weak reactions without radiative corrections (Yp is 0.001 lower than precise codes, see above);
- no ⁶Li and no nuclei heavier than ⁷Be: they do not affect the final composition;
- the "expansion rate" lever multiplies H in all epochs at once. It has no direct reference;
  the closest analogue is extra neutrino species, and that is checked against AlterBBN;
- the player's "hand" is artistic licence. Real fluctuations were laid down by inflation long
  before the first microsecond. The model counts the reactions; the hand only decides where a
  flash is shown. The sign of the spots follows the large-scale Sachs–Wolfe effect (an
  overdensity looks cold); below the sound horizon it would depend on the phase of acoustic
  oscillations. CMB anisotropies are amplified about 10,000 times, otherwise they would be invisible;
- quark colours are arbitrary.

## Project layout

```
scenes/main.tscn            — the only scene; everything else is built in code
scripts/universe.gd         — the physics model (numbers only, no graphics)
scripts/particle_field.gd   — particles, fusions, flashes, gamma rays (MultiMesh + HDR)
scripts/main.gd             — the director: pacing, epochs, narration, wiring
scripts/start_screen.gd     — start screen: wake the point with clicks, then the Big Bang
scripts/hud.gd              — interface: timeline, composition, levers, results
scripts/audio_director.gd   — ambience, reaction "chimes", music per epoch
scripts/i18n.gd             — all texts in Russian and English (UI, epochs, narration, codex)
scripts/palette.gd          — plasma colours from black-body radiation
shaders/plasma.gdshader     — background: plasma and the CMB
shaders/haze.gdshader       — haze over the particles
audio/music/                — music, one Suno track per epoch
tools/sim_check.gd          — headless physics check (against AlterBBN 2.2)
```

## Building

You need [Godot 4.7](https://godotengine.org/download/) and export templates of the same
version (in the editor: Editor → Manage Export Templates). Builds go to `build/` inside the
project (ignored by git):

```
godot --headless --path . --export-release "Windows Desktop" build/Ylem.exe
godot --headless --path . --export-release "Linux" build/linux/Ylem.x86_64
godot --headless --path . --export-release "Web" build/web/index.html
```

or in the editor: Project → Export. The web build uses threads (audio is mixed off the main
thread), so on itch.io enable **SharedArrayBuffer support**, and a self-hosted server must send
COOP/COEP headers (see [RELEASING.md](RELEASING.md)). In the browser (WebGL) the frame cannot store brightness
above 1, so `main.gd` dims particles and the background there and raises brightness back at
the end of the frame (`WEB_GAIN`) — otherwise the glow disappears.

## Development

Check the physics for different parameters:

```
godot --headless --path . --script res://tools/sim_check.gd
```

Start at a given temperature and take screenshots:

```
godot --path . -- --start-T=1.5e9 --shot=shot_%d.png --shot-at=5,20
```

More debug arguments: `--expansion=2 --density=0.3` (starting levers),
`--demo=touch` (a virtual hand draws a circle), `--demo=follow` (pick a particle),
`--launch-at=2` (wake the point on the start screen automatically at 2 s).
With `--start-T` the start screen is skipped.

## Contributing

Help with the physics and the gameplay is welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md):
how to run the physics check, and the main rule: no fudge factors, every number has a source.

## License

- **Code** (`scripts/`, `shaders/`, `scenes/`, `tools/`, project files) — [MIT](LICENSE).
- **Music, splash and icon** (`audio/music/*.mp3`, `splash.png`, `icon.svg`) — all rights
  reserved, see [ASSETS_LICENSE.md](ASSETS_LICENSE.md). They may be redistributed only as part
  of the unmodified game. The game also runs without music — then you hear the synthesized ambience.
- **Physics data** — reaction rates and constants come from published work (see "Scientific
  data") as implemented in [AlterBBN 2.2](https://alterbbn.hepforge.org/); if you use the model
  in your own work, please cite those sources.
