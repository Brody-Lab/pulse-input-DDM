function remean(data, μ_rnt; do_RBF=true, nRBFs=6)
    
    spikes = getfield.(data, :spikes)
    input_data = getfield.(data, :input_data)
    choice = getfield.(data, :choice)   
    binned_clicks = getfield.(input_data, :binned_clicks)
    clicks = getfield.(input_data, :clicks)   
    nT = getfield.(binned_clicks, :nT)
    @unpack dt, centered, delay, pad = input_data[1]
    
    ncells = data[1].ncells
    
    μ_t = Vector(undef, ncells)

    for n = 1:ncells

        μ_t[n] =  map(n->[max(0., mean([μ_rnt[i][n][t]
            for i in findall(nT .+ 2*pad .>= t)]))
            for t in 1:(maximum(nT) .+ 2*pad)], n:n)

        λ0 = map(nT-> bin_λ0(μ_t[n], nT+2*pad), nT)

        input_data = neuralinputs(clicks, binned_clicks, λ0, dt, centered, delay, pad)
        spike_data = neuraldata(input_data, map(x-> [x[n]], spikes), 1, choice)

        if do_RBF
            θ = optimize([spike_data], [1]; nRBFs=nRBFs, show_trace=false)
            maxnT = maximum(nT)
            x = 1:maxnT+2*pad   
            rbf = UniformRBFE(x, nRBFs, normalize=true)  
            μ_t[n] = [rbf(x) * θ.θμ[1][1]]
        end

    end

    μ_t = map(x-> x[1], μ_t);
    λ0 = map(nT-> bin_λ0(μ_t, nT+2*pad), nT)
    input_data = neuralinputs(clicks, binned_clicks, λ0, dt, centered, delay, pad)
    spike_data = neuraldata(input_data, spikes, ncells, choice)
    
    return spike_data, μ_rnt, μ_t
    
end


"""
"""
function save(file, model::neuralDDM, options, CI)

    @unpack lb, ub, fit = options
    @unpack θ = model
    
    dict = Dict("ML_params"=> collect(pulse_input_DDM.flatten(θ)),
        "lb"=> lb, "ub"=> ub, "fit"=> fit,
        "CI" => CI)

    matwrite(file, dict)

    #=
    if !isempty(H)
        #dict["H"] = H
        hfile = matopen(path*"hessian_"*file, "w")
        write(hfile, "H", H)
        close(hfile)
    end
    =#

end


"""
"""
#function bin_clicks_spikes_λ0(data::Dict; centered::Bool=true,
#        dt::Float64=1e-2, delay::Float64=0., pad::Int=10, filtSD::Int=5)

function bin_clicks_spikes_λ0(spikes, clicks, λ0; centered::Bool=true,
        dt::Float64=1e-2, delay::Float64=0., dt_synthetic::Float64=1e-4,
        synthetic::Bool=false)

    spikes = bin_spikes(spikes, dt, dt_synthetic)
    binned_clicks = bin_clicks(clicks, centered=centered, dt=dt)
    λ0 = bin_λ0(λ0, dt, dt_synthetic)

    return spikes, binned_clicks, λ0

end


"""
"""
bin_λ0(λ0::Vector{Vector{Vector{Float64}}}, dt, dt_synthetic) = bin_λ0.(λ0, dt, dt_synthetic)


"""
"""
#bin_λ0(λ0::Vector{Vector{Float64}}, dt, dt_synthetic) = decimate.(λ0, Int(dt/dt_synthetic))
bin_λ0(λ0::Vector{Vector{Float64}}, dt, dt_synthetic) = 
     map(λ0-> mean.(Iterators.partition(λ0, Int(dt/dt_synthetic))), λ0)


"""
"""
bin_spikes(spikes::Vector{Vector{Vector{Int}}}, dt, dt_synthetic) = bin_spikes.(spikes, dt, dt_synthetic)



