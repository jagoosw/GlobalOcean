# BGCInitClimatology dataset hooks, unit conversions and the tracer-name mapping, using a tiny fake bgc_init.nc

using NumericalEarth.DataWrangling: DataWrangling, Metadata, Metadatum
using Oceananigans.Biogeochemistry: required_biogeochemical_tracers

const DW = DataWrangling
const BGC = GO.BGCInitClimatology()

@testset "BGC_INIT_TRACERS mapping" begin
    grid = RectilinearGrid(size = (2, 2, 2), extent = (1, 1, 1))

    # every tracer name OceanBioME uses, from models spanning the names in the mapping
    oceanbiome_tracers = Set{Symbol}()
    for bgc in (PISCES(; grid), MITgcmDIC(grid), LOBSTER(grid), ImplicitBiology(grid),
                NutrientsPlanktonDetritus(grid; detritus = CarbonNitrogenDissolvedParticulate(grid)))
        union!(oceanbiome_tracers, required_biogeochemical_tracers(bgc))
    end

    @test Set(keys(GO.BGC_INIT_TRACERS)) ⊆ oceanbiome_tracers
    @test all(v -> haskey(GO.BGC_INIT_VARIABLES, v), values(GO.BGC_INIT_TRACERS))

    # Unicode subscripts, as OceanBioME names them, never the ASCII spellings
    for name in (:NO₃, :NH₄, :PO₄, :O₂)
        @test haskey(GO.BGC_INIT_TRACERS, name)
    end
    for ascii in (:NO3, :NH4, :PO4, :O2)
        @test !haskey(GO.BGC_INIT_TRACERS, ascii)
    end

    @test GO.BGC_INIT_TRACERS[:NO₃] == :nitrate
    @test GO.BGC_INIT_TRACERS[:PO₄] == :phosphate
    @test GO.BGC_INIT_TRACERS[:O₂]  == :dissolved_oxygen
    @test GO.BGC_INIT_TRACERS[:Fe]  == :dissolved_iron
    @test GO.BGC_INIT_TRACERS[:DIC] == :dissolved_inorganic_carbon
    @test GO.BGC_INIT_TRACERS[:Alk] == :alkalinity

    # MITgcmDIC: every dissolved tracer can be initialised (only the particulate POP cannot)
    mitgcm_tracers = required_biogeochemical_tracers(MITgcmDIC(grid))
    @test Set(filter(t -> !haskey(GO.BGC_INIT_TRACERS, t), mitgcm_tracers)) == Set([:POP])
end

@testset "dataset hooks" begin
    @test DW.all_dates(BGC, :nitrate) == [DateTime(2001, m, 1) for m in 1:12]
    @test DW.all_dates(BGC, :soluble_iron_deposition) == [DateTime(2001, m, 1) for m in 1:12]
    @test DW.all_dates(BGC, :dust_deposition) == [DateTime(2001, m, 1) for m in (1, 4, 7, 10)]

    @test DW.dataset_location(BGC, :nitrate) == (Center, Center, Center)
    @test DW.dataset_location(BGC, :soluble_iron_deposition) == (Center, Center, Nothing)
    @test DW.dataset_location(BGC, :dust_deposition) == (Center, Center, Nothing)

    @test size(BGC, :nitrate) == (360, 180, 102)
    @test size(BGC, :dust_deposition) == (360, 180, 1)
    @test size(BGC, :soluble_iron_deposition) == (360, 180, 1)

    @test DW.longitude_interfaces(BGC) == (-180, 180)
    @test DW.latitude_interfaces(BGC) == (-90, 90)
    @test DW.reversed_vertical_axis(BGC)
    @test DW.available_variables(BGC) === GO.BGC_INIT_VARIABLES
    @test DW.metadata_filename(BGC, :nitrate, DateTime(2001, 1, 1), nothing) == "bgc_init.nc"
    @test DW.default_download_directory(BGC) == GO.bgc_dir[]

    dir = mktempdir()
    nitrate = Metadata(:nitrate; dataset = BGC, dir)
    dust = Metadata(:dust_deposition; dataset = BGC, dir)
    iron = Metadatum(:soluble_iron_deposition; dataset = BGC, date = DateTime(2001, 5, 1), dir)

    @test length(nitrate) == 12
    @test length(dust) == 4
    @test DW.dataset_variable_name(nitrate) == "NO3"
    @test DW.dataset_variable_name(iron) == "iron"
    @test DW.dataset_variable_name(dust) == "dust"
    @test DW.is_three_dimensional(nitrate)
    @test !DW.is_three_dimensional(iron)
    @test !DW.is_three_dimensional(dust)
    @test DW.metaprefix(nitrate) == "BGCInitMetadata"
    @test DW.metaprefix(iron) == "BGCInitMetadatum"
    @test isnothing(DW.default_inpainting(nitrate))
    @test DW.metadata_path(iron) == joinpath(dir, "bgc_init.nc")

    @test DW.conversion_units(iron) isa GO.NmolPerCm2sToNegMmolPerM2s
    @test isnothing(DW.conversion_units(nitrate))
    @test isnothing(DW.conversion_units(dust))

    # seasonal variables average over the quarter, the rest over the calendar month
    @test DW.averaging_window(Metadatum(:dust_deposition; dataset = BGC, date = DateTime(2001, 4, 1), dir)) ==
          (DateTime(2001, 4, 1), DateTime(2001, 7, 1))
    @test DW.averaging_window(Metadatum(:dust_deposition; dataset = BGC, date = DateTime(2001, 10, 1), dir)) ==
          (DateTime(2001, 10, 1), DateTime(2002, 1, 1))
    @test DW.averaging_window(Metadatum(:nitrate; dataset = BGC, date = DateTime(2001, 3, 1), dir)) ==
          (DateTime(2001, 3, 1), DateTime(2001, 4, 1))
