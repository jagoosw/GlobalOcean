function auto_config_directories!(prefix = ""; 
                                  user = ENV["USER"],
                                  output_root = on_bouchet ? "/nfs/roberts/pi/pi_ey239" : "output",
                                  data_root = on_bouchet ? "/nfs/roberts/pi/pi_ey239/js5256/OAEMIP/data/" : "data",
                                  datadeps_always_accept = true)

    global ENV["DATADEPS_ALWAYS_ACCEPT"]        = "$(datadeps_always_accept)"
    global ENV["NUMERICALEARTH_DATA_DIRECTORY"] = joinpath(data_root, "caches")
    global ENV["DATADEPS_LOAD_PATH"]            = joinpath(data_root, "caches", "datadeps")

    forcing_dir[] = joinpath(data_root, "forcing")
    restoring_dir[] = joinpath(data_root, "climatology")
    output_dir[] = joinpath(output_root, user, prefix)

    for d in (forcing_dir[], restoring_dir[], output_dir[],
              ENV["NUMERICALEARTH_DATA_DIRECTORY"], ENV["DATADEPS_LOAD_PATH"])
        mkpath(d)
    end
   
    return nothing
end