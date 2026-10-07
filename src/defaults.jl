using Oceananigans.Units: minutes, days

function default_maximum_search_radius(grid)
    Nx, Ny, _ = size(grid)
    return max(5, ceil(Int, 3 / ((360 / Nx + 180 / Ny) / 2)))
end

default_river_spread_radius(grid)        = 1.2
default_river_spread_radius(::ORCA1GRID) = nothing

default_river_spread_cells(grid)        = nothing
default_river_spread_cells(::ORCA1GRID) = 8

default_κ_skew(grid)        = nothing
default_κ_skew(::ORCA1GRID) = 800

default_κ_symmetric(grid)        = nothing
default_κ_symmetric(::ORCA1GRID) = 800

default_momentum_advection_order(grid)        = nothing
default_momentum_advection_order(::ORCA1GRID) = 5

default_biharmonic_timescale(grid)             = 50days
default_biharmonic_timescale(::ORCATPivotGRID) = nothing

default_barotropic_substeps(grid)             = 100
default_barotropic_substeps(::ORCA1GRID)      = 300
default_barotropic_substeps(::ORCATPivotGRID) = 200

default_Δt(grid)                 = 30minutes
default_Δt(::ORCA1GRID)          = 90minutes
default_Δt(grid::ORCATPivotGRID) = is_orca_twelfth(grid) ? 6minutes : 20minutes