"""
"""
bin_spikes(spikes::Vector{Vector{Int}}, dt::Float64, dt_synthetic::Float64) = 
    map(SCn-> sum.(Iterators.partition(SCn, Int(dt/dt_synthetic))), spikes)


"""
"""
function bin_spikes(spike_times::Vector{Vector{Float64}}, dt, nT::Int; pad::Int=20, extra_pad::Int=10) 

    trial = map(x-> StatsBase.fit(Histogram, vec(collect(x)), 
            collect(range(-pad*dt, stop=(nT+pad)*dt, 
                    length=(nT+2*pad)+1)), closed=:left).weights, spike_times)

    padded = map(x-> StatsBase.fit(Histogram, vec(collect(x)), 
            collect(range(-(extra_pad+pad)*dt, stop=(nT+pad+extra_pad)*dt, 
                    length=(nT+2*extra_pad+2*pad)+1)), closed=:left).weights, spike_times)


    return trial, padded
    
end


"""
"""
bin_λ0(λ0::Vector{Vector{Float64}}, nT) = map(λ0-> λ0[1:nT], λ0)


"""
"""
function filtered_rate(padded, dt; filtSD::Int=5, cut::Int=10)

    kern = reflect(KernelFactors.gaussian(filtSD, 8*filtSD+1));

    map(padded-> imfilter(1/dt * padded, kern,
            Fill(zero(eltype(padded))))[cut+1:end-cut], padded)

end


"""

    process_spike_data(μ_rnt, data)

Arguments:

- `μ_rnt`: `array` of Gaussian-filterd single trial firing rates for all cells and all trials in one session. `μ_rnt` is output from `load_neural_data`.
- `data`: `array` of all trial data for one session. `data` is output from `load_neural_data`.

Optional arguments: 

- `nconds`: number of groups to make to compute PSTHs

Returns: 

- `μ_ct`: mean PSTH for each group.
- `σ_ct`: 1 std PSTH for each group.

"""
function process_spike_data(μ_rnt, data; nconds::Int=4)
    
    ncells = data[1].ncells

    pad = data[1].input_data.pad
    nT = map(x-> x.input_data.binned_clicks.nT, data)
    μ_rn = map(n-> map(μ_rnt-> mean(μ_rnt[n]), μ_rnt), 1:ncells)

    ΔLRT = map((data,nT) -> getindex(diffLR(data), pad+nT), data, nT)
    conds = encode(LinearDiscretizer(binedges(DiscretizeUniformWidth(nconds), ΔLRT)), ΔLRT)

    μ_ct = map(n-> map(c-> [mean([μ_rnt[conds .== c][i][n][t]
        for i in findall(nT[conds .== c] .+ (2*pad) .>= t)])
        for t in 1:(maximum(nT[conds .== c]) .+ (2*pad))], 1:nconds), 1:ncells)

    σ_ct = map(n-> map(c-> [std([μ_rnt[conds .== c][i][n][t]
        for i in findall(nT[conds .== c] .+ (2*pad) .>= t)]) /
            sqrt(length([μ_rnt[conds .== c][i][n][t]
                for i in findall(nT[conds .== c] .+ (2*pad) .>= t)]))
        for t in 1:(maximum(nT[conds .== c]) .+ (2*pad))], 1:nconds), 1:ncells)

    return μ_ct, σ_ct, μ_rn

end

group_by_neuron(data) = [[data[t].spikes[n] for t in 1:length(data)] for n in 1:data[1].ncells]

