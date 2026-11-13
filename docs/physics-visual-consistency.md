# Physics → events → visible sample

`universe.gd` owns physical state. `particle_chemistry.gd` defines its finite visual
representation. `particle_field.gd` animates that representation. Particle positions,
frame rate, the hand and random selection never feed composition back into physics.

## Numerical state and events

Forward nuclear rates are nonnegative. The fits retain their original coefficients;
`_rate` applies the absolute-value convention in AlterBBN's `rate_all`
([source, line 1335](https://github.com/espensem/AlterBBN/blob/d3cc09ade68eac73a864323ae3c3a5fa130675be/src/bbnrate.c#L1335)).
Some fits cross zero near their temperature limits. Treating that sign as a negative
forward rate creates unphysical production/destruction terms; it is distinct from
the sign of the **net** forward-minus-reverse flux.

Each accepted SDIRK2 interval integrates both state and events with the same weights:
`dt × ((1 − gamma) × flux(stage 1) + gamma × flux(stage 2))`. Every nuclear channel
that changes the displayed species has a signed rule, including two-to-two exchanges
and destruction of A=7 nuclei. Tritium decay stays inside the combined A=3 group.
Above the network temperature, dissociation preserves the separate proton/neutron
products of tritium, helium-3, lithium-7 and beryllium-7.

Newton iterations have a measured backward error, not just a fixed iteration count.
The scale includes the equation's Jacobian row because stiff equilibrium contains
large cancelling terms. The thresholds are numerical settings, not fitted physical
constants: absolute `1e-14`, relative `1e-10`, at most eight corrections. The redundant
proton equation uses exact baryon conservation. An accepted nuclear interval must
also conserve baryons within `1e-10`.

A failed interval is bisected (at most ten levels). After four subdivision levels,
backward Euler replaces SDIRK2 for a monotone stiff-decay update; its fluxes use the
same backward-Euler quadrature. `solver_retries` and `solver_fallbacks` expose those
paths. `solver_max_residual` includes rejected trials and is **not** an accepted-state
accuracy bound. The ordinary reference trajectory is tested separately from a
synthetic stiff-decay case that exercises the fallback.

On exhausted retries, `advance` returns false, preserves the last accepted substep
and its pending events, and stores `numerical_error`. Earlier successful substeps in
the same call remain accepted. The scene pauses and removes its forecast; reset
starts a valid new calculation. A forecast has independent state and events and is
invalidated when expansion, density or neutrino parameters change, including via
autopilot. A contracting/stationary universe has no cooling forecast.

## Finite sample and rounding

The display budget is 500–1350 baryons, with a 5200-slot pool. A quark represents one
third of a baryon; a nucleus represents its integer mass number. The sampler:

1. Splits the budget between quark triplets and hadrons using the model's hadron fraction.
2. Rounds nuclear abundances down, then allocates remaining baryons to free neutrons
   and protons. This gives exactly the requested baryon budget without scaling the model.
3. Splits displayed protons and helium-4 into ions/atoms using `xH` and `xHe`.
4. Supplies electrons for the **display representatives'** ionic charge.

A=3 groups tritium/helium-3; A=7 groups lithium-7/beryllium-7. Thus displayed charge
is not isotope-resolved charge accounting. Deuterium is displayed as a nucleus, not
a separate neutral atom. Abundances smaller than one particle remain in the numeric
HUD; the renderer does not inflate rare species to make them visible.

## Animation and reconciliation

Signed events describe possible visual transformations, not an exact census. A
reaction reserves all inputs and verifies output capacity before consuming anything.
Missing partners or a full pool leave both particles and observation intact. Forward
and reverse transformations conserve displayed baryon number. Ten animated reactions
and eighty scheduling attempts per frame bound work, using round-robin channels.

The backlog is not clamped to ±60. Fractional/unprocessed amounts remain queued.
If any channel exceeds 5200 events, an explicit resynchronization request supersedes
the entire backlog (`event_overflows`). Unknown or non-finite events are errors.

Every 0.5 seconds, or on overflow, reconciliation waits for existing bonds to finish
(at most 0.85 seconds), then clears the superseded events and moves toward the current
model sample. It performs up to `ceil(2400 × delta)` corrections, capped at 128 per
frame. Density changes also smooth the display budget. This bounds frame work, not
instantaneous composition error: while physics changes rapidly, animation can lag.
With fixed model and density, it converges to the exact rounded sample; tests cover
30, 60 and 144 FPS, live event streams, a long frame, density changes and reheating.

Reconciliation retains unaffected particle slots and preferentially retains the
observed particle. If it must remove that representative, observation ends with an
explicit message. It never adds a fictitious reaction to the history. Actual
transformations transfer observation to a surviving product and record the event.
Restart clears all pending events, bonds, observation, forecasts and held input.

## Verification

Run `python3 tools/check.py` with Godot 4.7.2 stable. No third-party Python packages
are needed. The runner imports resources, enforces timeouts and rejects engine errors
or missing summaries even when the process exits zero. It is used by public hosted
PR checks and before release export; it requires no secrets or self-hosted runner.

- `sim_check.gd`: existing AlterBBN/Planck comparisons and forecast step accuracy;
  tolerances are unchanged. Evolution loops now detect failure and have step limits.
- `model_contract_check.gd`: rate positivity, singular solve, rollback, stiff decay,
  signed flux versus state changes, baryon conservation and step refinement.
- `consistency_check.gd`: independently specified products in both directions,
  atomic pool capacity, observation history, queue bounds, rounding and convergence.
- `lifecycle_check.gd`: actual scene controls, pause, forecast invalidation, reheating
  below the cooling limit, numerical failure and restart.

Headless checks do not validate rendering or browser performance. Use the README's
screenshot arguments in a native window and `tools/bench_field.gd` for frame-cost
measurements. Existing cosmological approximations and observational tolerances
remain in the README; this work does not establish independent scientific validation
of arbitrary contraction histories.
