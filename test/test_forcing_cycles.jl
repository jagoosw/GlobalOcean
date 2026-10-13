# Phase-locking the cyclic forcing and climatologies to the calendar over multi-cycle runs, from metadata only (no data)

using NumericalEarth.DataWrangling: Metadata, native_times, window_span, all_dates
using NumericalEarth.DataWrangling.JRA55: MultiYearJRA55, RepeatYearJRA55
using NumericalEarth.DataWrangling.WOA: WOAMonthly
using NumericalEarth.DataWrangling.SeaWiFS: SeaWiFSMonthly
using Oceananigans.OutputReaders: Cyclical, interpolating_time_indices
using Oceananigans.Units: days, hours

const START = DateTime(1958, 1, 1)
const END   = DateTime(2018, 1, 1)
const CYCLE = 21915days

quiet(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger()) # "start_date before the first date" warnings

jra55_metadata(name) = quiet(() -> Metadata(name; dataset = MultiYearJRA55(), start_date = START, end_date = END))

# the period `FieldTimeSeries(metadata, grid)` infers when not given one
inferred_period(md, times = native_times(md)) = something(window_span(md), times[end] - times[1] + (times[end] - times[end-1]))

# the date of the data a series with nodes `times` (seconds since its first stamp) is read at, at model time `t`
function data_date(md, times, period, t)
    ñ, n₁, n₂ = interpolating_time_indices(Cyclical(period), times, t)
    @assert n₂ == n₁ + 1 || n₁ == n₂ # never cycled: the node past `end_date` closes the last interval
    return first(md).dates + GO.seconds_to_period(times[n₁] + ñ * (times[n₂] - times[n₁]))
end

# the same from the `mod` `Cyclical` takes, for periods under which the last interval is cycled
cycled_data_date(md, times, period, t) = first(md).dates + GO.seconds_to_period(mod(t - times[1], period) + times[1])

same_indices((ñ, n₁, n₂), (ñ′, n₁′, n₂′)) = n₁ == n₁′ && n₂ == n₂′ && abs(ñ - ñ′) < 1e-6

# a climatology's time of year at model time `t`, less that of the forcing's date, wrapped into [-period/2, period/2)
function calendar_error(times, period, t)
    date = GO.forcing_date(t, START, CYCLE)
    calendar_time = GO.period_to_seconds(date - DateTime(year(date)))
    climatology_time = mod(t - times[1], period) + times[1]
    return mod(climatology_time - calendar_time + period / 2, period) - period / 2
end

# every day of 1958--2017 at a time that is not a node, in each of five cycles
sample_days = [n * 1days + 5hours + 17 for n in 0:21914]

@testset "forcing_period and climatology_period" begin
    @test GO.forcing_period(MultiYearJRA55(), START, END) == CYCLE
    @test GO.forcing_period(MultiYearJRA55(), DateTime(1990, 1, 1), DateTime(1992, 1, 1)) == 730days
    @test GO.forcing_period(RepeatYearJRA55(), DateTime(1990, 1, 1), END) == 365days

    @test GO.climatology_period(CYCLE) == 365.25days # 60 years with 15 leap days
    @test GO.climatology_period(365days) == 365days
    @test GO.climatology_period(730days) == 365days
    @test GO.climatology_period(10days) == 10days # less than a year: one per cycle

    @test GO.forcing_date(CYCLE + 10days, START, CYCLE) == DateTime(1958, 1, 11)
    @test GO.forcing_date(4CYCLE + 10days + 3hours, START, CYCLE) == DateTime(1958, 1, 11, 3)
    @test GO.forcing_date(400days, START, Inf) == DateTime(1959, 2, 5) # never cycles
end

@testset "periods inferred without forcing_period" begin
    # what each series cycles over left to itself (days): none is the 21915 day calendar cycle
    @test inferred_period(jra55_metadata(:temperature)) / days == 21915.125
    @test inferred_period(jra55_metadata(:downwelling_shortwave_radiation)) / days == 21915.125
    @test inferred_period(jra55_metadata(:rain_freshwater_flux)) / days == 21915.125
    @test inferred_period(jra55_metadata(:river_freshwater_flux)) / days == 21916

    woa = Metadata(:salinity; dataset = WOAMonthly())
    seawifs = Metadata(:chlorophyll; dataset = SeaWiFSMonthly(), dates = (DateTime(2000, 1, 1), DateTime(2000, 12, 1)))
    dust = Metadata(:dust_deposition; dataset = GO.BGCInitClimatology(), dates = all_dates(GO.BGCInitClimatology(), :dust_deposition))

    @test inferred_period(woa) / days == 365
    @test inferred_period(seawifs) / days == 366 # 2000 is a leap year
    @test inferred_period(dust) / days == 365

    # the climatologies' time zero is 1 January (their first node is the middle of their first window)
    @test native_times(woa)[1] / days == 15.5
    @test native_times(seawifs)[1] / days == 15.5
    @test native_times(dust)[1] / days == 45

    @test RepeatYearJRA55() isa RepeatYearJRA55 # (repeat-year series all infer 365 days; their files are not needed here)