end

@testset "unit conversions" begin
    # 1 nmol/cm²/s = 1e-2 mmol/m²/s, negative into the ocean
    @test DW.convert_units(1.0, GO.NmolPerCm2sToNegMmolPerM2s()) ≈ -0.01
    @test DW.convert_units(1.0f0, GO.NmolPerCm2sToNegMmolPerM2s()) isa Float32
    @test DW.convert_units(0.0, GO.NmolPerCm2sToNegMmolPerM2s()) == 0

    # 1 kg dust/m²/s × 3.5 % Fe / 55.845e-6 kg/mmol
    @test DW.convert_units(1.0, GO.KgDustToNegMmolFe()) ≈ -0.035 / 55.845e-6 rtol = 1e-6
    @test DW.convert_units(2.0f0, GO.KgDustToNegMmolFe()) isa Float32
    @test DW.convert_units(2.0f0, GO.KgDustToNegMmolFe()) ≈ -2 * 0.035 / 55.845e-6 rtol = 1e-5
end

@testset "z_interfaces and retrieve_data (fake bgc_init.nc)" begin
    dir = mktempdir()
    depth = [5.0, 15.0, 30.0]
    NCDataset(joinpath(dir, "bgc_init.nc"), "c") do ds
        defDim(ds, "longitude", 4); defDim(ds, "latitude", 3); defDim(ds, "depth", 3)
        defDim(ds, "time", 12); defDim(ds, "season", 4)
        defVar(ds, "depth", depth, ("depth",))
        no3 = zeros(4, 3, 3, 12)
        for n in 1:12, k in 1:3
            no3[:, :, k, n] .= 100n + k # depth index k counts down from the surface
        end
        defVar(ds, "NO3", no3, ("longitude", "latitude", "depth", "time"))
        defVar(ds, "iron", reshape(repeat(1.0:12.0, inner = 12), 4, 3, 12), ("longitude", "latitude", "time"))
        defVar(ds, "dust", reshape(repeat(10.0:10.0:40.0, inner = 12), 4, 3, 4), ("longitude", "latitude", "season"))
    end

    nitrate_march = Metadatum(:nitrate; dataset = BGC, date = DateTime(2001, 3, 1), dir)

    # faces midway between centres, a surface at 0 and the bottom extrapolated; bottom-up and negative
    z = DW.z_interfaces(nitrate_march)
    @test z == [-37.5, -22.5, -10.0, 0.0]
    @test issorted(z)

    data = DW.retrieve_data(nitrate_march)
    @test size(data) == (4, 3, 3)
    @test eltype(data) == Float32
    @test data[1, 1, :] == Float32[303, 302, 301] # month 3, reversed so k = 1 is the deepest
    @test all(data[:, :, 3] .== 301)

    iron = DW.retrieve_data(Metadatum(:soluble_iron_deposition; dataset = BGC, date = DateTime(2001, 5, 1), dir))
    @test size(iron) == (4, 3)
    @test all(iron .== 5)

    # seasonal: any month picks the quarter it falls in
    for (month, expected) in ((1, 10), (3, 10), (4, 20), (6, 20), (9, 30), (12, 40))
        dust = DW.retrieve_data(Metadatum(:dust_deposition; dataset = BGC, date = DateTime(2001, month, 1), dir))
        @test size(dust) == (4, 3)
        @test all(dust .== expected)
    end
end
