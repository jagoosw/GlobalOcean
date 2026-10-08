# Grid-dispatched defaults (uses the stand-in grids from test_grids.jl)

using Oceananigans.Advection: WENO, weno_order, ExplicitTimeDiscretization
using Oceananigans.Biogeochemistry: required_biogeochemical_tracers

@testset "ORCA1 defaults" begin
    for g in (ORCA1_STANDIN, immersed(ORCA1_STANDIN))
        @test GO.default_Δt(g) == 90minutes
        @test GO.default_barotropic_substeps(g) == 300
        @test GO.default_κ_skew(g) == 800
        @test GO.default_κ_symmetric(g) == 800
        @test GO.default_river_spread_cells(g) == 8
        @test isnothing(GO.default_river_spread_radius(g))
        @test GO.default_momentum_advection_order(g) == 5
        @test GO.default_biharmonic_timescale(g) == 50days
    end
end

@testset "T-pivot (eORCA025 / eORCA12) defaults" begin
    for g in (QUARTER_STANDIN, TWELFTH_STANDIN, immersed(QUARTER_STANDIN))
        @test GO.default_barotropic_substeps(g) == 200
        @test isnothing(GO.default_biharmonic_timescale(g))
        @test isnothing(GO.default_κ_skew(g))
        @test isnothing(GO.default_κ_symmetric(g))
        @test isnothing(GO.default_river_spread_cells(g))
        @test GO.default_river_spread_radius(g) == 1.2
        @test isnothing(GO.default_momentum_advection_order(g))
    end
    @test GO.default_Δt(QUARTER_STANDIN) == 20minutes
    @test GO.default_Δt(immersed(QUARTER_STANDIN)) == 20minutes
    @test GO.default_Δt(TWELFTH_STANDIN) == 6minutes
    @test GO.default_Δt(immersed(TWELFTH_STANDIN)) == 6minutes
    @test GO.default_Δt(TPIVOT_OTHER) == 20minutes
end

@testset "fallback defaults" begin
    for g in (DEFAULT_TRIPOLAR, LATLON_GRID, immersed(DEFAULT_TRIPOLAR))
        @test GO.default_Δt(g) == 30minutes
        @test GO.default_barotropic_substeps(g) == 100
        @test GO.default_biharmonic_timescale(g) == 50days
        @test GO.default_river_spread_radius(g) == 1.2
        @test isnothing(GO.default_river_spread_cells(g))
        @test isnothing(GO.default_κ_skew(g))
        @test isnothing(GO.default_κ_symmetric(g))
        @test isnothing(GO.default_momentum_advection_order(g))
    end
end

@testset "default_maximum_search_radius" begin
    # max(5, ceil(3 / mean(360/Nx, 180/Ny)))
    @test GO.default_maximum_search_radius(ORCA1_STANDIN) == 5
    @test GO.default_maximum_search_radius(RectilinearGrid(size = (360, 180, 1), extent = (1, 1, 1))) == 5
    @test GO.default_maximum_search_radius(RectilinearGrid(size = (1440, 720, 1), extent = (1, 1, 1))) == 12
    @test GO.default_maximum_search_radius(QUARTER_STANDIN) == 5 # only 10 rows: coarse in y
    r = GO.default_maximum_search_radius(RectilinearGrid(size = (4320, 3240, 1), extent = (1, 1, 1)))
    @test r == 44 # 3 / ((1/12 + 1/18) / 2) = 43.2
    @test r isa Int
end

@testset "tracer_advection_schemes" begin
    td = ExplicitTimeDiscretization()

    schemes = GO.tracer_advection_schemes(nothing, td)
    @test keys(schemes) == (:T, :S)
    @test all(s -> s isa WENO && weno_order(s) == 7, values(schemes))
    @test all(s -> s.time_discretization === td, values(schemes))

    grid = RectilinearGrid(size = (2, 2, 2), extent = (1, 1, 1))
    for bgc in (MITgcmDIC(grid), LOBSTER(grid), NPZD(grid))
        bgc_tracers = filter(n -> n ∉ (:T, :S), required_biogeochemical_tracers(bgc))
        schemes = GO.tracer_advection_schemes(bgc, td)

        @test Set(keys(schemes)) == Set((:T, :S, bgc_tracers...))
        @test weno_order(schemes.T) == 7
        @test weno_order(schemes.S) == 7
        @test all(n -> schemes[n] isa WENO && weno_order(schemes[n]) == 5, bgc_tracers)
        @test all(s -> s.time_discretization === td, values(schemes))
    end

    # NPZD carries its own :T; it must keep the 7th order temperature scheme
    @test weno_order(GO.tracer_advection_schemes(NPZD(grid), td).T) == 7

    # the time discretization is passed through, whatever it is
    avid = Oceananigans.Advection.AdaptiveVerticallyImplicitDiscretization(cfl = 0.5)
    schemes = GO.tracer_advection_schemes(MITgcmDIC(grid), avid)
    @test all(s -> s.time_discretization === avid, values(schemes))
end
