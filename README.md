# xreduce

## Description
The application `xreduce.d` is a wrapper (script) around the D compilers `dmd` and
`ldmd` that automatically compiles and executes unittests along with diagnostics
of accompaning coverage analysis results.

## Usage

`./xreduce -checkaction=context -allinst -unittest -cov -cov=ctfe -main -run test.d`

## TODO
- Extend `dmd` to emit warning-style diagnostics instead of `.lst` files via say
  `-cov=diagnose`.
- Extend `dmd`to support `-unitest=modules...` to speed up `dmd -i`.
