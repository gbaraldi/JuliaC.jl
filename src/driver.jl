# This file is a part of Julia. License is MIT: https://julialang.org/license

# Julia compiler wrapper script
# NOTE: The interface and location of this script are considered unstable/experimental

using LazyArtifacts

module JuliaConfig
    include("julia-config.jl")
end

Base.@kwdef mutable struct ImageRecipe
    # codegen options
    cpu_target::String = ""
    output_type::String = ""
    enable_trim::Bool = false
    add_ccallables::Bool = false
    # build options
    img_path::String = ""
    file::String = ""
    julia_args::Vector{String} = String[]
    project::String = ""
    output_dir::String = ""
    verbose::Bool = false
end

Base.@kwdef mutable struct DriverRecipe
    image_recipe::ImageRecipe = ImageRecipe()
    link_recipe::LinkRecipe = LinkRecipe()
    bundle_recipe::BundleRecipe = BundleRecipe()

end


function parse_args(ctx::DriverContext)
    help = findfirst(x->x == "--help", ARGS)
    if help !== nothing
        println(
            """
            Usage: julia juliac.jl [--output-exe | --output-lib | --output-sysimage | --output-bc | --output-o] <name> [options] <file.jl>
            --experimental --trim=<no,safe,unsafe,unsafe-warn>  Only output code statically determined to be reachable
            --compile-ccallable  Include all methods marked `@ccallable` in output
            --relative-rpath     Configure the library / executable to lookup all required libraries in an adjacent "julia/" folder
            --verbose            Request verbose output
            --app-project <dir>  Use the given project directory for the app
            """)
        exit(0)
    end
    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == arg == "--output-exe" || arg == "--output-lib" || arg == "--output-sysimage" || arg == "--output-o" || arg == "--output-bc"
            ctx.build_ctx.output_type == "" || error("Multiple output types specified")
            ctx.build_ctx.output_type = arg
            i == length(ARGS) && error("Output specifier requires an argument")
            ctx.build_ctx.outname = ARGS[i+1]
            i += 1
        elseif arg == "--compile-ccallable"
            ctx.build_ctx.add_ccallables = true
        elseif arg == "--verbose"
            ctx.build_ctx.verbose = true
        elseif arg == "--relative-rpath"
            ctx.relative_rpath = true
        elseif startswith(arg, "--trim")
            ctx.enable_trim = arg != "--trim=no"
            push!(ctx.build_ctx.julia_args, arg) # forwarded arg
        elseif arg == "--experimental"
            push!(ctx.build_ctx.julia_args, arg) # forwarded arg
        elseif arg == "--app-project"
            i == length(ARGS) && error("App project directory requires an argument")
            ctx.app_project = ARGS[i+1]
            i += 1
        else
            if arg[1] == '-' || ctx.file != ""
                println("Unexpected argument `$arg`")
                exit(1)
            end
            ctx.file = arg
        end

        i += 1
    end
    ctx.build_ctx.outname == "" && error("No output file specified")
    ctx.build_ctx.file == "" && error("No input file specified")
    if ctx.app_project != "" && ctx.build_ctx.output_type != "--output-lib" && ctx.build_ctx.output_type != "--output-exe"
        error("App project directory can only be used with --output-lib or --output-exe")
    end
    if ctx.app_project != ""
        ctx.relative_rpath = true # always use relative rpath for app project
        ctx.build_ctx.outname = joinpath(ctx.app_project, ctx.build_ctx.outname)
    end
    ctx.build_ctx.cpu_target = get(ENV, "JULIA_CPU_TARGET", "")
end


function precompile_env(ctx::DriverContext)
    # Pre-compile the environment
    # (otherwise obscure error messages will occur)
    
    project_arg = ctx.app_project == "" ? Base.active_project() : ctx.app_project
    cmd = addenv(`$(ctx.sysimg_ctx.julia_cmd_target) --project=$project_arg -e "using Pkg; Pkg.precompile()"`)
    ctx.sysimg_ctx.verbose && println("Running: $cmd")
    if !success(pipeline(cmd; stdout, stderr))
        println(stderr, "\nError encountered during pre-compilation of environment.")
        exit(1)
    end
