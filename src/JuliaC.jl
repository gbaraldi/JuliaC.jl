module JuliaC
using Pkg
using PackageCompiler

module JuliaConfig
    include("julia-config.jl")
end
Base.@kwdef mutable struct ImageRecipe
    # codegen options
    cpu_target::Union{String, Nothing} = nothing
    output_type::String = ""
    enable_trim::Bool = false
    add_ccallables::Bool = false
    # build options
    file::String = ""
    julia_args::Vector{String} = String[]
    project::String = ""
    img_path::String = ""
    verbose::Bool = false
end

Base.@kwdef mutable struct LinkRecipe
    image_recipe::ImageRecipe = ImageRecipe()
    outname::String = ""
    rpath::Union{String, Nothing} = nothing
end

Base.@kwdef mutable struct BundleRecipe
    link_recipe::LinkRecipe = LinkRecipe()
    output_dir::Union{String, Nothing} = nothing # if nothing, don't bundle
    libdir::String = "lib"
end

include("compiling.jl")
include("linking.jl")
include("bundling.jl")

export ImageRecipe, LinkRecipe, BundleRecipe
export compile_products, link_products, bundle_products


end # module JuliaC
