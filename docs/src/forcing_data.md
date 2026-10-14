# Forcing data

To change the automatically configured data and output directories, change the value of `NumericalOcean.forcing_dir`, `NumericalOcean.restoring_dir`, `NumericalOcean.staging_dir`, `NumericalOcean.bgc_dir`, and `NumericalOcean.output_dir`.
They are `Ref`s, so you set them like

```julia
NumericalOcean.bgc_dir[] = "~/bgc_data/"
```

`staging_dir` is only needed when you have a slow `forcing_dir`, so that data can be asynchronously loaded to a faster drive before it is needed.

## Normally...

When you first load this package it will create the directories `data/forcing_data`, `data/climatology`, `data/output`, and `data/staging`.
When you run the model for the first time it will try to download the whole JRA55 surface dataset, which is around 700 GiB, so it is probably best to arrange for this before running, with `scripts/download_forcing.jl`.

Repeat-year (1990) forcing is much smaller; to use it pass `jra55_dataset = RepeatYearJRA55()`.
It is also small enough to be fully loaded into GPU memory on an H100 if you pass `backend_size = 2920` (one year of 3-hourly records), which gives a meaningful speed-up.

To use the biogeochemistry setup you will also need to download [UnifiedBGC](https://roms-tools.readthedocs.io/en/latest/datasets_overview.html#unified-bgc-dataset) and the [RivR2O](https://zenodo.org/records/14889524) dataset.

## On Bouchet

If you are running on Bouchet the package will point to a predownloaded copy of all the data; if you cannot access it please email [Jago](mailto:jago.strong-wright@yale.edu).
On Bouchet `staging_dir` is automatically configured to use the fast NVMe storage on the nodes, and is used if you pass `staging = true` to [`forced_ocean_simulation`](@ref) (although this has given minimal performance gain).
