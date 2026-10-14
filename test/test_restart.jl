# Choosing an OMIP spin-up checkpoint for a date, from fake checkpoints holding only the clock time

using Oceananigans.Units: days, hours, minutes
using NumericalEarth.DataWrangling.JRA55: MultiYearJRA55, RepeatYearJRA55

# the ORCA1 OMIP spin-up: 90 minute steps, a checkpoint every 360 days (5760 iterations), 1958--2018 cycles
const RESTART_DIR = mktempdir()

for iteration in 5760:5760:996480
    GO.jldopen(joinpath(RESTART_DIR, "orca_checkpoint_iteration$iteration.jld2"), "w") do file
        file["simulation/model/clock/time"] = iteration * 90minutes
    end
end

touch(joinpath(RESTART_DIR, "omip_checkpoint_iteration5760.jld2")) # a different prefix, ignored

checkpoint_path(iteration) = joinpath(RESTART_DIR, "orca_checkpoint_iteration$iteration.jld2")

@testset "checkpoint_times" begin
    paths, times = GO.checkpoint_times(RESTART_DIR, "orca_checkpoint")
    @test length(paths) == 173
    @test issorted(times)
    @test first(paths) == checkpoint_path(5760) # sorted by time, not by file name
    @test last(times) == 996480 * 90minutes
    @test_throws ArgumentError GO.checkpoint_times(RESTART_DIR, "no_such_prefix")
end

@testset "checkpoint_times from a Checkpointer" begin
    # the Checkpointer writes the clock as one dataset rather than a group
    dir = mktempdir()
    grid = RectilinearGrid(size = (2, 2, 2), extent = (1, 1, 1))
    model = HydrostaticFreeSurfaceModel(grid; tracers = :c, buoyancy = nothing)
    simulation = Simulation(model; Δt = 10, stop_iteration = 4, verbose = false)
    simulation.output_writers[:checkpointer] = Checkpointer(model; schedule = IterationInterval(2), dir, prefix = "real_checkpoint")
    run!(simulation)

    paths, times = GO.checkpoint_times(dir, "real_checkpoint")
    @test basename.(paths) == ["real_checkpoint_iteration$i.jld2" for i in (0, 2, 4)]
    @test times == [0, 20, 40]
end

@testset "forcing_cycle_length" begin
    # the last node (2018-01-01T00) is included, so the cycle is one 3-hourly interval longer than 1958--2018
    @test GO.forcing_cycle_length(MultiYearJRA55(), DateTime(1958, 1, 1), DateTime(2018, 1, 1)) == 21915days + 3hours
    @test GO.forcing_cycle_length(RepeatYearJRA55(), DateTime(1990, 1, 1), DateTime(1990, 12, 31, 23, 59, 59)) == 365days
end

@testset "restart_clock_time" begin
    @test GO.restart_clock_time(DateTime(1990, 1, 11), DateTime(1990, 1, 1)) == 10days
    @test GO.restart_clock_time(DateTime(1989, 12, 22), DateTime(1990, 1, 1)) == -10days
    @test GO.restart_clock_time(DateTime(1989, 10, 15), DateTime(1990, 1, 1); repeat_year = true) == 287days
    @test GO.restart_clock_time(DateTime(1989, 12, 22), DateTime(1990, 1, 1); repeat_year = true) == 355days
    # by calendar date, not day of year, in leap years
    @test GO.restart_clock_time(DateTime(1984, 12, 31, 6), DateTime(1990, 1, 1); repeat_year = true) == 364days + 6hours
    @test GO.restart_clock_time(DateTime(1984, 2, 29, 6), DateTime(1990, 1, 1); repeat_year = true) == 58days + 6hours
end

@testset "select_restart" begin
    paths, times = GO.checkpoint_times(RESTART_DIR, "orca_checkpoint")
    cycle_length = 21915days + 3hours

    # the last cycle present is the third (0-based 2), starting 2 × 21915.125 days in:
    # its checkpoints are 89.75 + 360n days after 1958-01-01
    path, date, cycle = GO.select_restart(paths, times, DateTime(1990, 1, 1); start_date = DateTime(1958, 1, 1), cycle_length)
    @test cycle == 2
    @test date == DateTime(1989, 10, 14, 18)
    @test path == checkpoint_path(887040)

    # restarting there puts the atmosphere where the checkpointed run had it
    t = GO.restart_clock_time(date, DateTime(1958, 1, 1))
    @test t == 887040 * 90minutes - 2cycle_length

    # a run starting in 1990 can't start before its start date, so takes the next one
    path, date, _ = GO.select_restart(paths, times, DateTime(1990, 1, 1); start_date = DateTime(1990, 1, 1), cycle_length)
    @test date == DateTime(1990, 10, 9, 18)
    @test path == checkpoint_path(892800)

    # but a repeat-year run can
    path, date, _ = GO.select_restart(paths, times, DateTime(1990, 1, 1); start_date = DateTime(1990, 1, 1), cycle_length, repeat_year = true)
    @test path == checkpoint_path(887040)

    # an earlier cycle: 44.875 + 360n days after 1958-01-01
    path, date, cycle = GO.select_restart(paths, times, DateTime(1990, 1, 1); start_date = DateTime(1958, 1, 1), cycle_length, cycle = 1)
    @test cycle == 1
    @test date == DateTime(1989, 8, 30, 21)
    @test path == checkpoint_path(535680)

    @test_throws ArgumentError GO.select_restart(paths, times, DateTime(1990, 1, 1); start_date = DateTime(2020, 1, 1), cycle_length)
end
