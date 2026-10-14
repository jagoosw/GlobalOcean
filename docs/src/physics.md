# Physics

As shown in `examples/1degree.jl`, the default configuration is an ocean--sea ice model forced with the JRA55 atmosphere and land, configured with (semi-)validated closures.
The model is initialised with WOA climatological temperature and salinity, and ECCO sea ice concentration and thickness.

```julia
using NumericalOcean
using NumericalEarth
using Oceananigans
using Oceananigans.Units
using Dates
using CUDA

auto_config_directories!()

grid = ORCA1(GPU())

simulation = forced_ocean_simulation(grid)

pickup_restart!(simulation, DateTime(1958, 1, 1))

omip_diagnostics!(simulation)
checkpointer!(simulation)

run!(simulation)
```

The `grid` can be any global grid, but automatic setup is only checked for `ORCA1`, `ORCA025`, and `ORCA12`, which are nominally ``1\degree``, ``1/4\degree``, and ``1/12\degree``.

The whole model is set up through [`forced_ocean_simulation`](@ref), so everything can be modified by passing arguments.
For example, to add a passive tracer `c` and release it in a circle of radius 1° around (0°E, 0°N) for the first day (`t` in seconds):

```julia
c_release = Forcing((λ, φ, z, t) -> (sqrt(λ^2 + φ^2) < 1) & (t < 86400))
simulation = forced_ocean_simulation(grid;
                                     tracers = (:c, ),
                                     forcing = (; c = c_release))
```

See the [`forced_ocean_simulation`](@ref) docstring for all of the options.
