
#import DataFrames 
#import PrettyTables
#import CSV 

#using NCDatasets
#using Statistics

#export ensemble
#export ensemble_def
#export ensemble_sort!
#export ensemble_get_var!
#export ens_stat
#export ensemble_get_var_ND!
#export ensemble_get_var_slice!
#export load_time_var
#export ensemble_check

mutable struct ensemble
    path::Array{String}
    set::Array{Integer}
    sim::Array{String}
    nsim::Integer
    info::DataFrames.DataFrame
    valid::Any
    color::Any
    label::Any
    linewidth::Any
    markersize::Any
    v::Dict
end

function ensemble_def(path;sort_by::String="")   
    
    # Define the info filename
    fname = string(path,"/","info.txt")

    # Read the ensemble info table into a DataFrame format, if it exists
    if isfile(fname)
        info  = CSV.read(fname,DataFrames.DataFrame,delim=' ',ignorerepeated=true)
    else 
        error(string("ensemble_def:: Error: file does not exist: ",fname))
    end
    
    nsim = DataFrames.nrow(info) 
    
    # Initialize an empty array of the right length
    set = fill(1,nsim)
    sim = fill("",nsim)
    
    # Populate the array
    for i in 1:nsim
        sim[i] = string(path,"/",info[i,"rundir"])
    end

    valid = fill(true,nsim)
    label = fill("",nsim)
    color = fill(colorant"Black",nsim)
    linewidth = fill(1,nsim)
    markersize = fill(1,nsim) 

    # Store all information for output in the ensemble object
    ens = ensemble([path],set,sim,nsim,info,valid,color,label,
                                linewidth,markersize,Dict())

    if sort_by != ""
        ensemble_sort!(ens,sort_by)
    end
                
    return ens

end

function ensemble_def(paths::Array{String};sort_by::String="")   
    
    # Define the ensemble object based on first ensemble set of interest
    ens = ensemble_def(paths[1])

    # Define info array for entire list 
    for j = 2:size(paths,1)

        ens_now = ensemble_def(paths[j])
        
        ens_now.set .= j 

        if j == 1
            ens = deepcopy(ens_now)
        else
            append!(ens.path,ens_now.path)
            append!(ens.set,ens_now.set)
            append!(ens.sim,ens_now.sim)
            append!(ens.info,ens_now.info)
            append!(ens.valid,ens_now.valid)
            append!(ens.color,ens_now.color)
            append!(ens.label,ens_now.label)
            append!(ens.linewidth,ens_now.linewidth)
            append!(ens.markersize,ens_now.markersize)
        end

    end
    
    # Update the total number of simulations and number of ensemble sets 
    ens.nsim = DataFrames.nrow(ens.info) 

    println("Loaded ensemble, number of simulations: ",ens.nsim)
    println("Paths:")
    for j = 1:size(paths,1)
        println("  ",paths[j])
    end

    if sort_by != ""
        ensemble_sort!(ens,sort_by)
    end
    
    return ens
end

function ensemble_sort!(ens,sort_by::String)

    kk = sortperm(ens.info[!,sort_by])
    ens.info        = ens.info[kk,:]
    ens.set         = ens.set[kk]
    ens.sim         = ens.sim[kk]
    ens.valid       = ens.valid[kk]
    ens.color       = ens.color[kk]
    ens.label       = ens.label[kk]
    ens.linewidth   = ens.linewidth[kk]
    ens.markersize  = ens.markersize[kk]

    return
end

function ensemble_get_var!(ens::ensemble,varname::String,filename::String;scale=1.0)

    println("\nLoad ",varname," from ",filename)
    println("  Ensemble path: ",ens.path)
    println("  Number of simulations: ",size(ens.sim,1))

    # Get total number of sims 
    ns  = size(ens.info,1)

    # Make an empty array to hold the variable 
    ens.v[varname] = []

    # Load time and variable from each simulation in ensemble 
    for k in 1:ns 

        # Get path of file of interest for reference sim
        path_now = ens.sim[k] * "/" * filename

        # Open NetCDF file
        ds = NCDataset(path_now,"r")

        # Get variable if it is available
        if !haskey(ds,varname)
            error("load_var:: Error: variable not found in file.")
        else 
            var = ds[varname][:];
        end 

        # Close NetCDF file
        close(ds) 
        
        # Scale variable as desired 
        var = var*scale; 

        # Store variable in ens output
        push!(ens.v[varname],var)
        
    end

    return
