# Biogeochemistry

[`forced_ocean_simulation`](@ref) tries to automatically set up the additional features needed for biogeochemistry: rivers, dust, and gas exchange.

- If you `using OceanBioME`, a `NumericalEarth` extension is loaded that automatically sets up ``CO_2`` and ``O_2`` gas exchange.
- River loads are added from [RivR2O](https://zenodo.org/records/14889524), co-located with the land model river mouths.
- Dust is supplied by [UnifiedBGC](https://roms-tools.readthedocs.io/en/latest/datasets_overview.html#unified-bgc-dataset) from ROMS-tools.
- BGC tracers are also initialised from UnifiedBGC.

For example, to set up an equivalent of the [MITgcm DIC package](https://mitgcm.readthedocs.io/en/latest/phys_pkgs/dic.html), which tracks ``PO_4``, ``Fe``, ``DOP``, ``DIC``, ``Alk`` and ``O_2``, with Mauna Loa atmospheric ``pCO_2``:

```julia
using OceanBioME

arch = GPU()
grid = ORCA1(arch)

surface_PAR = PARFromShortwave(grid)
light_attenuation = PrescribedAttenuationPAR(grid, surface_PAR;
                                             attenuation = PrescribedChlorophyllAttenuation(first_color_fraction = 0.0),
                                             attenuation_discrete_form = true)

biogeochemistry = MITgcmDIC(grid;
                            light_attenuation,
                            open_bottom = false,
                            implicit_sinking = true,
                            store_flux = true)

pCO₂ = MaunaLoaCO₂(arch; dates = DateTime(1990, 1, 15):Month(1):DateTime(1990, 12, 15),
                         start_date = DateTime(1990, 1, 1),
                         period = 365days)

simulation = forced_ocean_simulation(grid;
                                     biogeochemistry,
                                     atmosphere_tracers = (; pCO₂),
                                     jra55_dataset = RepeatYearJRA55(),
                                     start_date = DateTime(1990, 1, 1))
```

[`MaunaLoaCO₂`](@ref)`(arch)` with no other arguments gives the monthly record for 1958--2017, cycled with the multi-year JRA55 forcing (see [Forcing data](@ref)); here we instead repeat 1990 to go with repeat-year forcing.

We have to use `PARFromShortwave` to get the downwelling radiation from the atmosphere component of the model and, since this model doesn't prognose phytoplankton, we use the chlorophyll climatology from the radiation model to attenuate the light through `PrescribedAttenuationPAR` with `PrescribedChlorophyllAttenuation`.

## Alkalinity release

You can prescribe a Gaussian alkalinity release following the OAEMIP protocol by adding a [`GaussianInjection`](@ref) forcing:

```julia
alkalinity_release = GaussianInjection(grid, (-49.5, 0), 0.0; duration = 20days) # grid, center (λ, φ in degrees), start time (s)

simulation = forced_ocean_simulation(grid;
                                     biogeochemistry,
                                     atmosphere_tracers = (; pCO₂),
                                     jra55_dataset = RepeatYearJRA55(),
                                     start_date = DateTime(1990, 1, 1),
                                     forcing = (; Alk2 = alkalinity_release))
```

The default is 1 Tmol (`total_injection = 1000e12` mmol) over 1 year, in a patch with a 250 km standard deviation cut off at 3 standard deviations, in the surface cells only.
See [Alkalinity release at the mouth of the Amazon](@ref) for a complete example.
