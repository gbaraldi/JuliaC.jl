
function compile_products(recipe::ImageRecipe)

    # Only strip IR / metadata if not `--trim=no`
    strip_args = String[]
    if recipe.enable_trim
        push!(strip_args, "--strip-ir")
        push!(strip_args, "--strip-metadata")
    end
    if recipe.output_type == "--output-bc"
        image_arg = "--output-bc"
    else
        image_arg = "--output-o"
    end
    julia_cmd = `$(Base.julia_cmd(;cpu_target=recipe.cpu_target)) --startup-file=no --history-file=no`
    # Compile the Julia code
    if recipe.img_path == ""
        tmpdir = mktempdir()
        recipe.img_path = joinpath(tmpdir, "image.o.a")
    end
    project_arg = recipe.project == "" ? Base.active_project() : recipe.project
    cmd = addenv(`$(julia_cmd) --project=$project_arg $(image_arg) $(recipe.img_path) --output-incremental=no $strip_args $(recipe.julia_args) $(joinpath(@__DIR__,"scripts/juliac-buildscript.jl")) $(abspath(recipe.file)) $(recipe.output_type) $(recipe.add_ccallables)`, "OPENBLAS_NUM_THREADS" => 1, "JULIA_NUM_THREADS" => 1)
    recipe.verbose && println("Running: $cmd")
    if !success(pipeline(cmd; stdout, stderr))
        println(stderr, "\nFailed to compile $(recipe.file)")
        exit(1)
    end
end

