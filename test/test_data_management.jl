# Pure filesystem logic: directory configuration and JRA55 staging, on temp dirs with fake `.nc` files.

# Real JRA55-do file names: the year is matched as "_gr_<year>"
jra55_name(var, year) = "$(var)_input4MIPs_atmosphericState_OMIP_MRI-JRA55-do-1-5-0_gr_$(year)01010130-$(year)12312230.nc"
ryf_name(var) = "RYF.$(var).1990_1991.nc"

function write_fake(path, nbytes)
    open(path, "w") do io
        write(io, rand(UInt8, nbytes))
    end
    return path
end

# Run `f` with the directory `Ref`s and the ENV variables `auto_config_directories!` touches restored afterwards
function with_restored_config(f)
    refs = (GO.forcing_dir, GO.restoring_dir, GO.staging_dir, GO.bgc_dir, GO.output_dir)
    saved_refs = map(r -> r[], refs)
    env_names = ("DATADEPS_ALWAYS_ACCEPT", "NUMERICALEARTH_DATA_DIRECTORY", "DATADEPS_LOAD_PATH")
    saved_env = map(n -> get(ENV, n, nothing), env_names)
    try
        f()
    finally
        foreach((r, v) -> r[] = v, refs, saved_refs)
        foreach(env_names, saved_env) do n, v
            isnothing(v) ? delete!(ENV, n) : (ENV[n] = v)
        end
    end
end

@testset "auto_config_directories!" begin
    with_restored_config() do
        data_root = mktempdir()
        output_root = mktempdir()

        @test isnothing(GO.auto_config_directories!("run1"; user = "tester", data_root, output_root,
                                                     datadeps_always_accept = false))

        @test GO.forcing_dir[]   == joinpath(data_root, "forcing")
        @test GO.restoring_dir[] == joinpath(data_root, "climatology")
        @test GO.bgc_dir[]       == data_root
        @test GO.output_dir[]    == joinpath(output_root, "tester", "run1")

        @test ENV["DATADEPS_ALWAYS_ACCEPT"] == "false"
        @test ENV["NUMERICALEARTH_DATA_DIRECTORY"] == joinpath(data_root, "caches")
        @test ENV["DATADEPS_LOAD_PATH"] == joinpath(data_root, "caches", "datadeps")

        for d in (GO.forcing_dir[], GO.restoring_dir[], GO.output_dir[],
                  joinpath(data_root, "caches"), joinpath(data_root, "caches", "datadeps"))
            @test isdir(d)
        end

        # no prefix: output goes straight into the user's directory; calling again is harmless
        GO.auto_config_directories!(; user = "tester", data_root, output_root)
        @test rstrip(GO.output_dir[], '/') == joinpath(output_root, "tester")
        @test ENV["DATADEPS_ALWAYS_ACCEPT"] == "true"
    end
end

@testset "atomic_replace!" begin
    dir = mktempdir()
    dst = joinpath(dir, "file.nc")
    write(dst, "old")
    write(dst * ".tmp", "stale tmp from a crash")

    @test GO.atomic_replace!(dst, tmp -> write(tmp, "new")) == dst
    @test read(dst, String) == "new"
    @test !ispath(dst * ".tmp")

    # replacing a symlink with a real file, and back again
    src = write_fake(joinpath(dir, "source.nc"), 16)
    link = joinpath(dir, "link.nc")
    symlink(src, link)
    GO.atomic_replace!(link, tmp -> cp(src, tmp))
    @test isfile(link) && !islink(link)
    @test read(link) == read(src)
    GO.atomic_replace!(link, tmp -> symlink(src, tmp))
    @test islink(link) && readlink(link) == src
end

@testset "setup_staging_directory" begin
    source = mktempdir()
    staging = joinpath(mktempdir(), "staging") # does not exist yet

    a = write_fake(joinpath(source, "a.nc"), 100)
    b = write_fake(joinpath(source, "b.nc"), 100)
    c = write_fake(joinpath(source, "c.nc"), 100)
    write_fake(joinpath(source, "notes.txt"), 10)

    @test GO.setup_staging_directory(source, staging) == staging
    @test isdir(staging)
    for f in (a, b, c)
        dst = joinpath(staging, basename(f))
        @test islink(dst) && readlink(dst) == f
    end
    @test !ispath(joinpath(staging, "notes.txt")) # only .nc files are linked

    # Simulate a previous run: a good real copy of a.nc, a truncated copy of b.nc, a leftover tmp
    rm(joinpath(staging, "a.nc")); cp(a, joinpath(staging, "a.nc"))
    rm(joinpath(staging, "b.nc")); write_fake(joinpath(staging, "b.nc"), 37)
    write_fake(joinpath(staging, "c.nc.tmp"), 5)

    GO.setup_staging_directory(source, staging)

    @test isfile(joinpath(staging, "a.nc")) && !islink(joinpath(staging, "a.nc")) # healthy copy kept
    @test islink(joinpath(staging, "b.nc")) && readlink(joinpath(staging, "b.nc")) == b # truncated copy healed
    @test !ispath(joinpath(staging, "c.nc.tmp")) # leftover tmp swept
    @test islink(joinpath(staging, "c.nc"))
