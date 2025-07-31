
function get_rpath(recipe::LinkRecipe)
    if recipe.rpath !== nothing
        rpath_str = ""
        if Sys.isapple()
            rpath_str = "-Wl,-rpath,'@loader_path/'"
        elseif Sys.islinux()
            rpath_str = "-Wl,-rpath,'\$ORIGIN/'"
        else
            error("unimplemented")
        end
        private_libdir = joinpath(recipe.rpath, "julia")
        out_str = rpath_str * private_libdir * " " * rpath_str * recipe.rpath
        return out_str
    else
        return JuliaConfig.ldrpath()
    end
end

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

function link_products(recipe::LinkRecipe)
    image_recipe = recipe.image_recipe
    if image_recipe.output_type == "--output-o" || image_recipe.output_type == "--output-bc"
        mv(image_recipe.img_path, recipe.outname)
        return
    end
    if image_recipe.output_type == "--output-lib" || image_recipe.output_type == "--output-sysimage"
        of, ext = splitext(recipe.outname)
        soext = "." * Base.BinaryPlatforms.platform_dlext()
        if ext == ""
            recipe.outname = of * soext
        end
    end
    rpath_str = Base.shell_split(get_rpath(recipe))
    julia_libs = Base.shell_split(Base.isdebugbuild() ? "-ljulia-debug -ljulia-internal-debug" : "-ljulia -ljulia-internal")
    compiler_cmd = get_compiler_cmd()
    allflags = Base.shell_split(JuliaConfig.allflags(; framework=false, rpath=false))
    try
        if image_recipe.output_type == "--output-lib"
            cmd2 = `$(compiler_cmd) $(allflags) $(rpath_str) -o $(recipe.outname) -shared -Wl,$(Base.Linking.WHOLE_ARCHIVE) $(image_recipe.img_path)  -Wl,$(Base.Linking.NO_WHOLE_ARCHIVE)  $(julia_libs)`
        elseif image_recipe.output_type == "--output-sysimage"
            cmd2 = `$(compiler_cmd) $(allflags) $(rpath_str) -o $(recipe.outname) -shared -Wl,$(Base.Linking.WHOLE_ARCHIVE) $(image_recipe.img_path)  -Wl,$(Base.Linking.NO_WHOLE_ARCHIVE) $(julia_libs)`
        else
            cmd2 = `$(compiler_cmd) $(allflags) $(rpath_str) -o $(recipe.outname) -Wl,$(Base.Linking.WHOLE_ARCHIVE) $(image_recipe.img_path) -Wl,$(Base.Linking.NO_WHOLE_ARCHIVE)  $(julia_libs)`
        end
        image_recipe.verbose && println("Running: $cmd2")
        run(cmd2)
    catch e
        println("\nCompilation failed: ", e)
        exit(1)
    end
end