end


function compile_products(ctx::BuildContext)

    # Only strip IR / metadata if not `--trim=no`
    strip_args = String[]
    if ctx.enable_trim
        push!(strip_args, "--strip-ir")
        push!(strip_args, "--strip-metadata")
    end
    if ctx.output_type == "--output-bc"
        image_arg = "--output-bc"
    else
        image_arg = "--output-o"
    end
    # Compile the Julia code
    project_arg = ctx.app_project == "" ? Base.active_project() : ctx.app_project
    cmd = addenv(`$(ctx.julia_cmd_target) --project=$project_arg $(image_arg) $(ctx.img_path) --output-incremental=no $strip_args $(ctx.julia_args) $(joinpath(@__DIR__,"juliac-buildscript.jl")) $(abspath(ctx.file)) $(ctx.output_type) $(ctx.add_ccallables)`, "OPENBLAS_NUM_THREADS" => 1, "JULIA_NUM_THREADS" => 1)
    ctx.verbose && println("Running: $cmd")
    if !success(pipeline(cmd; stdout, stderr))
        println(stderr, "\nFailed to compile $(ctx.file)")
        exit(1)
    end
end

Base.@kwdef mutable struct LinkingContext
    
end

Base.@kwdef mutable struct BundlingContext
    app_project::String = ""
end

Base.@kwdef mutable struct BuildContext
    julia_cmd::Cmd = `$(Base.julia_cmd()) --startup-file=no --history-file=no`
    julia_cmd_target::Cmd = ``
    cpu_target::String = ""
    output_type::String = ""
    outname::String = ""
    file::String = ""
    add_ccallables::Bool = false
    relative_rpath::Bool = false
    verbose::Bool = false
    cc::Cmd = ``
    absfile::String = ""
    cflags::Vector{String} = String[]
    allflags::Vector{String} = String[]
    tmpdir::String = ""
    img_path::String = ""
    bc_path::String = ""
    enable_trim::Bool = false
    julia_args::Vector{String} = String[]
    app_project::String = ""
end

# Copied from PackageCompiler
# https://github.com/JuliaLang/PackageCompiler.jl/blob/1c35331d8ef81494f054bbc71214811253101993/src/PackageCompiler.jl#L147-L190
function get_compiler_cmd(; cplusplus::Bool=false)
    cc = get(ENV, "JULIA_CC", nothing)
    path = nothing
    @static if Sys.iswindows()
        path = joinpath(LazyArtifacts.artifact"mingw-w64",
                        "extracted_files",
                        (Int==Int64 ? "mingw64" : "mingw32"),
                        "bin",
                        cplusplus ? "g++.exe" : "gcc.exe")
        compiler_cmd = `$path`
    end
    if cc !== nothing
        compiler_cmd = Cmd(Base.shell_split(cc))
        path = nothing
    elseif !Sys.iswindows()
        compilers_cpp = ("g++", "clang++")
        compilers_c = ("gcc", "clang")
        found_compiler = false
        if cplusplus
            for compiler in compilers_cpp
                if Sys.which(compiler) !== nothing
                    compiler_cmd = `$compiler`
                    found_compiler = true
                    break
                end
            end
        end
        if !found_compiler
            for compiler in compilers_c
                if Sys.which(compiler) !== nothing
                    compiler_cmd = `$compiler`
                    found_compiler = true
                    if cplusplus && !WARNED_CPP_COMPILER[]
                        @warn "could not find a c++ compiler (g++ or clang++), falling back to $compiler, this might cause link errors"
                        WARNED_CPP_COMPILER[] = true
                    end
                    break
                end
            end
        end
        found_compiler || error("could not find a compiler, looked for ",
            join(((cplusplus ? compilers_cpp : ())..., compilers_c...), ", ", " and "))
    end
    if path !== nothing
        compiler_cmd = addenv(compiler_cmd, "PATH" => string(ENV["PATH"], ";", dirname(path)))
    end
    return compiler_cmd
end

const WARNED_CPP_COMPILER = Ref(false)