end

@testset "stage_repeat_year_files!" begin
    source = mktempdir()
    staging = mktempdir()
    ryf_tas = write_fake(joinpath(source, ryf_name("tas")), 64)
    ryf_uas = write_fake(joinpath(source, ryf_name("uas")), 64)
    other   = write_fake(joinpath(source, jra55_name("tas", 1990)), 64)
    GO.setup_staging_directory(source, staging)

    @test isnothing(GO.stage_repeat_year_files!(source, staging))

    for f in (ryf_tas, ryf_uas)
        dst = joinpath(staging, basename(f))
        @test isfile(dst) && !islink(dst)
        @test read(dst) == read(f)
    end
    @test islink(joinpath(staging, basename(other))) # not repeat-year: left as a symlink
    @test isempty(filter(endswith(".tmp"), readdir(staging)))

    # already-real copies are skipped (a second call must not touch them)
    marker = joinpath(staging, basename(ryf_tas))
    write(marker, "modified locally")
    GO.stage_repeat_year_files!(source, staging)
    @test read(marker, String) == "modified locally"
end

@testset "stage_jra55! uses the directory Refs" begin
    with_restored_config() do
        source = mktempdir()
        staging = joinpath(mktempdir(), "staging")
        ryf = write_fake(joinpath(source, ryf_name("tas")), 32)
        GO.forcing_dir[] = source
        GO.staging_dir[] = staging

        # multi-year: just symlinks
        @test GO.stage_jra55!(GO.MultiYearJRA55()) == staging
        @test islink(joinpath(staging, basename(ryf)))

        # repeat year: real copies
        @test GO.stage_jra55!(GO.RepeatYearJRA55()) == staging
        dst = joinpath(staging, basename(ryf))
        @test isfile(dst) && !islink(dst)
        @test read(dst) == read(ryf)
    end
end

@testset "stage_jra55_year! / unstage_jra55_year!" begin
    source = mktempdir()
    staging = mktempdir()
    files = Dict((v, y) => write_fake(joinpath(source, jra55_name(v, y)), 48) for v in ("tas", "uas", "prra") for y in (1990, 1991))
    unknown = write_fake(joinpath(source, jra55_name("notavar", 1990)), 48) # not a JRA55 shortname
    GO.setup_staging_directory(source, staging)

    staged(v, y) = (p = joinpath(staging, basename(files[(v, y)])); isfile(p) && !islink(p))

    @test isnothing(GO.stage_jra55_year!(source, staging, 1990))
    @test all(staged(v, 1990) for v in ("tas", "uas", "prra"))
    @test !any(staged(v, 1991) for v in ("tas", "uas", "prra"))
    @test islink(joinpath(staging, basename(unknown)))
    @test read(joinpath(staging, basename(files[("tas", 1990)]))) == read(files[("tas", 1990)])

    # staging again is a no-op for files already copied
    marker = joinpath(staging, basename(files[("uas", 1990)]))
    write(marker, "keep me")
    GO.stage_jra55_year!(source, staging, 1990)
    @test read(marker, String) == "keep me"

    @test isnothing(GO.unstage_jra55_year!(source, staging, 1990))
    for v in ("tas", "uas", "prra")
        p = joinpath(staging, basename(files[(v, 1990)]))
        @test islink(p) && readlink(p) == files[(v, 1990)]
    end
    @test isempty(filter(endswith(".tmp"), readdir(staging)))
end

function wait_until(condition; timeout = 30)
    t₀ = time()
    while !condition() && time() - t₀ < timeout
        sleep(0.02)
    end
    return condition()
end

@testset "JRA55DataStagingCallback" begin
    years = 1990:1994
    mock_simulation(t) = (; model = (; clock = (; time = t)))

    for async in (false, true)
        @testset "async = $async" begin
            source = mktempdir()
            staging = mktempdir()
            files = Dict(y => write_fake(joinpath(source, jra55_name("tas", y)), 32) for y in years)
            GO.setup_staging_directory(source, staging)
            is_staged(y) = (p = joinpath(staging, basename(files[y])); isfile(p) && !islink(p))

            callback = GO.JRA55DataStagingCallback(; source_dir = source, staging_dir = staging,
                                                     start_date = DateTime(1990, 1, 1), async)

            callback(mock_simulation(0.0))
            # a second call in the same year blocks on (and reaps) any in-flight copy of the current year
            callback(mock_simulation(1.0))
            @test is_staged(1990)
            async && wait_until(() -> is_staged(1991)) # don't race the unstaging below
            @test is_staged(1991)

            # jump to 1993: stage 1993/1994, unstage everything before 1992
            t1993 = Dates.value(Second(DateTime(1993, 6, 1) - DateTime(1990, 1, 1)))
            callback(mock_simulation(Float64(t1993)))
            callback(mock_simulation(Float64(t1993) + 1))
            @test is_staged(1993)
            @test !is_staged(1990)
            @test !is_staged(1991)
            @test !is_staged(1992) # never requested

            async && wait_until(() -> is_staged(1994))
            @test is_staged(1994)
        end
    end
end
