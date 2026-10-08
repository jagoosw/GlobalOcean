#=
Opt-in tests that need real data. Enabled by environment variables:

  GLOBALOCEAN_DATA_TESTS=true    the real bgc_init.nc (from GLOBALOCEAN_BGC_DIR, default
                                 /Users/jago/Documents/OAEMIP/data); reads only, no downloads
  GLOBALOCEAN_ORCA_TESTS=true    the ORCA1 grid (downloads the eORCA1 mesh + bathymetry into the
                                 NumericalEarth cache if missing)
  GLOBALOCEAN_SMOKE_TESTS=true   builds the full coupled model with `forced_ocean_simulation` on ORCA1 (CPU):
                                 needs JRA55 (repeat year), WOA, SeaWiFS, ECCO and bgc_init.nc in the directories
                                 configured by `auto_config_directories!` (GLOBALOCEAN_DATA_ROOT, default "data"
                                 relative to the repo root)
=#

using NumericalEarth.DataWrangling: DataWrangling, Metadata, Metadatum

const REPO_DIR = dirname(TEST_DIR)

if RUN_DATA_TESTS
    @testset "BGCInitClimatology (real bgc_init.nc)" begin
        bgc_dir = get(ENV, "GLOBALOCEAN_BGC_DIR", "/Users/jago/Documents/OAEMIP/data")
        if !isfile(joinpath(bgc_dir, "bgc_init.nc"))
            @warn "No bgc_init.nc in $bgc_dir; skipping"
            @test_skip false
        else
            saved = GO.bgc_dir[]
            try
                GO.bgc_dir[] = bgc_dir
                dataset = GO.BGCInitClimatology()
                @test DataWrangling.default_download_directory(dataset) == bgc_dir

                nitrate = Metadatum(:nitrate; dataset, date = DateTime(2001, 1, 1))
                @test nitrate.dir == bgc_dir

                z = DataWrangling.z_interfaces(nitrate)
                @test length(z) == size(dataset, :nitrate)[3] + 1
                @test issorted(z)
                @test z[end] == 0
                @test z[1] < -5000

                data = DataWrangling.retrieve_data(nitrate)
                @test size(data) == size(dataset, :nitrate)

                iron = DataWrangling.retrieve_data(Metadatum(:soluble_iron_deposition; dataset, date = DateTime(2001, 6, 1)))
                @test size(iron) == size(dataset, :soluble_iron_deposition)[1:2]

                dust = DataWrangling.retrieve_data(Metadatum(:dust_deposition; dataset, date = DateTime(2001, 7, 1)))
                @test size(dust) == size(dataset, :dust_deposition)[1:2]

                # every mapped tracer's variable is in the file
                NCDataset(joinpath(bgc_dir, "bgc_init.nc")) do ds
                    for name in values(GO.BGC_INIT_TRACERS)
                        @test haskey(ds, GO.BGC_INIT_VARIABLES[name])
                    end
                end

                # interpolated onto a small model grid
                grid = LatitudeLongitudeGrid(size = (36, 18, 5), longitude = (0, 360), latitude = (-80, 80), z = (-1000, 0))
                series = GO.BGCInitSolubleIronDeposition(grid)
                @test length(series.times) == 12
                @test all(isfinite, interior(series))
                @test all(interior(series) .<= 0) # negative into the ocean
            finally
                GO.bgc_dir[] = saved
            end
        end
    end
end

if RUN_ORCA_TESTS
    @testset "ORCA1 grid" begin
        grid = ORCA1(CPU())
        @test grid isa GO.ORCA1GRID
        @test !(grid isa GO.ORCATPivotGRID)
        @test size(grid, 3) == 70
        @test GO.default_Δt(grid) == 90minutes
        @test GO.default_barotropic_substeps(grid) == 300
        @test !GO.is_orca_quarter(grid)
    end
end

if RUN_SMOKE_TESTS
    @testset "forced_ocean_simulation smoke test (ORCA1, CPU)" begin
        data_root = get(ENV, "GLOBALOCEAN_DATA_ROOT", joinpath(REPO_DIR, "data"))
        GO.auto_config_directories!("test"; user = get(ENV, "USER", "test"), data_root,
                                    output_root = mktempdir())

        grid = ORCA1(CPU())
        simulation = forced_ocean_simulation(grid; backend_size = 4, stop_time = 2 * GO.default_Δt(grid))
        @test simulation isa Simulation
        @test simulation.Δt == 90minutes

        time_step!(simulation)
        @test iteration(simulation) == 1
        @test all(isfinite, interior(simulation.model.ocean.model.tracers.T))
    end
end
