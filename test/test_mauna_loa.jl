# Mauna Loa CO₂, read from a copy of the CSV in test/data (no download)

using NumericalEarth.DataWrangling: DataWrangling, Metadata, Metadatum
using Oceananigans.OutputReaders: Cyclical
using Oceananigans.Units: Time

const MLO_DIR = TEST_DATA_DIR # contains mlo_spo_monthly_mean.csv

@testset "MaunaLoa dataset" begin
    dataset = GO.MaunaLoa()
    @test dataset.url == GO.MAUNA_LOA_URL
    @test GO.MaunaLoa(url = "x").url == "x"

    dates = DataWrangling.all_dates(dataset, :carbon_dioxide)
    @test first(dates) == DateTime(1958, 1, 15)
    @test last(dates) == DateTime(2024, 3, 15)
    @test length(dates) == 66 * 12 + 3

    @test DataWrangling.dataset_location(dataset, :carbon_dioxide) == (Nothing, Nothing, Nothing)
    @test DataWrangling.metadata_filename(dataset, :carbon_dioxide, nothing, nothing) == "mlo_spo_monthly_mean.csv"

    md = Metadata(:south_pole_carbon_dioxide; dataset, dir = MLO_DIR)
    @test DataWrangling.dataset_variable_name(md) == "SPO"
    @test DataWrangling.dataset_variable_name(Metadata(:mean_carbon_dioxide; dataset, dir = MLO_DIR)) == "Average"
    @test !DataWrangling.is_three_dimensional(md)
    @test DataWrangling.metadata_url(Metadata(:carbon_dioxide; dataset = GO.MaunaLoa(url = "https://x"), dir = MLO_DIR)) == "https://x"

    # already present: no download attempted
    @test GO.Downloads.download(md) == joinpath(MLO_DIR, "mlo_spo_monthly_mean.csv")

    # a missing file with a non-http URL is an ArgumentError rather than a download attempt
    @test_throws ArgumentError GO.Downloads.download(Metadata(:carbon_dioxide; dataset = GO.MaunaLoa(url = "none"), dir = mktempdir()))
end

@testset "read_mauna_loa" begin
    md = Metadata(:carbon_dioxide; dataset = GO.MaunaLoa(), dir = MLO_DIR)
    dates, values = GO.read_mauna_loa(md)

    @test length(dates) == length(values) == length(DataWrangling.all_dates(GO.MaunaLoa()))
    @test dates == collect(DataWrangling.all_dates(GO.MaunaLoa()))
    # Jan/Feb 1958 padded with March 1958
    @test dates[1:3] == [DateTime(1958, 1, 15), DateTime(1958, 2, 15), DateTime(1958, 3, 15)]
    @test values[1] == values[2] == values[3] == 314.44
    @test values[4] == 315.16
    @test values[end] == 423.65

    @test all(300 .< values .< 450)
    @test values[end] - values[1] > 100 # it went up

    _, spo = GO.read_mauna_loa(Metadata(:south_pole_carbon_dioxide; dataset = GO.MaunaLoa(), dir = MLO_DIR))
    @test spo[1] == spo[3] == 314.78
    @test spo != values

    @test GO.mauna_loa_co2(DateTime(1990, 3, 15); dir = MLO_DIR) == 353.79
    @test GO.mauna_loa_co2(DateTime(1958, 1, 15); dir = MLO_DIR) == 314.44
    @test_throws ArgumentError GO.mauna_loa_co2(DateTime(1990, 3, 1); dir = MLO_DIR) # not a 15th

    field = Field(Metadatum(:carbon_dioxide; dataset = GO.MaunaLoa(), date = DateTime(1990, 3, 15), dir = MLO_DIR))
    @test field[1, 1, 1] ≈ 353.79 # Float32 by default
end

@testset "MaunaLoaCO₂" begin
    # one repeat year, cycled every 365 days
    dates = DateTime(1990, 1, 15):Month(1):DateTime(1990, 12, 15)
    xCO₂ = MaunaLoaCO₂(; dates, start_date = DateTime(1990, 1, 1), period = 365days, dir = MLO_DIR)

    @test xCO₂ isa FieldTimeSeries
    @test Oceananigans.Fields.location(xCO₂) == (Nothing, Nothing, Nothing)
    @test length(xCO₂.times) == 12
    @test xCO₂.times isa AbstractRange
    @test step(xCO₂.times) ≈ 365days / 12
    @test first(xCO₂.times) ≈ 365days / 24 # half a step after 1 Jan
    @test xCO₂.time_indexing isa Cyclical
    @test xCO₂.time_indexing.period ≈ 365days
    @test eltype(xCO₂) == Float64

    values = interior(xCO₂, 1, 1, 1, :)
    @test all(350 .< values .< 360)
    @test values[3] == GO.mauna_loa_co2(DateTime(1990, 3, 15); dir = MLO_DIR)
    @test xCO₂[1, 1, 1, Time(xCO₂.times[3])] ≈ values[3]

    # cyclic: one period on is the same, and across the seam it interpolates Dec -> Jan
    t = xCO₂.times[5]
    @test xCO₂[1, 1, 1, Time(t + 365days)] ≈ xCO₂[1, 1, 1, Time(t)]
    seam = last(xCO₂.times) + step(xCO₂.times) / 2
    @test xCO₂[1, 1, 1, Time(seam)] ≈ (values[1] + values[end]) / 2

    # the whole record with the default mean-month spacing
    full = MaunaLoaCO₂(; dir = MLO_DIR)
    @test length(full.times) == length(DataWrangling.all_dates(GO.MaunaLoa()))
    @test step(full.times) ≈ GO.MEAN_MONTH_LENGTH
    @test full.time_indexing.period ≈ length(full.times) * GO.MEAN_MONTH_LENGTH
    @test first(full.times) ≈ GO.MEAN_MONTH_LENGTH / 2 - 14days # start_date defaults to the first date, 15 Jan 1958
    @test all(300 .< interior(full) .< 450)

    # start_date shifts model time zero
    shifted = MaunaLoaCO₂(; dates, start_date = DateTime(1989, 12, 1), period = 365days, dir = MLO_DIR)
    @test first(shifted.times) ≈ first(xCO₂.times) + 31days

    # Float32
    @test eltype(MaunaLoaCO₂(; dates, FT = Float32, dir = MLO_DIR)) == Float32

    # needs at least two samples to interpolate
    @test_throws ArgumentError MaunaLoaCO₂(; dates = DateTime(1990, 1, 15):Month(1):DateTime(1990, 1, 15), dir = MLO_DIR)
end
