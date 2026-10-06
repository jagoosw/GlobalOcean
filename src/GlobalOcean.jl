module GlobalOcean

export auto_config_directories!

const on_bouchet = isdir("/nfs/roberts/pi/pi_ey239")
const forcing_dir = Ref(on_bouchet ? "/nfs/roberts/pi/pi_ey239/js5256/OAEMIP/data/forcing" : "data/forcing")
const restoring_dir = Ref(on_bouchet ? "/nfs/roberts/pi/pi_ey239/js5256/OAEMIP/data/climatology" : "data/climatology")
const staging_dir = Ref(on_bouchet ? joinpath("/tmp", "jra55_" * get(ENV, "SLURM_JOB_ID", string(getpid()))) : "data/staging")
const output_dir = Ref(on_bouchet ? joinpath("/nfs/roberts/pi/pi_ey239/", get(ENV, "USER", "no_user_this_should_error_as_long_as_no_one_makes_this_folder"), "output") :
                                    "data/output")

include("data_management.jl")

end # module GlobalOcean
