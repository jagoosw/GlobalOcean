using GlobalOcean
using NumericalEarth
using Oceananigans
using Oceananigans.Units
using CUDA

auto_config_directories!()

grid = ORCA1(GPU())

simulation = forced_ocean_simulation(grid)

omip_diagnostics!(simulation)
checkpointer!(simulation)

run!(simulation)