function filter_data_by_dprime!(data,thresh)

    bool_vec = data["d'"] .< thresh
    deleteat!(data["μ_t"], bool_vec)
    deleteat!(data["μ_ct"], bool_vec)
    deleteat!(data["σ_ct"], bool_vec)
    deleteat!(data["μ_rn"], bool_vec)
    map(x-> deleteat!(x, bool_vec), data["spike_counts_padded"])
    map(x-> deleteat!(x, bool_vec), data["spike_counts"])
    map(x-> deleteat!(x, bool_vec), data["spike_times"])
    map(x-> deleteat!(x, bool_vec), data["μ_rnt"])
    map(x-> deleteat!(x, bool_vec), data["λ0"])
    map(x-> deleteat!(x, bool_vec), data["cellID"])

    deleteat!(data["d'"], bool_vec);
    data["N"] = length(data["d'"])

    return data

end

function filter_data_by_ΔLL!(data,ΔLL,thresh)

    bool_vec = ΔLL .< thresh
    deleteat!(data["μ_t"], bool_vec)
    deleteat!(data["μ_ct"], bool_vec)
    deleteat!(data["σ_ct"], bool_vec)
    deleteat!(data["μ_rn"], bool_vec)
    map(x-> deleteat!(x, bool_vec), data["spike_counts_padded"])
    map(x-> deleteat!(x, bool_vec), data["spike_counts"])
    map(x-> deleteat!(x, bool_vec), data["spike_times"])
    map(x-> deleteat!(x, bool_vec), data["μ_rnt"])
    map(x-> deleteat!(x, bool_vec), data["λ0"])
    map(x-> deleteat!(x, bool_vec), data["cellID"])

    deleteat!(data["d'"], bool_vec);
    data["N"] = length(data["d'"])

    return data

end

#################################### Data filtering #########################

#This doesn't work, but might be a good idea to fix up.

function filter_data_by_cell!(data,cell_index)

    data["N0"] = length(cell_index)

    #organized by neurons, so filter by neurons
    data["spike_counts_by_neuron"] = data["spike_counts_by_neuron"][cell_index]
    data["trial"] = data["trial"][cell_index]
    data["cellID_by_neuron"] = data["cellID_by_neuron"][cell_index]
    data["sessID_by_neuron"] = data["sessID_by_neuron"][cell_index]
    data["ratID_by_neuron"] = data["ratID_by_neuron"][cell_index]

    if (haskey(data,"spike_counts_stimulus_aligned_extended_by_neuron") |
        haskey(data, "spike_counts_cpoke_aligned_extended_by_neuron"))

        data["spike_counts_stimulus_aligned_extended_by_neuron"] =
            data["spike_counts_stimulus_aligned_extended_by_neuron"][cell_index]
        data["spike_counts_cpoke_aligned_extended_by_neuron"] =
            data["spike_counts_cpoke_aligned_extended_by_neuron"][cell_index]

    end

    trial_index = unique(collect(vcat(data["trial"]...)))
    data["trial0"] = length(trial_index)

    #organized by trials, so filter by trials
    data["binned_leftbups"] = data["binned_leftbups"][trial_index]
    data["binned_rightbups"] = data["binned_rightbups"][trial_index]
    data["rightbups"] = data["rightbups"][trial_index]
    data["leftbups"] = data["leftbups"][trial_index]
    data["T"] = data["T"][trial_index]
    data["nT"] = data["nT"][trial_index]
    data["pokedR"] = data["pokedR"][trial_index]
    data["correct_dir"] = data["correct_dir"][trial_index]
    data["sessID"] = data["sessID"][trial_index]
    data["ratID"] = data["ratID"][trial_index]
    data["stim_start"] = data["stim_start"][trial_index]
    data["cpoke_end"] = data["cpoke_end"][trial_index]

    #this subtracts the minimum current trial index from all of the trial indices
    #for i = 1:data["N0"]
    #    #data["trial"] = map(x->x[1] - minimum(trial_index) + 1 : x[end] - minimum(trial_index) + 1, data["trial"])
    #    data["trial"][i] = data["trial"][i][1] - minimum(trial_index) + 1 : data["trial"][i][end] - minimum(trial_index) + 1
    #end

    #tvec2 = deepcopy(unique(vcat(data["trial"]...)))
    #map!(x->findall(x[1] .== tvec2)[1]:findall(x[end] .== tvec2)[1], data["trial"], data["trial"])

    #trial_index = unique(collect(vcat(data["trial"]...)))

    #shifts all trial times so the run consequtively from 1:data["trial0"]
    #for i = 1:data["N0"]
    #    data["trial"][i] = findfirst(data["trial"][i][1] .== trial_index) : findfirst(data["trial"][i][end] .== trial_index)
    #end

    data["N"] = Vector{Vector{Int}}(undef,0)
    map(x->push!(data["N"], Vector{Int}(undef,0)), 1:data["trial0"])
    data["cellID"] = Vector{Vector{Int}}(undef,0)
    map(x->push!(data["cellID"], Vector{Int}(undef,0)), 1:data["trial0"])
    data["spike_counts"] = Vector{Vector{Vector{Int64}}}(undef,0)
    map(x->push!(data["spike_counts"], Vector{Vector{Int}}(undef,0)), 1:data["trial0"])

    #map(y->map(x->push!(data["N"][x],y), data["trial"][y]), 1:data["N0"])
    #map(y->map(x->push!(data["cellID"][x], cell_index[y]), data["trial"][y]), 1:data["N0"])
    #map(y->map(x->push!(data["spike_counts"][data["trial"][y][x]], data["spike_counts_by_neuron"][y][x]),
    #        1:length(data["trial"][y])), 1:data["N0"])

    for i = 1:data["N0"]

        #shifts all trial times so the run consequtively from 1:data["trial0"]
        data["trial"][i] = findfirst(data["trial"][i][1] .== trial_index) : findfirst(data["trial"][i][end] .== trial_index)

        for j = 1:length(data["trial"][i])

            push!(data["N"][data["trial"][i][j]], i)
            push!(data["cellID"][data["trial"][i][j]], data["cellID_by_neuron"][i])
            push!(data["spike_counts"][data["trial"][i][j]], data["spike_counts_by_neuron"][i][j])

        end
    end

    return data

