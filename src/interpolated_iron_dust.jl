# Iron dust deposition forcing, copied from OAEMIP/src/interpolated_iron_dust.jl

using KernelAbstractions: @kernel, @index
using Adapt: Adapt, adapt
using OceanBioME: IronDustDeposition
using Oceananigans.Architectures: architecture, on_architecture, CPU
using Oceananigans.Fields: Field, Center
using Oceananigans.Units: Time
using Oceananigans.Utils: launch!
using Oceananigans.OutputReaders: interpolating_time_indices

import Oceananigans.OutputReaders: extract_field_time_series, update_field_time_series!

"""
    InterpolatedIronDust(series; kwargs...)

OceanBioME's `IronDustDeposition` of the surface dust `series` (a 2D `FieldTimeSeries` on the model
grid) as a forcing for `Fe`, with the time interpolation of `series` done once per update into a 2D
field rather than in every cell of the `Fe` tendency kernel. `kwargs` are passed to `IronDustDeposition`.

Evaluated inline (`IronDustDepositionForcing(series)`), the time interpolation (a `mod` of the time,
a search of `times` and two reads, in every thread) pushes the already heavy tracer tendency kernel
over its register budget, slowing it ~10×. Here the kernel reads the surface dust from a 2D field;
the vertical dissolution profile (`znode` and two `exp`s) is still computed inline.

The surface dust is recomputed whenever the model's `FieldTimeSeries` are updated (every
`update_state!`), so the forcing is the same as `IronDustDepositionForcing(series; kwargs...)`.
"""
struct InterpolatedIronDust{S, T, D}
        series :: S # host only
     cpu_times :: T # host only
    deposition :: D # `IronDustDeposition` of the 2D surface dust field
end

function InterpolatedIronDust(series; kwargs...)
    surface_dust = Field{Center, Center, Nothing}(series.grid)
    cpu_times = on_architecture(CPU(), series.times)
    dust = InterpolatedIronDust(series, cpu_times, IronDustDeposition(surface_dust; kwargs...))
    update_surface_dust!(dust, zero(eltype(cpu_times)))
    return dust
end

Adapt.adapt_structure(to, dust::InterpolatedIronDust) =
    InterpolatedIronDust(nothing, nothing, adapt(to, dust.deposition))

@inline (dust::InterpolatedIronDust)(i, j, k, grid, clock, model_fields) =
    dust.deposition(i, j, k, grid, clock, model_fields)

Base.summary(::InterpolatedIronDust) = "InterpolatedIronDust"
Base.show(io::IO, dust::InterpolatedIronDust) = print(io, "InterpolatedIronDust of ", dust.deposition)

@kernel function _interpolate_surface_dust!(surface_dust, series, ñ, n₁, n₂)
    i, j = @index(Global, NTuple)

    @inbounds begin
        ψ₁ = series[i, j, 1, n₁]
        ψ₂ = series[i, j, 1, n₂]
        surface_dust[i, j, 1] = ifelse(n₁ == n₂, ψ₁, ψ₂ * ñ + ψ₁ * (1 - ñ))
    end
end

function update_surface_dust!(dust::InterpolatedIronDust, time)
    series = dust.series
    surface_dust = dust.deposition.dust_deposition
    grid = surface_dust.grid

    # the same indices the `Time` indexing of `series` computes, once on the host
    ñ, n₁, n₂ = interpolating_time_indices(series.time_indexing, dust.cpu_times, time)

    launch!(architecture(grid), grid, :xy, _interpolate_surface_dust!, surface_dust, series, ñ, n₁, n₂)

    return nothing
end

# Hooks into the model's refresh of its `FieldTimeSeries` in `update_state!` (`update_model_field_time_series!`):
# `series` is updated first (a no-op when it is all in memory), then the surface dust is interpolated
extract_field_time_series(dust::InterpolatedIronDust) = (extract_field_time_series(dust.series)..., dust)

update_field_time_series!(dust::InterpolatedIronDust, time::Time) = update_surface_dust!(dust, time.time)
