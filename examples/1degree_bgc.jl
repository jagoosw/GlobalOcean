using GlobalOcean
using NumericalEarth
using Oceananigans
using Oceananigans.Units
using OceanBioME
using Dates
using CUDA

arch = GPU()
grid = ORCA1(arch)

surface_PAR = PARFromShortwave(grid)
light_attenuation = PrescribedAttenuationPAR(grid, surface_PAR;
                                             attenuation = PrescribedChlorophyllAttenuation(first_color_fraction = 0.0),
                                             attenuation_discrete_form = true)

plankton = ImplicitProductivity(; maximum_community_productivity = 9.0 / 360days)

biogeochemistry = MITgcmDIC(grid;
                            plankton,
                            light_attenuation,
                            open_bottom = false,
                            implicit_sinking = true,
                            store_flux = true)

pCO₂ = MaunaLoaCO₂(arch; dates = DateTime(1990, 1, 15):Month(1):DateTime(1990, 12, 15),
                         start_date = DateTime(1990, 1, 1),
                         period = 365days)

simulation = forced_ocean_simulation(grid;
                                     biogeochemistry,
                                     atmosphere_tracers = (; pCO₂),
                                     jra55_dataset = RepeatYearJRA55(),
                                     start_date = DateTime(1990, 1, 1),
                                     backend_size = 2920, # the whole repeat year of JRA55 in memory
                                     stop_time = 1000 * 365days)

omip_diagnostics!(simulation)
oaemip_diagnostics!(simulation)
checkpointer!(simulation)

run!(simulation)
