# preset grids, but any other grid can be dropped in
using KernelAbstractions: @kernel, @index
using OMIPSimulations: omip_vertical_discretization
using Oceananigans.Architectures: architecture
using Oceananigans.Grids: OrthogonalSphericalShellGrid, RightFaceFolded, RightCenterFolded
using Oceananigans.ImmersedBoundaries: ImmersedBoundaryGrid
using Oceananigans.OrthogonalSphericalShellGrids: Tripolar
using Oceananigans.BoundaryConditions: FPivot, TPivot, fill_halo_regions!
using Oceananigans.DistributedComputations: Distributed, global_size

# eORCA1 is the only ORCA mesh folded about an F-point pivot (eORCA025/eORCA12 pivot on T points and
# `TripolarGrid` defaults to a U pivot), so the fold parameters of its `Tripolar` mapping identify it.
# A `TripolarGrid` built with `fold_topology = RightFaceFolded` would also match.
const ORCA1Mapping        = Tripolar{<:Any, <:Any, <:Any, RightFaceFolded, FPivot}
const ORCA1UnderlyingGrid = OrthogonalSphericalShellGrid{<:Any, <:Any, <:Any, <:Any, <:Any, <:ORCA1Mapping}
const ORCA1GRID           = Union{ORCA1UnderlyingGrid, ImmersedBoundaryGrid{<:Any, <:Any, <:Any, <:Any, <:ORCA1UnderlyingGrid}}

# eORCA025 and eORCA12 both fold about a T-point pivot, so they share a type and only their size
# (1440 and 4320 distinct columns) tells them apart.
const ORCATPivotMapping        = Tripolar{<:Any, <:Any, <:Any, RightCenterFolded, TPivot}
const ORCATPivotUnderlyingGrid = OrthogonalSphericalShellGrid{<:Any, <:Any, <:Any, <:Any, <:Any, <:ORCATPivotMapping}
const ORCATPivotGRID           = Union{ORCATPivotUnderlyingGrid, ImmersedBoundaryGrid{<:Any, <:Any, <:Any, <:Any, <:ORCATPivotUnderlyingGrid}}

# On a distributed grid `size` is the local size, so recover the global one
global_Nx(grid) = global_Nx(architecture(grid), grid)
global_Nx(arch, grid) = size(grid)[1]
global_Nx(arch::Distributed, grid) = global_size(arch, size(grid))[1]

is_orca_quarter(grid) = false
is_orca_quarter(grid::ORCATPivotGRID) = global_Nx(grid) == 1440

is_orca_twelfth(grid) = false
is_orca_twelfth(grid::ORCATPivotGRID) = global_Nx(grid) == 4320

function ORCA1(arch; Nz = 70, Δz_top = 1.5, depth = 5500, Δzmax = nothing,
                     immersed_bottom = GridFittedBottom, minimum_depth = 0)


    z_faces = omip_vertical_discretization(Nz, depth; surface_grid_size = Δz_top,
                                                       maximum_grid_size = Δzmax)

    grid = ORCAGrid(arch;
                    dataset = ORCAOne(),
                    Nz,
                    z = z_faces,
                    halo = (8, 8, 8),
                    with_bathymetry = true,
                    immersed_bottom,
                    major_basins = 1,
                    minimum_depth,
                    active_cells_map = true)

    return grid
end

function ORCA025(arch; Nz = 100, Δz_top = 1.5, depth = 5500, Δzmax = nothing,
                     immersed_bottom = GridFittedBottom, minimum_depth = 20)

    z_faces = omip_vertical_discretization(Nz, depth; surface_grid_size = Δz_top,
                                                       maximum_grid_size = Δzmax)

    grid = ORCAGrid(arch;
                    dataset = ORCAQuarter(),
                    Nz,
                    z = z_faces,
                    halo = (8, 8, 8),
                    with_bathymetry = true,
                    immersed_bottom,
                    major_basins = 1,
                    minimum_depth,
                    active_cells_map = true)

    return grid
end

function ORCA12(arch; Nz = 100, Δz_top = 1.5, depth = 5500, Δzmax = nothing,
                     immersed_bottom = GridFittedBottom, minimum_depth = 20)

    z_faces = omip_vertical_discretization(Nz, depth; surface_grid_size = Δz_top,
                                                       maximum_grid_size = Δzmax)

    grid = ORCAGrid(arch;
                    dataset = ORCATwelfth(),
                    Nz,
                    z = z_faces,
                    halo = (8, 8, 8),
                    with_bathymetry = true,
                    immersed_bottom,
                    major_basins = 1,
                    minimum_depth,
                    active_cells_map = true)

    return grid
end

build_sea_ice_grid(grid, ::Nothing, immersed_bottom) = grid

@kernel function _immerse_latitude_band!(bottom_height, grid, south, north)
    i, j = @index(Global, NTuple)
    φ = φnode(i, j, 1, grid, Center(), Center(), Center())
    @inbounds z = bottom_height[i, j, 1]
    @inbounds bottom_height[i, j, 1] = ifelse((φ > south) & (φ < north), oftype(z, 100), z)
end

function build_sea_ice_grid(grid, latitudes::Tuple, immersed_bottom)
    south, north = latitudes

    arch       = architecture(grid)
    underlying = grid.underlying_grid

    bottom = Field{Center, Center, Nothing}(underlying)
    parent(bottom) .= parent(bottom_height_field(grid))

    FT = eltype(grid)
    launch!(arch, underlying, :xy, _immerse_latitude_band!, bottom, underlying, convert(FT, south), convert(FT, north))
    fill_halo_regions!(bottom)

    return ImmersedBoundaryGrid(underlying, GridFittedBottom(bottom); active_cells_map = true)
end