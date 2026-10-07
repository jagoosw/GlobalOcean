using Oceananigans.Units
using WorldOceanAtlasTools
using OMIPSimulations: henyey_diffusivity_field, νhb, build_sea_ice_grid, woa_to_teos10!, salinity_surface_restoring, NormalizeTotalWater
using Oceananigans.TurbulenceClosures: TriadIsopycnalSkewSymmetricDiffusivity, FluxTapering
using ClimaSeaIce: IncrementalRemapping
using Oceananigans.Architectures: architecture
using Oceananigans.TurbulenceClosures.TKEBasedVerticalDiffusivities: CATKEMixingLength
using NumericalEarth.DataWrangling.SeaWiFS: SeaWiFSMonthly
using NumericalEarth.DataWrangling: ConservativeSurfaceFluxRestoringCallback
using NumericalEarth.EarthSystemModels.InterfaceComputations: COARELogarithmicSimilarityProfile, ConvectiveGustiness,
                                                              WindDependentWaveFormulation, TemperatureDependentAirViscosity,
                                                              atmosphere_sea_ice_stability_functions,
                                                              ImpureSaturationSpecificHumidity, AtmosphericThermodynamics

function forced_ocean_model(grid; 
                            arch = architecture(grid),
                            backend_size = 50,
                            start_date = DateTime(1958, 1, 1),
                            end_date = DateTime(2018, 1, 1),
                            atmosphere_tracers = NamedTuple(),
                            staging = false,
                            jra55_dataset = RepeatYearJRA55(),
                            jra55_dir = staging ? stage_jra55!(jra55_dataset) : forcing_dir[],
                            land = JRA55PrescribedLand(grid; 
                                                       dir = jra55_dir, 
                                                       dataset = jra55_dataset,
                                                       start_date, 
                                                       end_date, 
                                                       time_indices_in_memory = backend_size, 
                                                       prefetch = true,
                                                       maximum_search_radius = default_maximum_search_radius(grid),
                                                       spread_radius = default_river_spread_radius(grid),
                                                       maximum_spread_cells = default_river_spread_cells(grid)),

                            eddy_closure = grid isa ORCA1GRID ? TriadIsopycnalSkewSymmetricDiffusivity(VerticallyImplicitTimeDiscretization();
                                                                                                       κ_skew = 800, κ_symmetric = 800, 
                                                                                                       slope_limiter = FluxTapering(1e-2))
                                                              : nothing,
                            background_diffusivity = VerticalScalarDiffusivity(κ = henyey_diffusivity_field(grid), ν = 3e-5),
                            vertical_closure = CATKEVerticalDiffusivity(VerticallyImplicitTimeDiscretization(); 
                                                                        mixing_length = CATKEMixingLength(Cᵇ = 0.01), 
                                                                        maximum_viscosity = 3, 
                                                                        maximum_tracer_diffusivity = 3, 
                                                                        maximum_tke_diffusivity = 3, 
                                                                        negative_tke_damping_time_scale = 10),
                            horizontal_viscosity = grid isa ORCA1GRID ? 
                                                   HorizontalScalarBiharmonicDiffusivity(ν = νhb, κ = nothing, discrete_form = true,
                                                                                         parameters = 50days) :
                                                   nothing,
                            closures = (vertical_closure, eddy_closure, horizontal_viscosity, background_diffusivity),
                            salt_restoring = salinity_surface_restoring(grid, WOAMonthly(); 
                                                                        restoring_dir = restoring_dir[], 
                                                                        piston_velocity = 0.254),
                            chlorophyll = FieldTimeSeries(Metadata(:chlorophyll; 
                                                                   dataset = SeaWiFSMonthly(), 
                                                                   dates = (DateTime(2000, 1, 1), DateTime(2000, 12, 1)), 
                                                                   dir = restoring_dir[]), grid),
                            radiative_forcing = TwoColorRadiation(grid; chlorophyll),
                            momentum_advection = WENOVectorInvariant(; vorticity_order = grid isa ORCA1GRID ? 5 : 9,
                                                                       time_discretization = AdaptiveVerticallyImplicitDiscretization(cfl=0.5)),
                            ocean = ocean_simulation(grid;
                                                     Δt = 1minutes,
                                                     radiative_forcing,
                                                     momentum_advection,
                                                     materialize_buoyancy_gradients = true, 
                                                     free_surface = SplitExplicitFreeSurface(grid; substeps = default_barotropic_substeps(grid)),
                                                     additional_surface_fluxes = (; S = salt_restoring),
                                                     closure = filter(!isnothing, closures),
                                                     river_routing = land.river_routing),

                            sea_ice_immersed_latitudes = (-50, 35),
                            sea_ice_grid = build_sea_ice_grid(grid, sea_ice_immersed_latitudes, GridFittedBottom),
                            sea_ice = sea_ice_simulation(sea_ice_grid, ocean;
                                                         advection = IncrementalRemapping(),
                                                         thickness_categories = 4),
                            atmosphere = JRA55PrescribedAtmosphere(arch; 
                                                                   dataset = jra55_dataset,
                                                                   tracers = atmosphere_tracers,
                                                                   dir = jra55_dir,
                                                                   start_date,
                                                                   end_date,
                                                                   time_indices_in_memory = backend_size),
                            # CCSM3 sea-ice albedo reads live model fields; the atmosphere sees the snow surface
                            sea_ice_albedo = SeaIceAlbedo(sea_ice.model.ice_thickness,
                                                          sea_ice.model.snow_thickness,
                                                          sea_ice.model.snow_thermodynamics.top_surface_temperature),
                            radiation = JRA55PrescribedRadiation(arch;
                                                                 dataset = jra55_dataset,
                                                                 dir = jra55_dir,
                                                                 start_date,
                                                                 end_date,
                                                                 time_indices_in_memory = backend_size,
                                                                 prefetch = true,
                                                                 ocean_surface   = SurfaceRadiationProperties(0.06, 1.00),
                                                                 sea_ice_surface = SurfaceRadiationProperties(sea_ice_albedo, 1.0)),
                            atmosphere_correction = nothing,
                            radiation_correction = nothing,
                            biogeochemistry_interface_kwargs = NamedTuple(),
                            air_kinematic_viscosity = TemperatureDependentAirViscosity(),
                            similarity_form = COARELogarithmicSimilarityProfile(),
                            atmosphere_ocean_fluxes = SimilarityTheoryFluxes(; similarity_form,
                                                                               subgrid_velocities           = ConvectiveGustiness(minimum_gustiness = 0.5),
                                                                               momentum_roughness_length    = MomentumRoughnessLength(; wave_formulation = WindDependentWaveFormulation(), air_kinematic_viscosity),
                                                                               temperature_roughness_length = ScalarRoughnessLength(; air_kinematic_viscosity),
                                                                               water_vapor_roughness_length = ScalarRoughnessLength(; air_kinematic_viscosity)),
                            atmosphere_sea_ice_fluxes = SimilarityTheoryFluxes(; stability_functions = atmosphere_sea_ice_stability_functions(),
                                                                                 similarity_form,
                                                                                 subgrid_velocities = ConvectiveGustiness(minimum_gustiness = 0.2),
                                                                                 momentum_roughness_length = 5e-4,
                                                                                 temperature_roughness_length = 5e-5,
                                                                                 water_vapor_roughness_length = 5e-5),
                            sea_ice_ocean_heat_flux = ThreeEquationHeatFlux(; heat_transfer_coefficient = 0.0057,
                                                                              friction_velocity = MomentumBasedFrictionVelocity()),
                            ice_meltwater_enthalpy = InterfaceTemperatureMeltwater(),
                            saturation_enhancement = GillSaturationEnhancement(),
                            humidity = (ocean = ImpureSaturationSpecificHumidity(AtmosphericThermodynamics.Liquid(), 0.98; saturation_enhancement),
                                        sea_ice = ImpureSaturationSpecificHumidity(AtmosphericThermodynamics.Ice(); saturation_enhancement)),
                            interfaces = ComponentInterfaces(atmosphere, ocean, sea_ice; radiation, land,
                                                             atmosphere_ocean_fluxes,
                                                             atmosphere_sea_ice_fluxes,
                                                             sea_ice_ocean_heat_flux,
                                                             ice_meltwater_enthalpy,
                                                             atmosphere_ocean_interface_specific_humidity = humidity.ocean,
                                                             atmosphere_sea_ice_interface_specific_humidity = humidity.sea_ice,
                                                             exchanger_correction = atmosphere_correction, radiation_correction,
                                                             biogeochemistry_interface_kwargs),
                            Δt = default_Δt(grid),
                            stop_time = 1000 * 365days)

    T_init = Field(Metadatum(:temperature; dir = restoring_dir[], dataset = WOAAnnual()), grid)
    S_init = Field(Metadatum(:salinity;    dir = restoring_dir[], dataset = WOAAnnual()), grid)
    woa_to_teos10!(T_init, S_init)
    set!(ocean.model, T=T_init, S=S_init)

    set!(sea_ice.model, h = Metadatum(:sea_ice_thickness;     dir = restoring_dir[], dataset = ECCO4Monthly(), date = DateTime(1993, 1, 1)),
                        ℵ = Metadatum(:sea_ice_concentration; dir = restoring_dir[], dataset = ECCO4Monthly(), date = DateTime(1993, 1, 1)))

    model = OceanSeaIceModel(ocean, sea_ice; atmosphere, radiation, land, interfaces)

    simulation = Simulation(model; Δt, stop_time)

    if staging && !(jra55_dataset isa RepeatYearJRA55)
        staging_callback = JRA55DataStagingCallback(; source_dir = forcing_dir[],
                                                      staging_dir = staging_dir[],
                                                      start_date)
        add_callback!(simulation, staging_callback, TimeInterval(30days))
    end

    add_callback!(simulation, ConservativeSurfaceFluxRestoringCallback(salt_restoring, ocean.model), IterationInterval(1))
    add_callback!(simulation, NormalizeTotalWater(model, Δt, nothing), IterationInterval(1))

    return simulation
end

    
