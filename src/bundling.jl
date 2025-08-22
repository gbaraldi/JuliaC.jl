function bundle_products(recipe::BundleRecipe)

    if recipe.output_dir === nothing
        return
    end

    # Ensure the bundle output directory exists
    mkpath(recipe.output_dir)

    # Create julia subdirectory for bundled libraries under lib/
    ctx2 = PackageCompiler.create_pkg_context(recipe.link_recipe.image_recipe.project)
    stdlibs = unique(vcat(PackageCompiler.gather_stdlibs_project(ctx2), PackageCompiler.stdlibs_in_sysimage()))
    PackageCompiler.bundle_julia_libraries(recipe.output_dir, stdlibs)
    PackageCompiler.bundle_artifacts(ctx2, recipe.output_dir; include_lazy_artifacts=false) # Lazy artifacts

    # Determine where to place the built product within the bundle
    outname = recipe.link_recipe.outname
    is_exe = recipe.link_recipe.image_recipe.output_type == "--output-exe"
    libdir = recipe.libdir
    bindir = Sys.iswindows() ? libdir : "bin"
    dest_dir = is_exe ? joinpath(recipe.output_dir, bindir) : joinpath(recipe.output_dir, libdir)
    mkpath(dest_dir)
    dest = joinpath(dest_dir, basename(outname))
    if abspath(outname) != abspath(dest)
        mv(outname, dest; force=true)
        recipe.link_recipe.outname = dest
    end
    # Use relative rpath layout by default (handled by linking with empty rpath string)

    # On macOS, ensure expected dylib version symlinks exist (e.g., libjulia.1.12.dylib -> libjulia.1.12.0.dylib)
    if Sys.isapple()
        julia_dir = joinpath(recipe.output_dir, libdir, "julia")
        if isdir(julia_dir)
            # Map of base name to the symlink we want
            wanted = [
                ("libjulia", "1.12"),
                ("libjulia-internal", "1.12"),
            ]
            for (base, shortver) in wanted
                target = joinpath(julia_dir, string(base, ".", shortver, ".dylib"))
                if !isfile(target)
                    # Find the highest semantic versioned dylib for this base
                    candidates = filter(readdir(julia_dir)) do f
                        startswith(f, base * ".") && endswith(f, ".dylib")
                    end
                    if !isempty(candidates)
                        # Prefer the longest version string (most specific)
                        best = sort(candidates, by=length, rev=true)[1]
                        # Try symlink first; if it fails, copy as a fallback
                        ok = false
                        try
                            symlink(best, target)
                            ok = true
                        catch
                            ok = false
                        end
                        if !ok
                            try
                                cp(joinpath(julia_dir, best), target; force=true)
                            catch
                                # ignore if copy fails; test will fail and surface issue
                            end
                        end
                    end
                end
            end
        end
    end
end