end

#=

######INCOMPLETE##########

function aggregate_and_append_extended_spiking_data!(data::Dict, path::String, sessids::Vector{Vector{Int}},
        ratnames::Vector{String}, dt::Float64, ts::Float64, tf::Float64; delay::Float64=0.)

    data["spike_counts_stimulus_aligned_extended"] = Vector{Vector{Vector{Int64}}}()
    data["spike_counts_cpoke_aligned_extended"] = Vector{Vector{Vector{Int64}}}()
    data["spike_counts_stimulus_aligned_extended_by_neuron"] = Vector{Vector{Vector{Int64}}}()
    data["spike_counts_cpoke_aligned_extended_by_neuron"] = Vector{Vector{Vector{Int64}}}()
    map(x-> push!(data["spike_counts_stimulus_aligned_extended_by_neuron"], Vector{Vector{Int}}(undef,0)), 1:data["N0"])
    map(x-> push!(data["spike_counts_cpoke_aligned_extended_by_neuron"], Vector{Vector{Int}}(undef,0)), 1:data["N0"])
    data["time_basis_edges"] = (floor.(ts/dt) * dt) : dt : (ceil.(tf/dt) * dt)
    #data["time_basis_centers"] = (data["time_basis_edges"][1] + dt/2): dt: (data["time_basis_edges"][end-1] + dt/2)
    data["time_basis_centers"] = data["time_basis_edges"][1:end-1]

    for j = 1:length(ratnames)
        for i = 1:length(sessids[j])
            rawdata = read(matopen(path*"/"*ratnames[j]*"_"*string(sessids[j][i])*".mat"),"rawdata")
            data = append_extended_neural_data!(data, rawdata, dt, ts, tf, delay=delay)
        end
    end

    map(n-> map(t-> append!(data["spike_counts_stimulus_aligned_extended_by_neuron"][n],
        data["spike_counts_stimulus_aligned_extended"][t][data["N"][t] .== n]), data["trial"][n]), 1:data["N0"])

    map(n-> map(t-> append!(data["spike_counts_cpoke_aligned_extended_by_neuron"][n],
        data["spike_counts_cpoke_aligned_extended"][t][data["N"][t] .== n]), data["trial"][n]), 1:data["N0"])

    return data

