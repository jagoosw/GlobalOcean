# Keeping the cyclic forcing and climatologies in phase with the calendar, and with each other, over multi-cycle runs

using Oceananigans.Units: days
using NumericalEarth.DataWrangling.JRA55: MultiYearJRA55, RepeatYearJRA55

seconds_to_period(t) = Millisecond(round(Int, 1000t))
period_to_seconds(p) = Dates.value(Millisecond(p)) / 1000

"""
$(TYPEDSIGNATURES)

The period (seconds) over which `forced_ocean_simulation` cycles the JRA55 `dataset`: the calendar span from
`start_date` to `end_date` for `MultiYearJRA55` (21915 days for 1958--2018), one 365-day year for `RepeatYearJRA55`.

Left to infer it, a multi-year series cycles over its nodes plus one interval, and its nodes run to the first on or
after `end_date`: from 1958 to 2018 that is 21915 days + 3 hours for the 3-hourly variables and 21916 days for the
daily rivers and icebergs, so the rivers slip 0.875 days a cycle against the atmosphere and both slip against the
calendar. With this period the node past `end_date` is only ever the far end of the last interval before the wrap.
"""
forcing_period(::MultiYearJRA55, start_date, end_date) = period_to_seconds(end_date - start_date)
forcing_period(::RepeatYearJRA55, start_date, end_date) = 365days

"""
$(TYPEDSIGNATURES)

The period (seconds) to cycle an annual climatology with in a run whose forcing cycles every `forcing_period`
seconds: the mean length of the years in the cycle (365.25 days for 1958--2018, 365 days for repeat-year forcing),
so it repeats a whole number of times per forcing cycle and has the same phase in every cycle.

A 365-day climatology cannot follow leap days under `Cyclical`; at 365.25 days it stays within 0.75 days of the
calendar. By itself it would cycle every 365 days (366 for a leap-year one, e.g. SeaWiFS 2000), running 15 days
ahead of the calendar (45 days behind) by the end of 1958--2018 and starting each later cycle further out.
"""
climatology_period(forcing_period) = forcing_period / max(1, round(Int, forcing_period / 365.2425days))

"""
$(TYPEDSIGNATURES)

The forcing date at model time `t` (seconds since `start_date`) in a run cycling its forcing every `period` seconds.
"""
forcing_date(t, start_date, period) = start_date + seconds_to_period(mod(t, period))
