
#################################### Poisson neural observation model #########################

function sample_input_and_spikes_multiple_sessions(pz::Vector{Float64}, py::Vector{Vector{Vector{Float64}}}, 
        ntrials_per_sess::Vector{Int}; f_str::String="softplus", rng::Int=0, use_bin_center::Bool=false)
    
    nsessions = length(ntrials_per_sess)
      
    data = map((py,ntrials,rng)-> sample_inputs_and_spikes_single_session(pz, py, ntrials; rng=rng, f_str=f_str,
            use_bin_center=use_bin_center), 
        py, ntrials_per_sess, (1:nsessions) .+ rng)   
    
    return data
    
end

function sample_inputs_and_spikes_single_session(pz::Vector{Float64}, py::Vector{Vector{Float64}}, ntrials::Int; 
        dtMC::Float64=1e-4, rng::Int=1, f_str::String="softplus", use_bin_center::Bool=false)
    
    data = sample_clicks(ntrials; rng=rng)
    data["dtMC"] = dtMC
    data["synthetic"] = true
    data["N"] = length(py)
    
    data["λ0_MC"] = [repeat([zeros(Int(ceil(T./dtMC)))], outer=length(py)) for T in data["T"]]
    #data["spike_times"] = sample_spikes_single_session(data, pz, py; dtMC=dtMC, rng=rng, f_str=f_str)
    data["spike_counts_MC"] = sample_spikes_single_session(data, pz, py; dtMC=dtMC, rng=rng, f_str=f_str,
        use_bin_center=use_bin_center)
            
    return data
    
end

function sample_spikes_single_session(data::Dict, pz::Vector{Float64}, py::Vector{Vector{Float64}}; 
        f_str::String="softplus", dtMC::Float64=1e-4, rng::Int=1, use_bin_center::Bool=false)
    
    Random.seed!(rng)   
    nT,nL,nR = bin_clicks(data["T"],data["leftbups"],data["rightbups"],dtMC,use_bin_center)
    #spike_times = pmap((λ0,nT,L,R,nL,nR,rng) -> sample_spikes_single_trial(pz,py,λ0,nT,L,R,nL,nR;
    #    f_str=f_str, rng=rng, dtMC=dtMC), 
    #    data["λ0"], nT, data["leftbups"], data["rightbups"], nL, nR, shuffle(1:length(data["T"]))) 
    
    spike_counts = pmap((λ0,nT,L,R,nL,nR,rng) -> sample_spikes_single_trial(pz,py,λ0,nT,L,R,nL,nR;
        f_str=f_str, rng=rng, dtMC=dtMC, use_bin_center=use_bin_center), 
        data["λ0_MC"], nT, data["leftbups"], data["rightbups"], nL, nR, shuffle(1:length(data["T"])))  
    
    return spike_counts
    
end

function sample_spikes_single_trial(pz::Vector{Float64}, py::Vector{Vector{Float64}}, λ0::Vector{Vector{Float64}}, 
        nT::Int, L::Vector{Float64}, R::Vector{Float64}, nL::Vector{Int}, nR::Vector{Int};
        f_str::String="softplus", dtMC::Float64=1e-4, rng::Int=1, use_bin_center::Bool=false)
    
    Random.seed!(rng)    
    a = sample_latent(nT,L,R,nL,nR,pz,use_bin_center;dt=dtMC)
    #this assumes only one spike per bin, which should most often be true at 1e-4, but not guaranteed!
    #findall(x-> x > 1, pulse_input_DDM.poisson_noise!.(10 * ones(100 * 10 * Int(1. /1e-4)),1e-4))
    #Y = map((py,λ0)-> findall(x -> x != 0, 
    #        poisson_noise!.(map((a, λ0)-> f_py!(a, λ0, py, f_str=f_str), a, λ0), dtMC)) .* dtMC, py, λ0)    
    
    Y = map((py,λ0)-> poisson_noise!.(map((a, λ0)-> f_py!(a, λ0, py, f_str), a, λ0), dtMC), py, λ0)    
    
end

poisson_noise!(lambda,dt) = lambda = Int(rand(Poisson(lambda*dt)))

#################################### Expected rates, Poisson neural observation model #########################

function sample_average_expected_rates_multiple_sessions(pz, py, data, f_str::String)
    
    output = map(i-> sample_expected_rates_multiple_sessions(pz, py, data, f_str; rng=i), 1:100)
    μ_rate = mean(map(k-> output[k][1], 1:length(output)))
    
    #μ_hat_ct = map(i-> map(n-> map(c-> [mean([μ_rate[i][data[i]["conds"] .== c][k][n][t] 
    #    for k in findall(data[i]["nT"][data[i]["conds"] .== c] .>= t)]) 
    #    for t in 1:(maximum(data[i]["nT"][data[i]["conds"] .== c]))], 
    #            1:data[i]["nconds"]), 
    #                1:data[i]["N"]), 
    #                    1:length(data))
    
    μ_hat_ct = map(i-> condition_mean_varying_duration_trials(μ_rate[i], data[i]["conds"], 
            data[i]["nconds"], data[i]["N"], data[i]["nT"]), 1:length(data))
    
    return μ_hat_ct
    
end

function condition_mean_varying_duration_trials(μ_rate, conds, nconds, N, nT)
    
    map(n-> map(c-> [mean([μ_rate[conds .== c][k][n][t] 
        for k in findall(nT[conds .== c] .>= t)]) 
        for t in 1:(maximum(nT[conds .== c]))], 
                1:nconds), 1:N)
    
end

function sample_expected_rates_multiple_sessions(pz::Vector{Float64}, py::Vector{Vector{Vector{Float64}}}, 
        data, f_str::String; rng::Int=1)
    
    nsessions = length(data)
      
    output = map((data, py)-> sample_expected_rates_single_session(data, pz, py, f_str; rng=rng), 
        data, py)   
    
    λ = map(x-> x[1], output)
    a = map(x-> x[2], output)  
    
    return λ, a
    
end

function sample_expected_rates_single_session(data::Dict, pz::Vector{Float64}, py::Vector{Vector{Float64}}, 
        f_str::String; rng::Int=1)
    
    #removed lambda0_MC to lambda0
    Random.seed!(rng)   
    use_bin_center = data["use_bin_center"]
    dt = data["dt"]
    output = pmap((λ0,nT,L,R,nL,nR,rng) -> sample_expected_rates_single_trial(pz,py,λ0,nT,L,R,nL,nR,dt,
        f_str,use_bin_center; rng=rng), 
        data["λ0"], data["nT"], data["leftbups"], data["rightbups"], data["binned_leftbups"], 
        data["binned_rightbups"], shuffle(1:length(data["T"])))    
    
    λ = map(x-> x[1], output)
    a = map(x-> x[2], output)  
    
    return λ,a
    
end

function sample_expected_rates_single_trial(pz::Vector{Float64}, py::Vector{Vector{Float64}}, λ0::Vector{Vector{Float64}}, 
        nT::Int, L::Vector{Float64}, R::Vector{Float64}, nL::Vector{Int}, nR::Vector{Int}, dt::Float64,
        f_str::String,use_bin_center::Bool; rng::Int=1)
    
    Random.seed!(rng)  
    #changed this from 
    #a = decimate(sample_latent(nT,L,R,nL,nR,pz;dt=dtMC), Int(dt/dtMC))
    a = sample_latent(nT,L,R,nL,nR,pz,use_bin_center;dt=dt)
    λ = map((py,λ0)-> map((a, λ0)-> f_py!(a, λ0, py, f_str), a, λ0), py, λ0)  
    
    return λ, a
    
end