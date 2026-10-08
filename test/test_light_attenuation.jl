# PrescribedChlorophyllAttenuation: the two-band effective attenuation coefficient

using Adapt: adapt

@testset "log_light_fraction" begin
    llf = GO.log_light_fraction

    for (f₁, κ₁, κ₂) in ((0.58, 1 / 0.35, 0.05), (0.3, 0.02, 2.0), (0.5, 0.1, 0.1))
        @test llf(0.0, f₁, κ₁, κ₂) ≈ 0 atol = 1e-14 # all the light at the surface
        for z in (-1.0, -10.0, -100.0)
            # equals log of the two-band fraction where that doesn't underflow
            @test llf(z, f₁, κ₁, κ₂) ≈ log(f₁ * exp(κ₁ * z) + (1 - f₁) * exp(κ₂ * z))
        end
        # stable where the direct form underflows: tends to log(weight) + κ_min z
        κ = min(κ₁, κ₂)
        weight = κ₁ < κ₂ ? f₁ : (κ₁ == κ₂ ? 1.0 : 1 - f₁)
        @test isfinite(llf(-1e4, f₁, κ₁, κ₂))
        @test llf(-1e4, f₁, κ₁, κ₂) ≈ κ * -1e4 + log(weight) rtol = 1e-10
    end

    # single exponentials
    @test llf(-7.0, 0.0, 3.0, 0.1) ≈ 0.1 * -7
    @test llf(-7.0, 1.0, 3.0, 0.1) ≈ 3.0 * -7
end

@testset "PrescribedChlorophyllAttenuation" begin
    defaults = GO.PrescribedChlorophyllAttenuation()
    @test defaults.first_color_fraction == 0.58
    @test defaults.first_decay_coefficient ≈ 1 / 0.35
    @test defaults.clear_water_attenuation == 0.0232
    @test defaults.chlorophyll_scaling == 0.074
    @test defaults.chlorophyll_exponent == 0.674

    grid = RectilinearGrid(size = (1, 1, 50), x = (0, 1), y = (0, 1), z = (-500, 0))
    clock = Clock(time = 0.0)
    κ₂(C, optics) = optics.clear_water_attenuation + optics.chlorophyll_scaling * max(0, C)^optics.chlorophyll_exponent

    # f₁ = 0: a single exponential, so every cell's effective coefficient is exactly κ₂(C)
    single = GO.PrescribedChlorophyllAttenuation(first_color_fraction = 0.0)
    for C in (0.0, 0.1, 1.0, 5.0)
        for k in (1, 25, 50)
            @test single(1, 1, k, grid, clock, C) ≈ κ₂(C, single)
        end
    end

    # negative chlorophyll is clipped to clear water
    @test single(1, 1, 50, grid, clock, -1.0) ≈ single.clear_water_attenuation

    # two bands: positive, between the two coefficients, decreasing with depth towards κ₂
    for C in (0.0, 0.3, 2.0)
        κs = [defaults(1, 1, k, grid, clock, C) for k in 1:50]
        k₂ = κ₂(C, defaults)
        @test all(κs .> 0)
        @test all(k₂ * (1 - 1e-12) .<= κs .<= defaults.first_decay_coefficient)
        @test all(diff(κs) .>= -1e-12) # non-decreasing upwards (k = 1 is the deepest), up to roundoff
        @test κs[1] ≈ k₂ rtol = 1e-6
        @test κs[end] ≈ k₂ - log(1 - defaults.first_color_fraction) / 10 rtol = 1e-6 # the fast band is gone by 10 m
    end

    # more chlorophyll attenuates more
    @test defaults(1, 1, 50, grid, clock, 2.0) > defaults(1, 1, 50, grid, clock, 0.1)

    # the per-cell coefficients integrate to the light fraction: Σ κ Δz = -log I(z)/I(0)
    κs = [defaults(1, 1, k, grid, clock, 0.5) for k in 1:50]
    Δz = 10
    f₁, κ₁, κw = defaults.first_color_fraction, defaults.first_decay_coefficient, κ₂(0.5, defaults)
    @test sum(κs[41:50]) * Δz ≈ -GO.log_light_fraction(-100.0, f₁, κ₁, κw)

    # Float32
    optics32 = GO.PrescribedChlorophyllAttenuation{Float32}(0.58f0, 1 / 0.35f0, 0.0232f0, 0.074f0, 0.674f0)
    @test adapt(Array, optics32) == optics32
    @test adapt(Array, defaults) == defaults
end