function parse_args(ctx::BuildContext)
    help = findfirst(x->x == "--help", ARGS)
    if help !== nothing
        println(
            """
            Usage: julia juliac.jl [--output-exe | --output-lib | --output-sysimage | --output-bc | --output-o] <name> [options] <file.jl>
            --experimental --trim=<no,safe,unsafe,unsafe-warn>  Only output code statically determined to be reachable
            --compile-ccallable  Include all methods marked `@ccallable` in output
            --relative-rpath     Configure the library / executable to lookup all required libraries in an adjacent "julia/" folder
            --verbose            Request verbose output
            --app-project <dir>  Use the given project directory for the app
            """)
        exit(0)
    end
    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "--output-exe" || arg == "--output-lib" || arg == "--output-sysimage" || arg == "--output-o" || arg == "--output-bc"
            ctx.output_type == "" || error("Multiple output types specified")
            ctx.output_type = arg
            i == length(ARGS) && error("Output specifier requires an argument")
            ctx.outname = ARGS[i+1]
            i += 1
        elseif arg == "--compile-ccallable"
            ctx.add_ccallables = true
        elseif arg == "--verbose"
            ctx.verbose = true
        elseif arg == "--relative-rpath"
            ctx.relative_rpath = true
        elseif startswith(arg, "--trim")
            ctx.enable_trim = arg != "--trim=no"
            push!(ctx.julia_args, arg) # forwarded arg
        elseif arg == "--experimental"
            push!(ctx.julia_args, arg) # forwarded arg
        elseif arg == "--app-project"
            i == length(ARGS) && error("App project directory requires an argument")
            ctx.app_project = ARGS[i+1]
            i += 1
        else
            if arg[1] == '-' || ctx.file != ""
                println("Unexpected argument `$arg`")
                exit(1)
            end
            ctx.file = arg
        end

        i += 1
    end
    ctx.outname == "" && error("No output file specified")
    ctx.file == "" && error("No input file specified")
    if ctx.app_project != "" && ctx.output_type != "--output-lib" && ctx.output_type != "--output-exe"
        error("App project directory can only be used with --output-lib or --output-exe")
    end
    if ctx.app_project != ""
        ctx.relative_rpath = true # always use relative rpath for app project
        ctx.outname = joinpath(ctx.app_project, ctx.outname)
    end
end


function get_rpath(; relative::Bool = false, libdir=false)
    
    if relative
        str = libdir ? "/lib/" : ""
        if Sys.isapple()
            return "-Wl,-rpath,'@loader_path/$(str)julia/' -Wl,-rpath,'@loader_path/$(str)'"
        elseif Sys.islinux()
            return "-Wl,-rpath,'\$ORIGIN/$(str)julia/' -Wl,-rpath,'\$ORIGIN/$(str)'"
        else
            error("unimplemented")
        end
    else
        return JuliaConfig.ldrpath()
    end
end

function init_build_context(ctx::BuildContext)
    ctx.cc = get_compiler_cmd()
    cflags_str = JuliaConfig.cflags(; framework=false)
    ctx.cflags = Base.shell_split(cflags_str)
    allflags_str = JuliaConfig.allflags(; framework=false, rpath=false)
    ctx.allflags = Base.shell_split(allflags_str)
    ctx.tmpdir = mktempdir(cleanup=false)
    ctx.img_path = joinpath(ctx.tmpdir, "img.a")
    ctx.bc_path = joinpath(ctx.tmpdir, "img-bc.a")
    
    # Initialize julia_cmd_target with CPU target if specified
    cpu_target = get(ENV, "JULIA_CPU_TARGET", nothing)
    ctx.julia_cmd_target = `$(Base.julia_cmd(;cpu_target)) --startup-file=no --history-file=no`
end

function precompile_env(ctx::BuildContext)
    # Pre-compile the environment
    # (otherwise obscure error messages will occur)
    
    project_arg = ctx.app_project == "" ? Base.active_project() : ctx.app_project
    cmd = addenv(`$(ctx.julia_cmd_target) --project=$project_arg -e "using Pkg; Pkg.precompile()"`)
    ctx.verbose && println("Running: $cmd")
    if !success(pipeline(cmd; stdout, stderr))
        println(stderr, "\nError encountered during pre-compilation of environment.")
        exit(1)
    end
end

