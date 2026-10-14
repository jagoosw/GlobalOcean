# NumericalOcean

Global ocean--sea ice configurations in [Oceananigans](https://github.com/clima/oceananigans.jl/), with optional biogeochemistry from [OceanBioME](https://github.com/OceanBioME/OceanBioME.jl).
This configuration package assumes familiarity with Oceananigans and, to some extent, [NumericalEarth](https://github.com/numericalearth/numericalearth.jl/).

## Setup

This package depends on unreleased branches of Oceananigans, ClimaSeaIce, OceanBioME, SeawaterPolynomials, and NumericalEarth.
To install, create a Julia project:

```console
~$ mkdir AnOceanProject
~$ cd AnOceanProject
~$ touch Project.toml
~$ julia --project -t auto
```

and add the branches along with NumericalOcean:

```julia
julia> using Pkg

julia> Pkg.add([PackageSpec(url="https://github.com/NumericalEarth/NumericalEarth.jl.git", rev="jsw/omip-bgc"),
                PackageSpec(url="https://github.com/NumericalEarth/NumericalEarth.jl.git", rev="jsw/omip-bgc", subdir="experiments/OMIPSimulations"),
                PackageSpec(url="https://github.com/Clima/Oceananigans.jl.git", rev="jsw/for-oaemip"),
                PackageSpec(url="https://github.com/jagoosw/ClimaSeaIce.jl.git", rev="jsw/for-oaemip"),
                PackageSpec(url="https://github.com/OceanBioME/OceanBioME.jl.git", rev="jsw/for-oaemip"),
                PackageSpec(url="https://github.com/clima/SeawaterPolynomials.jl.git", rev="ss/conversion-functions"),
                PackageSpec(url="https://github.com/jagoosw/NumericalOcean", rev="v0.1.0")])
```

The branches have to be added first, in the same call or before `NumericalOcean`, because Pkg ignores the `[sources]` in NumericalOcean's `Project.toml` when it is installed as a package, and `OMIPSimulations` and some dependencies are not registered.
This puts Oceananigans, OceanBioME and NumericalEarth in your project, so they can be used in scripts; you will also need to add CUDA to run on the GPU:

```julia
julia> Pkg.add("CUDA")
```

Alternatively, clone the repository and use it as the project (`julia --project=. -e 'using Pkg; Pkg.instantiate()'`), where its `[sources]` are used directly.

## Contents

- [Physics](physics.md): the default ocean--sea ice setup and how to modify it.
- [Biogeochemistry](biogeochemistry.md): rivers, dust, gas exchange and alkalinity releases.
- [Forcing data](forcing_data.md): where the data lives and how to get it.
- [Restart files](restarts.md): starting from the OMIP spin-up.
- [Spun-up configurations](configurations.md): what the spun-up states were built with.
- [Spinning up the ``1\degree`` configuration](generated/1degree_spinup.md): building the spin-up the restarts come from.
- [Alkalinity release at the mouth of the Amazon](@ref): a worked example.

## Performance

Currently we get around 90 simulated years per day with the MITgcm BGC, and 140 simulated years per day with physics only, on an H100 on Bouchet.

We have been requesting 8 CPUs with 16 GB of memory each (probably excessive) and running Julia with `--threads=4 --gcthreads=4,1`, which helped performance a bit.
