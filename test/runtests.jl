#=
GlobalOcean test suite.

Default run (CPU, offline, no large data):

    julia --project=. test/runtests.jl            # from the repo root
    julia --project=. -e 'using Pkg; Pkg.test()'

Opt-in tests that need the real data (bgc_init.nc, ORCA meshes, JRA55, WOA, ECCO, ...):

    GLOBALOCEAN_DATA_TESTS=true  julia --project=. test/runtests.jl   # real bgc_init.nc (local, no download)
    GLOBALOCEAN_ORCA_TESTS=true  julia --project=. test/runtests.jl   # ORCA1 grid (downloads the mesh if missing)
    GLOBALOCEAN_SMOKE_TESTS=true julia --project=. test/runtests.jl   # builds the full coupled model

See `test_data_dependent.jl` for the extra environment variables they read.
=#

using Test

const TEST_DIR = @__DIR__
const TEST_DATA_DIR = joinpath(TEST_DIR, "data")

# `GlobalOcean.__init__` calls `auto_config_directories!()`, which `mkpath`s `data/...` and
# `output/$USER` relative to the working directory, so load it from a scratch directory.
const ORIGINAL_DIR = pwd()
const SCRATCH_DIR = mktempdir()
cd(SCRATCH_DIR)

using GlobalOcean
using Oceananigans
using Oceananigans.Units
using OceanBioME
using NumericalEarth
using NCDatasets
using Dates

const GO = GlobalOcean

envflag(name) = lowercase(get(ENV, name, "false")) in ("true", "1", "yes")

const RUN_DATA_TESTS  = envflag("GLOBALOCEAN_DATA_TESTS")
const RUN_ORCA_TESTS  = envflag("GLOBALOCEAN_ORCA_TESTS")
const RUN_SMOKE_TESTS = envflag("GLOBALOCEAN_SMOKE_TESTS")

try
    @testset "GlobalOcean" begin
        @testset "data_management.jl"       include("test_data_management.jl")
        @testset "grids.jl"                 include("test_grids.jl")
        @testset "defaults.jl"              include("test_defaults.jl")
        @testset "unified_bgc.jl"           include("test_unified_bgc.jl")
        @testset "river_input.jl"           include("test_river_input.jl")
        @testset "interpolated_iron_dust.jl" include("test_interpolated_iron_dust.jl")
        @testset "biogeochemistry.jl"       include("test_biogeochemistry.jl")
        @testset "light_attenuation.jl"     include("test_light_attenuation.jl")
        @testset "mauna_loa.jl"             include("test_mauna_loa.jl")

        if RUN_DATA_TESTS || RUN_ORCA_TESTS || RUN_SMOKE_TESTS
            @testset "data-dependent (opt-in)" include("test_data_dependent.jl")
        else
            @info "Skipping data-dependent tests; set GLOBALOCEAN_DATA_TESTS, GLOBALOCEAN_ORCA_TESTS and/or GLOBALOCEAN_SMOKE_TESTS=true to run them."
        end
    end
finally
    cd(ORIGINAL_DIR)
end