end

function append_extended_neural_data!(data::Dict, rawdata::Dict, dt::Float64, ts::Float64, tf::Float64;
        delay::Float64=0.)

    N = size(rawdata["spike_times"][1],2)
    ntrials = length(rawdata["T"])

    #time = data["time_basis_edges"]

    binnedT = ceil.(Int,rawdata["T"]/dt)

    append!(data["spike_counts_stimulus_aligned_extended"], map((t,tri) -> map(n -> fit(Histogram, vec(collect(tri[n] .- delay)),
        -10*dt:dt:((t+10)*dt), closed=:left).weights, 1:N), binnedT, rawdata["spike_times"]))

    #append!(data["spike_counts_cpoke_aligned_extended"], map(tri -> map(n -> fit(Histogram, vec(collect(tri[n])),
    #    time, closed=:left).weights, 1:N), rawdata["spike_times"]))

    time = data["time_basis_edges"]

    for i = 1:ntrials

        blah = map(n -> fit(Histogram, vec(collect(rawdata["spike_times"][i][n] .+ rawdata["stim_start"][i] .- delay)),
                time, closed=:left).weights, 1:N)
        push!(data["spike_counts_cpoke_aligned_extended"], blah)

    end

    return data

end

function λ0_by_trial(data::Dict, μ_λ; cpoke_aligned::Bool=false,
        extended::Bool=false)

    λ0 = Dict("by_trial" => Vector{Vector{Vector{Float64}}}(undef,0),
        "by_neuron" => Vector{Vector{Vector{Float64}}}())

    map(x->push!(λ0["by_trial"] , Vector{Vector{Float64}}(undef,0)), 1:data["trial0"])
    map(x-> push!(λ0["by_neuron"], Vector{Vector{Float64}}(undef,0)), 1:data["N0"])

    for i = 1:data["N0"]
        for j = 1:length(data["trial"][i])

            if extended

                if cpoke_aligned
                    stim_start = data["stim_start"][data["trial"][i][j]]
                else
                    stim_start =  0.
                end
                T0 = findlast(collect(data["time_basis_edges"]) .<= stim_start)

            else
                T0 = 1
            end

            nT = data["nT"][data["trial"][i][j]]

            push!(λ0["by_trial"][data["trial"][i][j]], μ_λ[i][T0: T0+ nT - 1])

        end
    end

    map(n-> map(t-> append!(λ0["by_neuron"][n],
                λ0["by_trial"][t][data["N"][t] .== n]), data["trial"][n]), 1:data["N0"])

    return λ0

end

