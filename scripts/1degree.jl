using GlobalOcean
using NumericalEarth
using Oceananigans
using Oceananigans.Units
using CUDA

auto_config_directories!()

grid = ORCA1(GPU())

simulation = GlobalOcean.forced_ocean_model(grid;
                                            jra55_dataset = MultiYearJRA55(),
                                            staging = true,
                                            stop_time = 5 * 21915days)

run!(simulation)
