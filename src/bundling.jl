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

    mv(recipe.link_recipe.outname, joinpath(recipe.output_dir, recipe.link_recipe.outname))
end