using JuliaC

function parse_args(ARGS)
    image_recipe = ImageRecipe()
    link_recipe = LinkRecipe(image_recipe=image_recipe)
    bundle_recipe = BundleRecipe(link_recipe=link_recipe)

    help = findfirst(x->x == "--help", ARGS)
    if help !== nothing
        println(
            """
            Usage: julia juliac.jl [--output-exe | --output-lib | --output-sysimage | --output-bc | --output-o] <name> [options] <file.jl>
            --experimental --trim=<no,safe,unsafe,unsafe-warn>  Only output code statically determined to be reachable
            --compile-ccallable  Include all methods marked `@ccallable` in output
            --verbose            Request verbose output
            --project <dir>  Use the given project directory for the app
            --bundle <dir>  Bundle the app into the given directory
            """)
        exit(0)
    end
    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        # image args
        if arg == "--output-exe" || arg == "--output-lib" || arg == "--output-sysimage" || arg == "--output-o" || arg == "--output-bc"
            image_recipe.output_type == "" || error("Multiple output types specified")
            image_recipe.output_type = arg
            i == length(ARGS) && error("Output specifier requires an argument")
            link_recipe.outname = ARGS[i+1]
            i += 1
        elseif startswith(arg, "--trim")
            image_recipe.enable_trim = arg != "--trim=no"
            push!(image_recipe.julia_args, arg) # forwarded arg
        elseif arg == "--experimental"
            push!(image_recipe.julia_args, arg) # forwarded arg
        elseif arg == "--compile-ccallable"
            image_recipe.add_ccallables = true
        elseif arg == "--project"
            i == length(ARGS) && error("App project directory requires an argument")
            image_recipe.project = ARGS[i+1]
            i += 1
        # link args
        # bundle args
        elseif arg == "--bundle"
            i == length(ARGS) && error("Bundle directory requires an argument")
            bundle_recipe.output_dir = ARGS[i+1]
            i += 1
    
        elseif arg == "--verbose"
            image_recipe.verbose = true
        else
            if arg[1] == '-' || image_recipe.file != ""
                println("Unexpected argument `$arg`")
                exit(1)
            end
            image_recipe.file = arg
        end
        i += 1
    end

    link_recipe.outname == "" && error("No output file specified")
    image_recipe.file == "" && error("No input file specified")
    image_recipe.cpu_target = get(ENV, "JULIA_CPU_TARGET", nothing)

    if bundle_recipe.output_dir !== nothing
        link_recipe.rpath = bundle_recipe.libdir
    end


    return image_recipe, link_recipe, bundle_recipe
end



function @main(ARGS)
    recipes = parse_args(ARGS)
    compile_products(recipes[1])
    link_products(recipes[2])
    bundle_products(recipes[3])
end

main()


