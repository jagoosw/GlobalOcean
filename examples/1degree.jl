using GlobalOcean
using NumericalEarth
using Oceananigans
using Oceananigans.Units
using Dates
using CUDA

auto_config_directories!()

grid = ORCA1(GPU())

simulation = forced_ocean_simulation(grid)

pickup_restart!(simulation, DateTime(1958, 1, 1))

omip_diagnostics!(simulation; async = true) # needs `julia --threads ≥ 2`
checkpointer!(simulation)

try
    run!(simulation)
finally
    flush_output!(simulation) # write anything still queued
end
