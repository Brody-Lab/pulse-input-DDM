"""
    mean_exp_rate_per_trial(pz, py, data, f_str; use_bin_center=false, dt=1e-2, num_samples=100)
Given parameters and model inputs returns the average expected firing rate of the model computed over num_samples number of samples.
"""
function mean_exp_rate_per_trial(pz, py, data, f_str::String; use_bin_center::Bool=false, dt::Float64=1e-2,
        num_trials::Int=100)

    output = map(i-> sample_expected_rates_multiple_sessions(pz, py, data, f_str, use_bin_center, dt; rng=i), 1:num_samples)
    mean(map(k-> output[k][1], 1:length(output)))

end



"""
    mean_exp_rate_per_cond(pz, py, data, f_str; use_bin_center=false, dt=1e-2, num_samples=100)

"""
function mean_exp_rate_per_cond(pz, py, data, f_str::String; use_bin_center::Bool=false, dt::Float64=1e-2,
        num_trials::Int=100)

    μ_rate = mean_exp_rate_per_trial(pz, py, data, f_str; use_bin_center=use_bin_center, dt=dt, num_samples=num_samples)

    map(i-> condition_mean_varying_duration_trials(μ_rate[i], data[i]["conds"],
            data[i]["nconds"], data[i]["N"], data[i]["nT"]), 1:length(data))

end


"""
"""
function condition_mean_varying_duration_trials(μ_rate, conds, nconds, N, nT)

    map(n-> map(c-> [mean([μ_rate[conds .== c][k][n][t]
        for k in findall(nT[conds .== c] .>= t)])
        for t in 1:(maximum(nT[conds .== c]))],
                1:nconds), 1:N)

end


"""
"""
function boot_LL(pz,py,data,f_str,i,n)
    dcopy = deepcopy(data)
    dcopy["spike_counts"] = sample_spikes_multiple_sessions(pz, py, [dcopy], f_str; rng=i)[1]

    LL_ML = compute_LL(pz, py, [dcopy], n, f_str)

    #LL_null = mapreduce(d-> mapreduce(r-> mapreduce(n->
    #            neural_null(d["spike_counts"][r][n], d["λ0"][r][n], d["dt"]),
    #                +, 1:d["N"]), +, 1:d["ntrials"]), +, [data])

    #(LL_ML - LL_null) / dcopy["ntrials"]

    LL_null = mapreduce(d-> mapreduce(r-> mapreduce(n->
        neural_null(d["spike_counts"][r][n], map(λ-> f_py(0.,λ, py[1][n],f_str), d["λ0"][r][n]), d["dt"]),
            +, 1:d["N"]), +, 1:d["ntrials"]), +, [dcopy])

    #return 1. - (LL_ML/LL_null), LL_ML, LL_null
    LL_ML - LL_null

end


"""
"""
function sample_clicks_and_spikes(θz::θz, py::Vector{Vector{Vector{Float64}}},
        f_str::String, num_sessions::Int, num_trials_per_session::Vector{Int}; centered::Bool=false,
        dtMC::Float64=1e-4, rng::Int=0)

    clicks = map((ntrials,rng)-> synthetic_clicks(ntrials; rng=rng), num_trials_per_session, (1:num_sessions) .+ rng)

    data = Vector{Any}(undef, num_sessions)
    for i = 1:num_sessions
        data[i] = Dict()
        @unpack L,R,T,ntrials = clicks[i]
        data[i]["leftbups"] = L
        data[i]["rightbups"] = R
        data[i]["T"] = T
        data[i]["ntrials"] = ntrials
    end

    map((data,py) -> data=sample_λ0!(data, py; dtMC=dtMC), data, py)

    Y = sample_spikes_multiple_sessions(θz, py, data, f_str, centered, dtMC; rng=rng)
    map((data,Y)-> data["spike_counts"] = Y, data, Y)

    return data, Y, clicks

end

function sample_λ0!(data, py::Vector{Vector{Float64}}; dtMC::Float64=1e-4, rng::Int=1)

    data["dt_synthetic"], data["synthetic"], data["N"] = dtMC, true, length(py)

    #Random.seed!(rng)
    #data["λ0"] = [repeat([collect(range(10. *rand(),stop=10. * rand(),
    #                    length=Int(ceil(T./dt))))], outer=length(py)) for T in data["T"]]
    data["λ0"] = [repeat([zeros(Int(ceil(T./dtMC)))], outer=length(py)) for T in data["T"]]

    return data

end


"""
"""
function sample_spikes_multiple_sessions(θz::θz, py::Vector{Vector{Vector{Float64}}},
        data, f_str::String, centered::Bool, dt::Float64; rng::Int=1)

    λ, = sample_expected_rates_multiple_sessions(θz, py, data, f_str, centered, dt; rng=rng)
    Y = map((λ,data)-> map(λ-> map(λ-> poisson_noise!.(λ, dt), λ), λ), λ, data)
    #Y = map((py,λ0)-> poisson_noise!.(map((a, λ0)-> f_py!(a, λ0, py, f_str), a, λ0), dt), py, λ0)

    #this assumes only one spike per bin, which should most often be true at 1e-4, but not guaranteed!
    #findall(x-> x > 1, pulse_input_DDM.poisson_noise!.(10 * ones(100 * 10 * Int(1. /1e-4)),1e-4))
    #Y = map((py,λ0)-> findall(x -> x != 0,
    #        poisson_noise!.(map((a, λ0)-> f_py!(a, λ0, py, f_str=f_str), a, λ0), dt)) .* dt, py, λ0)

    return Y

end


"""
"""
function sample_expected_rates_multiple_sessions(θz::θz, py::Vector{Vector{Vector{Float64}}},
        data, f_str::String, centered::Bool, dt::Float64; rng::Int=1)

    nsessions = length(data)

    output = map((data, py)-> sample_expected_rates_single_session(data, θz, py, f_str, centered, dt; rng=rng),
        data, py)

    λ = map(x-> x[1], output)
    a = map(x-> x[2], output)

    return λ, a

end


"""
"""
function sample_expected_rates_single_session(data::Dict, θz::θz, py::Vector{Vector{Float64}},
        f_str::String, centered::Bool, dt::Float64; rng::Int=1)

    Random.seed!(rng)

    T, L, R, λ0 = data["T"], data["leftbups"], data["rightbups"], data["λ0"]

    binned_clicks = bin_clicks(clicks(L, R, T, data["ntrials"]), centered=centered, dt=dt)
    @unpack nT, nL, nR = binned_clicks

    output = pmap((λ0,nT,L,R,nL,nR,rng) -> sample_expected_rates_single_trial(θz,py,λ0,nT,L,R,nL,nR,
        f_str,centered,dt; rng=rng), λ0, nT, L, R, nL, nR, shuffle(1:length(T)))

    λ = map(x-> x[1], output)
    a = map(x-> x[2], output)

    return λ,a

end


"""
"""
function sample_expected_rates_single_trial(θz::θz, py::Vector{Vector{Float64}}, λ0::Vector{Vector{Float64}},
        nT::Int, L::Vector{Float64}, R::Vector{Float64}, nL::Vector{Int}, nR::Vector{Int},
        f_str::String, centered::Bool, dt::Float64; rng::Int=1)

    Random.seed!(rng)
    a = rand(θz,nT,L,R,nL,nR; centered=centered, dt=dt)
    λ = map((py,λ0)-> map((a, λ0)-> f_py!(a, λ0, py, f_str), a, λ0), py, λ0)

    return λ, a

end


"""
"""
poisson_noise!(lambda,dt) = Int(rand(Poisson(lambda*dt)))
