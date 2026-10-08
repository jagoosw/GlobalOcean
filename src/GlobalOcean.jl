module GlobalOcean

export auto_config_directories!,
       ORCA1, ORCA025, ORCA12,
       forced_ocean_simulation,
       MaunaLoaCO₂,
       PrescribedChlorophyllAttenuation

using Dates
using NumericalEarth
using Oceananigans

const on_bouchet = isdir("/nfs/roberts/pi/pi_ey239")
const forcing_dir = Ref(on_bouchet ? "/nfs/roberts/pi/pi_ey239/js5256/OAEMIP/data/forcing" : "data/forcing")
const restoring_dir = Ref(on_bouchet ? "/nfs/roberts/pi/pi_ey239/js5256/OAEMIP/data/climatology" : "data/climatology")
const staging_dir = Ref(on_bouchet ? joinpath("/tmp", "jra55_" * get(ENV, "SLURM_JOB_ID", string(getpid()))) : "data/staging")
const bgc_dir = Ref(on_bouchet ? "/nfs/roberts/pi/pi_ey239/js5256/OAEMIP/data" : "data")
const output_dir = Ref(on_bouchet ? (joinpath("/nfs/roberts/pi/pi_ey239/", get(ENV, "USER", "no_user_this_should_error_as_long_as_no_one_makes_this_folder"), "output")) :
                                    "data/output")

include("data_management.jl")
include("grids.jl")
include("defaults.jl")
include("unified_bgc.jl")
include("river_input.jl")
include("interpolated_iron_dust.jl")
include("biogeochemistry.jl")
include("light_attenuation.jl")
include("mauna_loa.jl")
include("construct_model.jl")

function __init__()
    auto_config_directories!()
    @info "Setup directories. Forcing: $(forcing_dir[]), restoring: $(restoring_dir[]), output: $(output_dir[])."
end

end # module GlobalOcean