function append_neural_data!(data::Dict, rawdata::Dict, ratname::String, sessID::Int, dt::Float64;
        delay::Float64=0.)

    N = size(rawdata["spike_times"][1],2)
    ntrials = length(rawdata["T"])

    #by trial
    #append!(data["cellID"], map(x-> vec(collect(x)), rawdata["cellID"]))
    #append!(data["stim_start"], rawdata["stim_start"])

    #by neuron
    append!(data["cellID_by_neuron"], rawdata["cellID"][1])
    append!(data["sessID_by_neuron"], repeat([sessID], inner=N))
    append!(data["ratID_by_neuron"], repeat([ratname], inner=N))
    append!(data["trial"], repeat([data["trial0"]+1 : data["trial0"]+ntrials], inner=N))

    #if organize == "by_trial"

    #by trial
    binnedT = ceil.(Int,rawdata["T"]/dt)

    append!(data["cellID"], map(x-> vec(collect(x)), rawdata["cellID"]))

    append!(data["spike_counts"], map((x,y) -> map(z -> fit(Histogram, vec(collect(y[z] .- delay)),
            0.:dt:x*dt, closed=:left).weights, 1:N), binnedT, rawdata["spike_times"]))
    append!(data["N"], repeat([collect(data["N0"]+1 : data["N0"]+N)], inner=ntrials))

    #by neuron
    #append!(data["trial"], repeat([data["trial0"]+1 : data["trial0"]+ntrials], inner=N))

    #elseif organize == "by_neuron"

    #    append!(data["spike_counts"],map!(z -> map!((x,y) -> fit(Histogram,vec(collect(y[z])),
    #            0.:dt:x*dt,closed=:left).weights, Vector{Vector}(undef,ntrials),
    #            binnedT,rawdata["spike_times"]), Vector{Vector}(undef,N),1:N))

    #    append!(data["spike_counts_all"], map!(z -> map!((x,y) -> fit(Histogram,vec(collect(y[z])),
    #            0.:dt:x*dt, closed=:left).weights, Vector{Vector}(undef,ntrials),
    #            binnedT, rawdata["spike_times"]), Vector{Vector}(undef,N), 1:N))

    #    append!(data["trial"],repeat([data["trial0"]+1:data["trial0"]+ntrials],inner=N))

    #end

    data["N0"] += N
    data["trial0"] += ntrials

    return data

end

#function group_by_neuron!(data)

    #trials = Vector{Vector{Int}}()
    #data["spike_counts_by_neuron"] = Vector{Vector{Vector{Int64}}}()

    #map(x->push!(trials,Vector{Int}(undef,0)),1:data["N0"])
    #map(x-> push!(data["spike_counts_by_neuron"], Vector{Vector{Int}}(undef,0)), 1:data["N"])

    #map(y->map(x->push!(trials[x],y),data["N"][y]),1:data["trial0"])
    #map(n-> map(t-> append!(data["spike_counts_by_neuron"][n],
    #            data["spike_counts"][t][n]), 1:data["ntrials"]), 1:data["N"])

    #return trials, SC

    #=

    if (haskey(data,"spike_counts_stimulus_aligned_extended_by_neuron") |
        haskey(data, "spike_counts_cpoke_aligned_extended_by_neuron"))

        #trials = Vector{Vector{Int}}()
        data["spike_counts_stimulus_aligned_extended_by_neuron"] = Vector{Vector{Vector{Int64}}}()

        #map(x->push!(trials,Vector{Int}(undef,0)),1:data["N0"])
        map(x-> push!(data["spike_counts_stimulus_aligned_extended_by_neuron"], Vector{Vector{Int}}(undef,0)), 1:data["N0"])

        #map(y->map(x->push!(trials[x],y),data["N"][y]),1:data["trial0"])
        map(n-> map(t-> append!(data["spike_counts_stimulus_aligned_extended_by_neuron"][n],
            data["spike_counts_stimulus_aligned_extended"][t][data["N"][t] .== n]), data["trial"][n]), 1:data["N0"])

        #trials = Vector{Vector{Int}}()
        data["spike_counts_cpoke_aligned_extended_by_neuron"] = Vector{Vector{Vector{Int64}}}()
        #map(x->push!(trials,Vector{Int}(undef,0)),1:data["N0"])
        map(x-> push!(data["spike_counts_cpoke_aligned_extended_by_neuron"], Vector{Vector{Int}}(undef,0)), 1:data["N0"])

        #map(y->map(x->push!(trials[x],y),data["N"][y]),1:data["trial0"])
        map(n-> map(t-> append!(data["spike_counts_cpoke_aligned_extended_by_neuron"][n],
            data["spike_counts_cpoke_aligned_extended"][t][data["N"][t] .== n]), data["trial"][n]), 1:data["N0"])

    end

    =#

    #return data

#end

