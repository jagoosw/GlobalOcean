# `OMIPSimulations.build_ocean` with every input that `launch.sh` leaves off removed: the NEMO/CESM/hybrid
# eddy coefficients, slope tapering, the boundary-value GM parameters, extra viscosities (biharmonic,
# divergence, Reynolds limit, viscous velocity, Laplacian, strait damping), `Cᵂu★`, the initial-condition
# blend, and the extra tracer forcings (bottom boundary layers, overflow/Labrador restoring, sill overflow,
# divergence damping). Defaults are `launch.sh`'s, not `omip_simulation`'s.
using OMIPSimulations: fold_safe_constant_coefficients, salinity_surface_restoring, omip_closure,
                       coriolis_scheme_value, boundary_scheme_value, split_momentum_advection,
                       build_biogeochemistry, omip_tracer_advection, omip_radiative_forcing,
                       barotropic_free_surface, woa_to_teos10!
using Oceananigans.TimeSteppers: AdaptiveVerticallyImplicitDiscretization, ExplicitTimeDiscretization

function build_ocean(grid;
                     κ_skew = default_κ_skew(grid),
                     κ_symmetric = default_κ_symmetric(grid),
                     Cᵇ = 0.01, Cᵘⁿᵇ = 0.0, Cᵉc = 0.112,
                     Cᶠ = 1.0, Cᶠ⁰ = 1e9, Cᶠᵟ = 0.75,
                     barotropic_substeps = default_barotropic_substeps(grid),
                     Δt = default_Δt(grid),
                     biharmonic_timescale = default_biharmonic_timescale(grid),
                     restoring_dir = GlobalOcean.restoring_dir[],
                     piston_velocity = 0.254, # m / day
                     chlorophyll = :seawifs,
                     momentum_advection_scheme = :weno,
                     coriolis_scheme = :enstrophy,
                     vertical_closure = :catke,
                     background_vertical_diffusivity = :henyey,
                     background_vertical_viscosity = 3e-5,
                     implicit_vertical_advection = true,
                     tracer_advection_order = 7,
                     biogeochemical_tracer_advection_order = 5,
                     boundary_scheme = :default,
                     tracer_boundary_scheme = boundary_scheme,
                     momentum_boundary_scheme = boundary_scheme,
                     implicit_bottom_drag = true,
                     skew_flux_formulation = :diffusive,
                     isopycnal_formulation = :triad,
                     additional_tracer_closure = (),
                     biogeochemistry = nothing,
                     bgc_dir = GlobalOcean.forcing_dir[])

    if !isnothing(κ_skew) && !isnothing(κ_symmetric)
        κ_skew, κ_symmetric = fold_safe_constant_coefficients(grid, κ_skew, κ_symmetric,
                                                              Val(isopycnal_formulation))
    end

    additional_surface_fluxes = if piston_velocity == 0
        NamedTuple()
    else
        salt_restoring = salinity_surface_restoring(grid, WOAMonthly(); restoring_dir, piston_velocity)
        (; S = salt_restoring)
    end

    closure = omip_closure(vertical_closure;
                           grid,
                           κ_skew, κ_symmetric, Cᵇ, Cᵘⁿᵇ, Cᶠ, Cᶠ⁰, Cᶠᵟ, Cᵉc,
                           biharmonic_timescale,
                           skew_flux_formulation,
                           isopycnal_formulation,
                           background_vertical_diffusivity,
                           background_vertical_viscosity)
    closure = (closure..., additional_tracer_closure...)
    coriolis = HydrostaticSphericalCoriolis(scheme = coriolis_scheme_value(coriolis_scheme))

    time_discretization = implicit_vertical_advection ?
        AdaptiveVerticallyImplicitDiscretization(cfl=0.5) : ExplicitTimeDiscretization()

    tracer_boundary_scheme   = boundary_scheme_value(tracer_boundary_scheme)
    momentum_boundary_scheme = boundary_scheme_value(momentum_boundary_scheme)

    momentum_advection = split_momentum_advection(momentum_advection_scheme,
                                                  default_momentum_advection_order(grid),
                                                  time_discretization, momentum_boundary_scheme)

    biogeochemistry, forcing, bgc_additional_surface_fluxes = build_biogeochemistry(Val(biogeochemistry), grid; dir = bgc_dir)

    tracer_advection = omip_tracer_advection(biogeochemistry, tracer_advection_order,
                                             biogeochemical_tracer_advection_order,
                                             time_discretization, tracer_boundary_scheme)

    additional_surface_fluxes = merge(additional_surface_fluxes, bgc_additional_surface_fluxes)

    ocean = ocean_simulation(grid;
                             Δt = 1minutes,
                             radiative_forcing = omip_radiative_forcing(grid, chlorophyll, restoring_dir),
                             momentum_advection,
                             tracer_advection,
                             coriolis,
                             implicit_bottom_drag,
                             timestepper = :SplitRungeKutta3,
                             materialize_buoyancy_gradients = true, # stored once per stage instead of recomputed in the triad/CATKE kernels
                             free_surface = barotropic_free_surface(grid, barotropic_substeps, Δt),
                             additional_surface_fluxes,
                             forcing,
                             closure,
                             biogeochemistry)

    # Load WOA Annual T (in-situ, °C) and S (Practical) onto the model grid,
    # convert to TEOS-10 Conservative T and Absolute Salinity in place, then
    # initialize the prognostic ocean state from the converted fields.
    T_init = CenterField(grid)
    S_init = CenterField(grid)
    set!(T_init, Metadatum(:temperature; dir=restoring_dir, dataset=WOAAnnual()))
    set!(S_init, Metadatum(:salinity;    dir=restoring_dir, dataset=WOAAnnual()))
    woa_to_teos10!(T_init, S_init)

    set!(ocean.model, T=T_init, S=S_init)

    return ocean
end
