using OptEvapCool
using StatsPlots

function anu_crossbeam_test()
    #= Expect (with final power 2W)
        Final N: 6e6
        Final T: 700nK - 1 uK
        # Changing to final power 1.5 would give BEC
    =#

    # Cloud parameters
    Np = 3e7
    T₀ = 15e-6
    species = Rb87

    duration = 1.97

    F = Np / (1e4) # TEMPORARILY FIX VALUE OF Nt
    Nc = 4
    Nt = ceil(Int64, Np / F)

    # Beam parameters
    P₁ = exponential_ramp(15, 2, 0.8) # Watts
    P₂ = exponential_ramp(7.5, 2, 0.8)

    w₀ = 130e-6 # Beam waist (m)
    θ = ( 22.5 * π / 180 ) / 2 # Half-angle between crossed beams

    dir1 = [cos(θ), 0, sin(θ)]
    dir2 = [cos(θ), 0, -sin(θ)]
    λ₁ = 1064e-9
    λ₂ = 1090e-9

    beam1 = GaussianBeam([0,0,0], dir1, P₁, w₀, λ₁)
    beam2 = GaussianBeam([0,0,0], dir2, P₂, w₀, λ₂)

    acc1 = acceleration(gravity)
    acc2 = acceleration(beam1)
    acc3 = acceleration(beam2)

    function accel(p, s, t, o)
        a1 = acc1(p, s, t)
        a2 = acc2(p, s, t)
        a3 = acc3(p, s, t)
        return (o .= a1 + a2 + a3)
    end

    pot1 = potential(beam1)
    pot2 = potential(beam2)
    pot3 = potential(gravity)

    function crossbeam_potential(p, s, t)
        return pot1(p, s, t) + pot2(p, s, t)
    end

    function total_potential(p, s, t)
        return pot3(p, s, t) + crossbeam_potential(p, s, t)
    end

    # Trapping frequencies
    m = species.m
    κ = kappa(species)

    Uₜ_coeff = 2 * κ / (π * w₀^2)
    Uₜ(t) = Uₜ_coeff * (P₁(t) + P₂(t)) #Trap depth

    ωx_coeff = sqrt(4 * cos(θ)^2 / (m * w₀^2))
    ωz_coeff = sqrt(4 * sin(θ)^2 / (m * w₀^2))
    ωy_coeff = sqrt(4 / (m * w₀^2))

    ωx(t) = ωx_coeff * sqrt(Uₜ(t))
    ωz(t) = ωz_coeff * sqrt(Uₜ(t))
    ωy(t) = ωy_coeff * sqrt(Uₜ(t))

    # Cloud initialisation
    positions = harmonic_boltzmann_positions(Nt, m, T₀, ωx(0), ωy(0), ωz(0))
    velocities = boltzmann_velocities(Nt, m, T₀)

    # Function to make measurements on the system
    sensor = GlobalSensor()
    measure = measurer(sensor)

    # Evaporation
    evap = energy_evap(Uₜ, crossbeam_potential)

    conditions = SimulationConditions(species, F, positions, velocities,
        accel, total_potential, evap = evap)

    max_dt = 0.05 * 2π / max(ωx(0), ωy(0), ωz(0))
    # Run evolution
    final_cloud = evolve(conditions, duration;
        Nc = Nc, max_dt = max_dt, measure = measure)

    # Plotting
    temperature_plt, T_final = plot_temperature(sensor)

    max_speed = maximum(OptEvapCool.speeds(final_cloud))
    speed_hist = plot_speed(final_cloud)
    plot!(equilibrium_speeds(m, T_final, max_speed)...,
        label = "Theory")

    number_plt = plot_number(sensor)
    energy_plt = plot_energy(sensor)
    collrate_plt = plot_collrate(sensor)

    # Save plots and files
    ft = filetime()
    dir = "./results/$ft-crossbeam"
    mkpath(dir)

    savefig(temperature_plt, "$dir/temp.png")
    savefig(energy_plt, "$dir/energy.png")
    savefig(speed_hist, "$dir/speed.png")
    savefig(collrate_plt, "$dir/collrate.png")
    savefig(number_plt, "$dir/number.png")

    savecsv(sensor, "$dir/sensor-data.csv")

    return nothing
end