function package_extended_data!(data,rawdata,model_type::String,ratname,ts::Float64;dt::Float64=2e-2,organize::String="by_trial")

    ntrials = length(rawdata["T"])

    append!(data["sessid"],map(x->x[1],rawdata["sessid"]))
    append!(data["cell"],map(x->vec(collect(x)),rawdata["cell"]))
    append!(data["ratname"],map(x->ratname,rawdata["cell"]))

    maxT = ceil.(Int,(rawdata["T"])/dt)
    binnedT = ceil.(Int,(rawdata["T"] + ts)/dt);

    append!(data["nT"],binnedT)

    if any(model_type .== "spikes")

        N = size(rawdata["St"][1],2)

        if organize == "by_trial"

            append!(data["spike_counts"],map((x,y)->map(z->fit(Histogram,vec(collect(y[z])),
                    -ts:dt:x*dt,closed=:left).weights,1:N),maxT,rawdata["St"]));
            append!(data["N"],repmat([collect(data["N0"]+1:data["N0"]+N)],ntrials));

        elseif organize == "by_neuron"

            append!(data["spike_counts"],map!(z -> map!((x,y) -> fit(Histogram,vec(collect(y[z])),
                    -ts:dt:x*dt,closed=:left).weights,Vector{Vector}(ntrials),
                    maxT,rawdata["St"]),Vector{Vector}(N),1:N));
            append!(data["trial"],repmat([data["trial0"]+1:data["trial0"]+ntrials],N));

        end

        data["N0"] += N
        data["trial0"] += ntrials

    end

    return data

end

#scrub a larger dataset to only keep data relevant to a single neuron
function keep_single_neuron_data!(data,i)

    data["nT"] = data["nT"][data["trial"][i]]
    data["leftbups"] = data["leftbups"][data["trial"][i]]
    data["rightbups"] = data["rightbups"][data["trial"][i]]
    data["binned_rightbups"] = data["binned_rightbups"][data["trial"][i]]
    data["binned_leftbups"] = data["binned_leftbups"][data["trial"][i]]

    data["N"] = data["N"][data["trial"][i]]
    data["spike_counts"] = data["spike_counts"][data["trial"][i]]

    data["spike_counts"] = map((x,y)->x = x[y.==i],data["spike_counts"],data["N"])
    map!(x->x = [1],data["N"],data["N"])

    return data

end

#just hanging on to this for some later time
function my_callback(os)

    so_far = time() - start_time
    println(" * Time so far:     ", so_far)

    history = Array{Float64,2}(sum(fit_vec),0)
    history_gx = Array{Float64,2}(sum(fit_vec),0)
    for i = 1:length(os)
        ptemp = group_params(os[i].metadata["x"], p_const, fit_vec)
        ptemp = map_func!(ptemp,model_type,"tanh",N=N)
        ptemp_opt, = break_params(ptemp, fit_vec)
        history = cat(2,history,ptemp_opt)
        history_gx = cat(2,history_gx,os[i].metadata["g(x)"])
    end
    save(out_pth*"/history.jld", "history", history, "history_gx", history_gx)

    return false

end

#function my_callback(os)

    #so_far = time() - start_time
    #println(" * Time so far:     ", so_far)

    #history = Array{Float64,2}(sum(fit_vec),0)
    #history_gx = Array{Float64,2}(sum(fit_vec),0)
    #for i = 1:length(os)
    #    ptemp = group_params(os[i].metadata["x"], p_const, fit_vec)
    #    ptemp = map_func!(ptemp,model_type,"tanh",N=N)
    #    ptemp_opt, = break_params(ptemp, fit_vec)
    #    history = cat(2,history,ptemp_opt)
    #    history_gx = cat(2,history_gx,os[i].metadata["g(x)"])
    #end
    #print(os[1]["x"])
    #save(ENV["HOME"]*"/spike-data_latent-accum"*"/history.jld", "os", os)
    #print(path)

#    return false

#end

=#