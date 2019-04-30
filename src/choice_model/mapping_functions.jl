#################################### Choice observation model #################################

"""
    map_split_combine(p_opt, p_const, fit_vec, dt)  

    Combine constant and variable optimization components, split into functional groups andmap to bounded domain
"""
function map_split_combine(p_opt, p_const, fit_vec, dt,
    lb::Vector{Float64}, ub::Vector{Float64})
    
    pz, pd = split_latent_and_observation(combine_variable_and_const(p_opt, p_const, fit_vec))
    pz = map_pz!(pz,dt,lb,ub)
    pd = map_pd!(pd)
    
    return pz, pd
    
end

"""
    split_combine_invmap(pz, bias, fit_vec, dt)  

    Inverse map parameters to unbounded domain for optimization, combine functional groups and split into optimization variables and constants
"""
function split_combine_invmap(pz::Vector{TT}, pd::Vector{TT}, fit_vec, dt,
        lb::Vector{Float64}, ub::Vector{Float64}) where {TT <: Any}

    pz = inv_map_pz!(copy(pz),dt,lb,ub)
    pd = inv_map_pd!(copy(pd))
    
    p_opt, p_const = split_variable_and_const(combine_latent_and_observation(pz,pd),fit_vec)

    return p_opt, p_const
    
end

split_latent_and_observation(p::Vector{TT}) where {TT} = p[1:dimz], p[dimz+1:dimz+2]
combine_latent_and_observation(pz::Vector{TT}, pd::Vector{TT}) where {TT} = vcat(pz,pd)

function map_pd!(x)
    
    lb = [-Inf, 0.]
    ub = [Inf, 1.]
    
    x[1] = x[1]       
    x[2] = lb[2] + (ub[2] - lb[2]) * normtanh(x[2])  
    
    return x
    
end

function inv_map_pd!(x)
    
    lb = [-Inf, 0.]
    ub = [Inf, 1.]
    
    x[1] = x[1]
    x[2] = normatanh((x[2] - lb[2])/(ub[2] - lb[2]))
        
    return x
    
end