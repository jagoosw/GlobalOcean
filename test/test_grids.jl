# Grid-kind dispatch using small stand-in TripolarGrids (the real ORCA builders need meshes: opt-in only)

using Oceananigans.Grids: RightFaceFolded, RightCenterFolded
using Oceananigans.BoundaryConditions: FPivot, TPivot

# Shared with test_defaults.jl
const ORCA1_STANDIN    = TripolarGrid(size = (20, 20, 2), z = (-100, 0), fold_topology = RightFaceFolded)
const QUARTER_STANDIN  = TripolarGrid(size = (1440, 10, 1), z = (-100, 0), pivot = TPivot)
const TWELFTH_STANDIN  = TripolarGrid(size = (4320, 10, 1), z = (-100, 0), pivot = TPivot)
const TPIVOT_OTHER     = TripolarGrid(size = (40, 10, 1), z = (-100, 0), pivot = TPivot) # T pivot but neither size
const DEFAULT_TRIPOLAR = TripolarGrid(size = (20, 20, 2), z = (-100, 0))
const LATLON_GRID      = LatitudeLongitudeGrid(size = (8, 4, 2), longitude = (0, 360), latitude = (-60, 60), z = (-100, 0))

immersed(g) = ImmersedBoundaryGrid(g, GridFittedBottom((x, y) -> -50))

@testset "ORCA1GRID" begin
    @test ORCA1_STANDIN isa GO.ORCA1GRID
    @test immersed(ORCA1_STANDIN) isa GO.ORCA1GRID
    @test !(ORCA1_STANDIN isa GO.ORCATPivotGRID)
    @test !(DEFAULT_TRIPOLAR isa GO.ORCA1GRID)
    @test !(immersed(DEFAULT_TRIPOLAR) isa GO.ORCA1GRID)
    @test !(QUARTER_STANDIN isa GO.ORCA1GRID)
    @test !(LATLON_GRID isa GO.ORCA1GRID)
end

@testset "ORCATPivotGRID" begin
    for g in (QUARTER_STANDIN, TWELFTH_STANDIN, TPIVOT_OTHER)
        @test g isa GO.ORCATPivotGRID
        @test immersed(g) isa GO.ORCATPivotGRID
    end
    @test !(DEFAULT_TRIPOLAR isa GO.ORCATPivotGRID)
    @test !(LATLON_GRID isa GO.ORCATPivotGRID)
end

@testset "global_Nx / is_orca_quarter / is_orca_twelfth" begin
    @test GO.global_Nx(QUARTER_STANDIN) == 1440
    @test GO.global_Nx(immersed(TWELFTH_STANDIN)) == 4320
    @test GO.global_Nx(LATLON_GRID) == 8

    @test GO.is_orca_quarter(QUARTER_STANDIN)
    @test GO.is_orca_quarter(immersed(QUARTER_STANDIN))
    @test !GO.is_orca_twelfth(QUARTER_STANDIN)

    @test GO.is_orca_twelfth(TWELFTH_STANDIN)
    @test GO.is_orca_twelfth(immersed(TWELFTH_STANDIN))
    @test !GO.is_orca_quarter(TWELFTH_STANDIN)

    for g in (TPIVOT_OTHER, ORCA1_STANDIN, DEFAULT_TRIPOLAR, LATLON_GRID)
        @test !GO.is_orca_quarter(g)
        @test !GO.is_orca_twelfth(g)
    end

    # a 1440-wide grid that is not T-pivot tripolar is not eORCA025
    @test !GO.is_orca_quarter(TripolarGrid(size = (1440, 10, 1), z = (-100, 0)))
end

@testset "build_sea_ice_grid" begin
    @test GO.build_sea_ice_grid(LATLON_GRID, nothing, GridFittedBottom) === LATLON_GRID

    underlying = LatitudeLongitudeGrid(size = (4, 8, 2), longitude = (0, 40), latitude = (-80, 80), z = (-100, 0))
    ocean_grid = ImmersedBoundaryGrid(underlying, GridFittedBottom(-50.0))

    @test GO.build_sea_ice_grid(ocean_grid, nothing, GridFittedBottom) === ocean_grid

    sea_ice_grid = GO.build_sea_ice_grid(ocean_grid, (-50, 35), GridFittedBottom)

    let
        φ = Oceananigans.Grids.φnodes(underlying, Center())   # -70:20:70
        # masked columns are raised to land; `GridFittedBottom` caps them at the surface, z = 0
        expected = [(φ[j] > -50) & (φ[j] < 35) ? 0.0 : -50.0 for j in 1:8]
        bottom = sea_ice_grid.immersed_boundary.bottom_height
        @test sea_ice_grid isa ImmersedBoundaryGrid
        @test sea_ice_grid.underlying_grid === underlying
        @test all(bottom[i, j, 1] == expected[j] for i in 1:4, j in 1:8)
        # the ocean grid's bathymetry is not modified
        @test all(ocean_grid.immersed_boundary.bottom_height[i, j, 1] == -50 for i in 1:4, j in 1:8)
    end
end
