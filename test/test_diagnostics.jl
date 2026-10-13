# add_output_writer!: synchronous and asynchronous writers on a small model

using JLD2: jldopen
using OMIPSimulations: AsyncJLD2Writer

function output_writer_test_simulation(dir)
    grid = RectilinearGrid(size = (2, 2, 2), extent = (1, 1, 1))
    model = HydrostaticFreeSurfaceModel(grid; tracers = :c, buoyancy = nothing)
    set!(model, c = 1 + 1e-9) # resolvable in Float64 but not Float32
    simulation = Simulation(model; Δt = 1, stop_iteration = 4, verbose = false)
    writer(name) = JLD2Writer(model, (; ci = Integral(model.tracers.c)); indices = (1, 1, 1), array_type = Array{Float64},
                              schedule = IterationInterval(2), dir, filename = name, overwrite_files = true)
    return simulation, writer
end

@testset "add_output_writer!" begin
    dir = mktempdir()
    simulation, writer = output_writer_test_simulation(dir)

    users = writer("users")
    simulation.output_writers[:users] = users

    GO.add_output_writer!(simulation, :sync, writer("sync"))
    @test simulation.output_writers[:sync] isa JLD2Writer
    @test !haskey(simulation.callbacks, :flush_async_output)

    GO.add_output_writer!(simulation, :async, writer("async"); async = true)
    @test simulation.output_writers[:async] isa AsyncJLD2Writer
    @test haskey(simulation.callbacks, :flush_async_output)
    @test simulation.output_writers[:users] === users # other writers are left alone

    try
        run!(simulation)
    finally
        flush_output!(simulation)
    end

    for name in ("users", "sync", "async")
        jldopen(joinpath(dir, name * ".jld2")) do file
            @test filter(!=("serialized"), keys(file["timeseries/ci"])) == ["0", "2", "4"]
            value = file["timeseries/ci/4"]
            @test eltype(value) == Float64
            @test value[1] ≈ 1 + 1e-9
            @test value[1] != 1
        end
    end
end
