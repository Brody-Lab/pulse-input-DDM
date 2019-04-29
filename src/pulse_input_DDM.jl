module pulse_input_DDM

#using Revise
using StatsBase, Distributions, Optim, LineSearches, JLD2
using ForwardDiff, Distributed, LinearAlgebra
using Pandas, SpecialFunctions, MAT, Random 
using DSP
#using ROCAnalysis
#using ImageFiltering
#using DataFrames
#using BasisFunctionExpansions

#using GLM add later for linear regression

include("latent_variable_model_functions.jl")
include("helper_functions.jl")
#include("initialize_spike_obs_model.jl")
include("manipulate_data_functions.jl")
include("choice_observation_model.jl")
include("poisson_neural_observation.jl")
include("analysis_functions.jl")
include("choice_and_poisson_neural_observation.jl")
include("wrapper_functions.jl")
include("mapping_functions.jl")
include("sample_model_functions.jl")
include("data_sessions.jl")

export poiss_LL, aggregate_spiking_data, aggregate_choice_data
export nanmean, nanstderr
export diffLR, dimz
export optimize_model, sample_model, fy, bins, sigmoid_4param, softplus_3param
export compute_LL, compute_Hessian, compute_CI, load_and_optimize
export filter_data_by_cell!, sessids_from_region, group_by_neuron!, aggregate_and_append_extended_spiking_data!
export train_test_divide, compute_H_CI!

end # module
