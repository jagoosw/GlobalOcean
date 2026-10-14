# GaussianInjection / GaussianInjectionLowMemory on a small latitude-longitude grid around the Amazon release site

const INJECTION_GRID = LatitudeLongitudeGrid(size = (20, 20, 2), longitude = (-60, -40), latitude = (-10, 10), z = (-20, 0))
const INJECTION_CENTER = (-49.5, 0)

injection_clock(t) = (; time = t)

@testset "GaussianInjection" begin
    start, duration, total = 10days, 365days, 1000e12 # s, s, mmol
    gi = GaussianInjection(INJECTION_GRID, INJECTION_CENTER, start; duration, total_injection = total)

    mask = interior(gi.mask)
    @test all(mask[:, :, 1] .== 0) # surface layer only
    @test maximum(mask) ≈ exp(-(GO.spherical_distance(-49.5, 0, -49.5, 0.5, GO.planet_radius(INJECTION_GRID)))^2 / (2 * 250000^2))
    @test all(0 .<= mask .<= 1)

    # nothing beyond the cutoff (3σ = 750 km, about 6.7°): the domain corners are ~1500 km away
    @test mask[1, 1, 2] == 0
    @test mask[20, 20, 2] == 0

    # the rate releases `total` over `duration`
    rate(i, j, k, t) = gi(i, j, k, INJECTION_GRID, injection_clock(t), nothing)
    released = sum(rate(i, j, 2, start) * Oceananigans.Operators.Vᶜᶜᶜ(i, j, 2, INJECTION_GRID) for i in 1:20, j in 1:20) * duration
    @test released ≈ total

    # only between `start_time` and `start_time + duration`
    i, j = 10, 10
    @test rate(i, j, 2, start) > 0
    @test rate(i, j, 2, start + duration / 2) == rate(i, j, 2, start)
    @test rate(i, j, 2, start - 1) == 0
    @test rate(i, j, 2, start + duration) == 0
    @test rate(i, j, 1, start) == 0
end

@testset "GaussianInjectionLowMemory" begin
    start = 10days
    gi = GaussianInjection(INJECTION_GRID, INJECTION_CENTER, start)
    low = GaussianInjectionLowMemory(INJECTION_GRID, INJECTION_CENTER, start)

    @test isbits(low)
    @test low.rate == gi.rate

    @test all(low(i, j, k, INJECTION_GRID, injection_clock(t), nothing) ≈ gi(i, j, k, INJECTION_GRID, injection_clock(t), nothing)
              for t in (start - 1, start, start + 100days), k in 1:2, j in 1:20, i in 1:20)
end

@testset "GaussianInjection as a forcing" begin
    grid = INJECTION_GRID
    model = HydrostaticFreeSurfaceModel(grid; tracers = :A, buoyancy = nothing,
                                        forcing = (; A = GaussianInjection(grid, INJECTION_CENTER, 0; duration = 1days)))
    time_step!(model, 3600) # s
    @test maximum(interior(model.tracers.A, :, :, 2)) > 0
    @test all(interior(model.tracers.A, :, :, 1) .== 0)
end
