
function compile_products(recipe::ImageRecipe)

    # Only strip IR / metadata if not `--trim=no`
    strip_args = String[]
    if recipe.enable_trim
        push!(strip_args, "--strip-ir")
        push!(strip_args, "--strip-metadata")
        # Detect trim support on 1.12 prereleases as well
        supports_trim = (VERSION.major > 1 || VERSION.minor >= 12) || (:trim in fieldnames(typeof(Base.JLOptions())))
        if supports_trim && recipe.trim_mode !== nothing
            # On 1.12 prereleases, --trim requires --experimental; harmless on stable
            push!(strip_args, "--experimental")
            push!(strip_args, "--trim=$(recipe.trim_mode)")
        end
    end
    if recipe.output_type == "--output-bc"
        image_arg = "--output-bc"
    else
        image_arg = "--output-o"
    end
    julia_cmd = `$(Base.julia_cmd(;cpu_target=recipe.cpu_target)) --startup-file=no --history-file=no`
    # Ensure the app project is instantiated and precompiled
    project_arg = recipe.project == "" ? Base.active_project() : recipe.project
    # Respect compile-time depot path if provided
    env_overrides = Dict{String,Any}()
    if recipe.depot_path !== nothing
        env_overrides["JULIA_DEPOT_PATH"] = recipe.depot_path
    end
    inst_cmd = addenv(`$(julia_cmd) --project=$project_arg -e "using Pkg; Pkg.instantiate(); Pkg.precompile()"`, env_overrides...)
    recipe.verbose && println("Running: $inst_cmd")
    if !success(pipeline(inst_cmd; stdout, stderr))
        println(stderr, "\nError encountered during instantiate/precompile of app project.")
        exit(1)
    end
    # Compile the Julia code
    if recipe.img_path == ""
        tmpdir = mktempdir()
        recipe.img_path = joinpath(tmpdir, "image.o.a")
    end
    project_arg = recipe.project == "" ? Base.active_project() : recipe.project
    # Build command incrementally to guarantee proper token separation
    cmd = julia_cmd
    cmd = `$cmd --project=$project_arg $(image_arg) $(recipe.img_path) --output-incremental=no`
    for a in strip_args
        cmd = `$cmd $a`
    end
    for a in recipe.julia_args
        cmd = `$cmd $a`
    end
    cmd = `$cmd $(joinpath(@__DIR__, "scripts", "juliac-buildscript.jl")) $(abspath(recipe.file)) $(recipe.output_type) $(string(recipe.add_ccallables))`
    # Threading plus optional depot path at compile-time
    cmd = addenv(cmd, "OPENBLAS_NUM_THREADS" => 1, "JULIA_NUM_THREADS" => 1)
    if recipe.depot_path !== nothing
        cmd = addenv(cmd, "JULIA_DEPOT_PATH" => recipe.depot_path)
    end
    recipe.verbose && println("Running: $cmd")
    if !success(pipeline(cmd; stdout, stderr))
        println(stderr, "\nFailed to compile $(recipe.file)")
        exit(1)
    end

    # If C shim sources are provided, compile them to objects for linking stage
    if !isempty(recipe.c_sources)
        compiler_cmd = JuliaC.get_compiler_cmd()
        # Ensure include flags are passed as separate tokens
        default_cflags = Base.shell_split(JuliaC.JuliaConfig.cflags(; framework=false))
        user_cflags = String[]
        for cf in recipe.cflags
            if startswith(cf, "-I") && cf != "-I"
                push!(user_cflags, cf)
            else
                append!(user_cflags, split(cf))
            end
        end
        cflags = isempty(user_cflags) ? default_cflags : vcat(default_cflags, user_cflags)
        new_cflags = ``
        for flag in cflags
            new_cflags = `$new_cflags $flag`
        end
        @show new_cflags
        for csrc in recipe.c_sources
            obj = replace(csrc, ".c" => ".o")
            try
                # Build command incrementally to avoid argument concatenation issues
                cmdc = compiler_cmd
                for cf in cflags
                    cmdc = `$cmdc $cf`
                end
                cmdc = `$cmdc -c $(csrc) -o $(obj)`
                recipe.verbose && println("Running: $cmdc")
                run(cmdc)
                push!(recipe.extra_objects, obj)
            catch e
                println("\nC shim compilation failed: ", e)
                exit(1)
            end
        end
    end
end

