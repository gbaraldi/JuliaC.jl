Run via Pkg app entrypoint:

```bash
# After ensuring ~/.julia/bin is on PATH and the app is installed
juliac --output-exe app_test_exe --experimental --verbose --bundle ./test_project --trim=safe --depot ~/.julia test_project/src/test.jl
```

Or via the module directly without installing the app:

```bash
julia --project -e "using JuliaC; JuliaC.@main(ARGS)" -- --output-exe app_test_exe --experimental --verbose --bundle ./test_project --trim=safe --depot ~/.julia test_project/src/test.jl
```