end

@testset "JRA55 phase-locked over cycles" begin
    names = (:temperature, :downwelling_shortwave_radiation, :rain_freshwater_flux, :river_freshwater_flux)
    metadata = map(jra55_metadata, names)
    times = map(native_times, metadata)

    lags = Dict(name => Millisecond[] for name in names)
    inferred_river_lag = Millisecond[]

    for cycle in 0:4, s in sample_days[1:97:end]
        t = cycle * CYCLE + s
        dates = map((md, ts) -> data_date(md, ts, CYCLE, t), metadata, times)

        for (name, date) in zip(names, dates)
            push!(lags[name], date - (START + GO.seconds_to_period(s)))
        end
    end

    # mid-cycle, as before, with each series cycling over its own inferred period
    for cycle in 0:4, s in sample_days[10:97:end-10]
        river, atmosphere = (cycled_data_date(metadata[n], times[n], inferred_period(metadata[n], times[n]), cycle * CYCLE + s) for n in (4, 1))
        push!(inferred_river_lag, river - atmosphere)
    end

    within_a_second(lag, expected) = all(abs.(Dates.value.(lag .- GO.seconds_to_period(expected))) .≤ 1000)

    # the 3-hourly state is read at its date in every cycle
    @test within_a_second(lags[:temperature], 0)

    # series stamped at the middle of their averaging windows are read a constant half window early, as
    # `native_times` takes time zero at their first stamp rather than at `start_date` (rain and snow are
    # interpolated on the velocities' time axis anyway)
    @test within_a_second(lags[:downwelling_shortwave_radiation], 90minutes)
    @test within_a_second(lags[:rain_freshwater_flux], 90minutes)
    @test within_a_second(lags[:river_freshwater_flux], 12hours)

    # left to its own 21916 day period the rivers slip 0.875 days a cycle against the atmosphere
    @test abs(GO.period_to_seconds(maximum(inferred_river_lag) - minimum(inferred_river_lag)) - 4 * 0.875days) ≤ 1
end

@testset "climatologies phase-locked to the calendar" begin
    climatologies = (woa = Metadata(:salinity; dataset = WOAMonthly()),
                     seawifs = Metadata(:chlorophyll; dataset = SeaWiFSMonthly(), dates = (DateTime(2000, 1, 1), DateTime(2000, 12, 1))),
                     dust = Metadata(:dust_deposition; dataset = GO.BGCInitClimatology(), dates = all_dates(GO.BGCInitClimatology(), :dust_deposition)))

    period = GO.climatology_period(CYCLE)

    for md in climatologies
        times = native_times(md)

        # within 0.75 days of the calendar on every day of 1958--2017, the same in every cycle
        errors = [calendar_error(times, period, cycle * CYCLE + s) for s in sample_days, cycle in 0:4]
        @test maximum(abs, errors) ≤ 0.75days
        @test maximum(abs, errors .- errors[:, 1]) < 1 # second

        # and the interpolation is the same in every cycle
        indices(t) = interpolating_time_indices(Cyclical(period), times, t)
        @test all(s -> all(cycle -> same_indices(indices(s), indices(cycle * CYCLE + s)), 1:4), sample_days[1:13:end])

        # left to their own periods they drift through the season
        drift = [calendar_error(times, inferred_period(md), cycle * CYCLE + s) for s in sample_days, cycle in 0:4]
        @test maximum(abs, drift) > 15days
    end

    # monthly means are read at their own month on the 15th of every month of every cycle
    times = native_times(climatologies.woa)
    nearest_month(t) = ((ñ, n₁, n₂) = interpolating_time_indices(Cyclical(period), times, t); ñ < 1/2 ? n₁ : n₂)
    @test all(month(date) == nearest_month(cycle * CYCLE + GO.period_to_seconds(date - START))
              for cycle in 0:4, date in DateTime(1958, 1, 15, 12):Month(1):DateTime(2017, 12, 15, 12))
end
