# Chlorophyll-dependent light attenuation, copied from OAEMIP/src/light_attenuation.jl

using Oceananigans: HydrostaticFreeSurfaceModel, Center, Face
using OceanBioME: DiscreteBiogeochemistry, PrescribedAttenuationPAR

using Oceananigans.Grids: znode
using Oceananigans.Units: Time
using Adapt: Adapt, adapt
using NumericalEarth.EarthSystemModels.InterfaceComputations: state2dindex

import OceanBioME: chlorophyll

const ModelWithPrescribedAttenuation = 
    HydrostaticFreeSurfaceModel{<:Any, <:Any, <:Any, 
                                <:Any, <:Any, <:Any, 
                                <:Any, <:Any, <:Any, 
                                <:Any, <:Any, <:DiscreteBiogeochemistry{<:Any, <:PrescribedAttenuationPAR}} # TODO: add nonhydro 

# does this need to be so specific...
chlorophyll(::DiscreteBiogeochemistry{<:Any, <:PrescribedAttenuationPAR}, model::ModelWithPrescribedAttenuation) =
    model.forcing.T.chlorophyll

@kwdef struct PrescribedChlorophyllAttenuation{FT} <: Function
       first_color_fraction :: FT = 0.58
    first_decay_coefficient :: FT = 1 / 0.35
    clear_water_attenuation :: FT = 0.0232
        chlorophyll_scaling :: FT = 0.074
       chlorophyll_exponent :: FT = 0.674
end

Adapt.adapt_structure(to, pca::PrescribedChlorophyllAttenuation) = # only needed because were subtyping Function, maybe would be okay just `= pca`
    PrescribedChlorophyllAttenuation(adapt(to, pca.first_color_fraction),
                                     adapt(to, pca.first_decay_coefficient),
                                     adapt(to, pca.clear_water_attenuation),
                                     adapt(to, pca.chlorophyll_scaling),
                                     adapt(to, pca.chlorophyll_exponent))

@inline function log_light_fraction(z, f₁, κ₁, κ₂)
    κ = min(κ₁, κ₂)
    return κ * z + log(f₁ * exp((κ₁ - κ) * z) + (1 - f₁) * exp((κ₂ - κ) * z))
end

@inline function (optics::PrescribedChlorophyllAttenuation)(i, j, k, grid, clock, chlorophyll)
    C = @inbounds state2dindex(chlorophyll, i, j, grid, Time(clock.time))

    f₁ = optics.first_color_fraction
    κ₁ = optics.first_decay_coefficient
    κw = optics.clear_water_attenuation
    Cs = optics.chlorophyll_scaling
    Ce = optics.chlorophyll_exponent

    κ₂ = κw + Cs * max(0, C)^Ce

    z₁ = znode(i, j, k+1, grid, Center(), Center(), Face())
    z₂ = znode(i, j, k, grid, Center(), Center(), Face())

    return (log_light_fraction(z₁, f₁, κ₁, κ₂) - log_light_fraction(z₂, f₁, κ₁, κ₂)) / (z₁ - z₂)
end
