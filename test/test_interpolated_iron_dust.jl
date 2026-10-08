# InterpolatedIronDust: the surface dust is the time interpolation of a 2D FieldTimeSeries, and the
# forcing matches OceanBioME's IronDustDeposition of that dust.

using Oceananigans.OutputReaders: Cyclical, Linear
using Oceananigans.Units: Time
using Oceananigans.Forcings: DiscreteForcing
using Adapt: adapt

@testset "InterpolatedIronDust" begin
    grid = RectilinearGrid(size = (3, 2, 4), extent = (3, 2, 400))
    times = [0.0, 10.0, 20.0]

    series = FieldTimeSeries{Center, Center, Nothing}(grid, times; time_indexing = Cyclical(30.0))
    for n in 1:3
        # spatially varying, so the kernel's i, j indexing is checked too
        set!(series[n], (x, y) -> n * (1 + x + 10y))
    end
    pattern = [1 + x + 10y for x in 0.5:1:2.5, y in 0.5:1:1.5]

    dust = GO.InterpolatedIronDust(series; hard_fraction = 0.5, dissolution_length = 100.0)
    surface = dust.deposition.dust_deposition

    @test dust.deposition isa IronDustDeposition
    @test dust.deposition.hard_fraction == 0.5
    @test dust.deposition.dissolution_length == 100
    @test surface isa Field
    @test Oceananigans.Fields.location(surface) == (Center, Center, Nothing)
    @test dust.cpu_times == times

    # initialised to t = 0
    @test interior(surface, :, :, 1) ≈ pattern

    for (t, weight) in ((5.0, 1.5), (10.0, 2.0), (12.5, 2.25), (20.0, 3.0),
                        (25.0, 2.0),  # between the last record and the cyclic wrap back to the first
                        (35.0, 1.5))  # one period on
        GO.update_surface_dust!(dust, t)
        @test interior(surface, :, :, 1) ≈ weight .* pattern
        @test interior(surface, :, :, 1) ≈ [series[i, j, 1, Time(t)] for i in 1:3, j in 1:2]
    end

    # the model's FieldTimeSeries refresh hook
    @test GO.update_field_time_series!(dust, Time(15.0)) === nothing
    @test interior(surface, :, :, 1) ≈ 2.5 .* pattern
    extracted = GO.extract_field_time_series(dust)
    @test any(x -> x === series, extracted)
    @test any(x -> x === dust, extracted)

    # the forcing is OceanBioME's IronDustDeposition evaluated on the interpolated surface dust
    reference = IronDustDeposition(series; hard_fraction = 0.5, dissolution_length = 100.0)
    clock = Clock(time = 15.0)
    for k in 1:4
        @test dust(2, 1, k, grid, clock, nothing) ≈ reference(2, 1, k, grid, clock, nothing)
    end
    @test dust(2, 1, 4, grid, clock, nothing) > dust(2, 1, 1, grid, clock, nothing) > 0 # dissolves with depth

    # on the device only the deposition is kept
    adapted = adapt(Array, dust)
    @test isnothing(adapted.series)
    @test isnothing(adapted.cpu_times)
    @test adapted.deposition isa IronDustDeposition

    @test summary(dust) == "InterpolatedIronDust"
    @test startswith(sprint(show, dust), "InterpolatedIronDust of ")

    # Linear (non-cyclic) series also work
    linear = FieldTimeSeries{Center, Center, Nothing}(grid, times; time_indexing = Linear())
    for n in 1:3
        set!(linear[n], n)
    end
    linear_dust = GO.InterpolatedIronDust(linear)
    GO.update_surface_dust!(linear_dust, 15.0)
    @test all(interior(linear_dust.deposition.dust_deposition) .≈ 2.5)
end

@testset "InterpolatedIronDust in a model" begin
    grid = RectilinearGrid(size = (2, 2, 4), extent = (2, 2, 400))
    series = FieldTimeSeries{Center, Center, Nothing}(grid, [0.0, 100.0]; time_indexing = Cyclical(200.0))
    set!(series[1], 1e-9)
    set!(series[2], 3e-9)

    dust = GO.InterpolatedIronDust(series; hard_fraction = 0.0)
    # passed directly, as forced_ocean_simulation does (it is not a `Function`, so not wrapped in a `Forcing`)
    model = HydrostaticFreeSurfaceModel(grid; tracers = :Fe, buoyancy = nothing, forcing = (; Fe = dust))

    # update_state! refreshes the surface dust through extract_field_time_series
    model.clock.time = 50.0
    Oceananigans.TimeSteppers.update_state!(model)
    @test all(interior(dust.deposition.dust_deposition) .≈ 2e-9)

    time_step!(model, 1.0)
    Fe = interior(model.tracers.Fe)
    @test all(Fe .>= 0)
    @test Fe[1, 1, 4] > Fe[1, 1, 1] # more iron near the surface
end