end 

function ens_stat(ens,varname::String,stat::Function)

    vals = fill(NaN,ens.nsim)

    for j = 1:ens.nsim 
        vals[j] = stat(ens.v[varname][j])
    end

    return vals
end

function ensemble_get_var_ND!(ens::ensemble,varname::String,filename::String)

    println("\nLoad ",varname," from ",filename)
    println("  Ensemble path: ",ens.path)
    println("  Number of simulations: ",size(ens.sim,1))

    # Set ref sim number to 1 for now
    ref = 2

    # Get total number of sims 
    ns  = size(ens.info,1)

    # Get path of file of interest for reference sim
    path_now = ens.sim[ref] * "/" * filename

    # First load variable from reference sim
    ds = NCDataset(path_now,"r")

    #print(ds)

    if (!haskey(ds,varname))
        error("ensemble_get_var:: Error: variable not found in file.")
    end

    # Get dimensions of variable of interest 
    v = ds[varname]

    dims  = dimnames(v);
    nd    = dimsize(v);

    # Add extra dimension for sims
    dims = (dims...,("sim",)...)
    nd   = (nd...,(ns,)...)

    time = ds["time"][:]*1e-3

    # Define new ensemble arrays based on dimensions
    var_out = fill(NaN, nd...)

    # Close NetCDF file
    close(ds) 

    return ens 
end 

function ensemble_get_var_slice!(ens,vout::String,vin::String;time_slice=nothing,
                                 var_dim=nothing)

    # Get number of simulations
    ns = size(ens.info,1);

    # Generate output variable
    var_out = fill(NaN,ns);

    # Get variable for each ensemble member
    for k = 1:ns

        # Load variable from ensemble object 
        time = ens.v["time"][k]
        var  = ens.v[vin][k] 

        # Get time index of interest
        if time_slice == nothing
            time_now = maximum(time)
        else
            time_now = time_slice 
        end 

        tmp = findmin(abs.(time .- time_now))
        nt  = tmp[2]
        
        # Populate output variable
        var_out[k] = var[nt];

    end 

    if var_dim == nothing
        out = var_out 
    else 
        out = [var_dim var_out]
    end

    ens.v[vout] = out 

    return

end

function load_time_var(path,varname)
    
    if !isfile(path)
        return ([NaN,NaN],[NaN,NaN])
    end 

    # First load variable from reference sim
    ds = NCDataset(path,"r")

    # Get time variable
    time = ds["time"][:]*1e-3
    
    # Get variable itself
    if !haskey(ds,varname)
        error("load_var:: Error: variable not found in file.")
    else 
        var = ds[varname][:];
    end 

    # Close NetCDF file
    close(ds) 

    return (time,var)
end

#### Functions related to testing specific things 

function ensemble_check(path; vars = nothing)

    # Load ensemble information
    ens = ensemble_def(path);

    # Initially only loading standard PD comparison statistics variables
    var_names = ["time","rmse_H","rmse_zsrf","rmse_uxy","rmse_uxy_log"];

    # Add any other variables of interest from arguments
    if vars != nothing
        push!(var_names,vars);
    end 

    # Loop over all variable names of interest
    # (should be 1D time series, for now!)
    for vname in var_names
        ensemble_get_var!(ens,vname,"yelmo2D.nc");
    end

    # Generate a dataframe to hold output information in pretty format 
    df = DataFrames.DataFrame(runid = ens.info[!,:runid]);

    for vname in var_names
        #print(vname,size(ens.v[vname]),"\n")
        if ndims(ens.v[vname]) == 1
            v = [ens.v[vname][i][end] for i in 1:length(ens.v[vname])];
            DataFrames.insertcols!(df, vname => v )
        else
            print("ensemble_check:: Error: this function should be used with time series variables")
            print("vname = ", vname)
            return
        end
    end

    # Print information to screen, first about
    # ensemble (info) and then variables of interest.

    PrettyTables.pretty_table(ens.info, header = names(ens.info), crop = :horizontal)
    PrettyTables.pretty_table(df, header = names(df), crop = :horizontal)

    return ens
end