function bundle_products(recipe::BundleRecipe)

    if recipe.output_dir === nothing
        return
    end

    if !isdir(recipe.output_dir)
        error("App project directory does not exist: $(recipe.output_dir)")
    end

    # Create julia subdirectory for bundled libraries
    ctx2 = PackageCompiler.create_pkg_context(recipe.link_recipe.image_recipe.project)
    stdlibs = unique(vcat(PackageCompiler.gather_stdlibs_project(ctx2), PackageCompiler.stdlibs_in_sysimage()))
    PackageCompiler.bundle_julia_libraries(recipe.output_dir, stdlibs)
    PackageCompiler.bundle_artifacts(ctx2, recipe.output_dir; include_lazy_artifacts=false) # Lazy artifacts
    # Move the output library into the output_dir if it is not already there
    outname = recipe.link_recipe.outname
    dest = isabspath(outname) ? joinpath(recipe.output_dir, basename(outname)) : joinpath(recipe.output_dir, outname)
    if abspath(outname) != abspath(dest)
        mkpath(dirname(dest))
        mv(outname, dest; force=true)
        recipe.link_recipe.outname = dest
    end
end