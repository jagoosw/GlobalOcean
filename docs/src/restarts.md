# Restart files

[`pickup_restart!`](@ref)`(simulation, date)` starts a simulation from the checkpoint of the OMIP spin-up (`orca_checkpoint_iteration*.jld2` in `NumericalOcean.OMIP_RESTART_DIR[]`, which points at the spin-up on Bouchet) whose forcing date is closest to `date`, and sets the model clock so the forcing is picked up where the checkpointed run had it.

The spin-up was forced with 1958--2018 JRA55 and checkpointed every 360 days, so checkpoints fall on different dates in each cycle; by default only the last cycle is searched (pass `cycle = n`, 0-based, for another).

```julia
simulation = forced_ocean_simulation(grid)

# the last-cycle state nearest 1 January 1958, with the clock at its time since 1958-01-01
pickup_restart!(simulation, DateTime(1958, 1, 1))
```

For a run with a different `start_date`, pass the same `start_date` to `pickup_restart!`: only checkpoints dated on or after it can be used.

For repeat-year runs pass `repeat_year = true` to pick the checkpoint nearest `date` (in any year) and set the clock to its time of year since `start_date`:

```julia
simulation = forced_ocean_simulation(grid; jra55_dataset = RepeatYearJRA55(), start_date = DateTime(1990, 1, 1))

pickup_restart!(simulation, DateTime(1990, 1, 1); start_date = DateTime(1990, 1, 1), repeat_year = true)
```

Only the model state is restored: the iteration is reset to zero, and output and callback schedules start afresh from the new time.
State not in the checkpoint (e.g. biogeochemical tracers when restarting from the physics-only spin-up) keeps the values it was initialised with.