function compile_products(ctx::BuildContext)

    # Only strip IR / metadata if not `--trim=no`
    strip_args = String[]
    if ctx.enable_trim
        push!(strip_args, "--strip-ir")
        push!(strip_args, "--strip-metadata")
    end
    if ctx.output_type == "--output-bc"
        image_arg = "--output-bc"
    else
        image_arg = "--output-o"
    end
    # Compile the Julia code
    project_arg = ctx.app_project == "" ? Base.active_project() : ctx.app_project
    cmd = addenv(`$(ctx.julia_cmd_target) --project=$project_arg $(image_arg) $(ctx.img_path) --output-incremental=no $strip_args $(ctx.julia_args) $(joinpath(@__DIR__,"juliac-buildscript.jl")) $(abspath(ctx.file)) $(ctx.output_type) $(ctx.add_ccallables)`, "OPENBLAS_NUM_THREADS" => 1, "JULIA_NUM_THREADS" => 1)
    ctx.verbose && println("Running: $cmd")
    if !success(pipeline(cmd; stdout, stderr))
        println(stderr, "\nFailed to compile $(ctx.file)")
        exit(1)
    end
end

function link_products(ctx::BuildContext, app=false)
    if ctx.output_type == "--output-o" || ctx.output_type == "--output-bc"
        mv(ctx.img_path, ctx.outname)
        return
    end
    if ctx.output_type == "--output-lib" || ctx.output_type == "--output-sysimage"
        of, ext = splitext(ctx.outname)
        soext = "." * Base.BinaryPlatforms.platform_dlext()
        if ext == ""
            ctx.outname = of * soext
        end
    end
    rpath_str = Base.shell_split(get_rpath(; relative = ctx.relative_rpath, libdir=app))
    julia_libs = Base.shell_split(Base.isdebugbuild() ? "-ljulia-debug -ljulia-internal-debug" : "-ljulia -ljulia-internal")
    try
        if ctx.output_type == "--output-lib"
            cmd2 = `$(ctx.cc) $(ctx.allflags) $(rpath_str) -o $(ctx.outname) -shared -Wl,$(Base.Linking.WHOLE_ARCHIVE) $(ctx.img_path)  -Wl,$(Base.Linking.NO_WHOLE_ARCHIVE)  $(julia_libs)`
        elseif ctx.output_type == "--output-sysimage"
            cmd2 = `$(ctx.cc) $(ctx.allflags) $(rpath_str) -o $(ctx.outname) -shared -Wl,$(Base.Linking.WHOLE_ARCHIVE) $(ctx.img_path)  -Wl,$(Base.Linking.NO_WHOLE_ARCHIVE) $(julia_libs)`
        else
            cmd2 = `$(ctx.cc) $(ctx.allflags) $(rpath_str) -o $(ctx.outname) -Wl,$(Base.Linking.WHOLE_ARCHIVE) $(ctx.img_path) -Wl,$(Base.Linking.NO_WHOLE_ARCHIVE)  $(julia_libs)`
        end
        ctx.verbose && println("Running: $cmd2")
        run(cmd2)
    catch e
        println("\nCompilation failed: ", e)
        exit(1)
    end
end

function _main()
    ctx = BuildContext()
    parse_args(ctx)
    init_build_context(ctx)
    precompile_env(ctx)
    compile_products(ctx)
    if ctx.app_project != ""
        make_app(ctx)
    else
        link_products(ctx)
    end
end


using PackageCompiler

function make_app(ctx::BuildContext)
    # Bundle Julia libraries into the app project directory
    if !isdir(ctx.app_project)
        error("App project directory does not exist: $(ctx.app_project)")
    end
    
    # Create julia subdirectory for bundled libraries
    julia_dir = ctx.app_project
    ctx2 = PackageCompiler.create_pkg_context(julia_dir)
    stdlibs = unique(vcat(PackageCompiler.gather_stdlibs_project(ctx2), PackageCompiler.stdlibs_in_sysimage()))
    @show stdlibs
    PackageCompiler.bundle_julia_libraries(julia_dir, stdlibs)
    
    # Link the products normally
    link_products(ctx, true)
end

# Main execution
_main()

