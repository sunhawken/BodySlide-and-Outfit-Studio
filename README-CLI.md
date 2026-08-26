# BodySlide CLI

A Windows CMD frontend for the command-line build support in BodySlide and
Outfit Studio. It adds data discovery, XML inventory commands, validation,
dry-run output, and consistent exit codes.

Run `bodyslide-cli.cmd help` for syntax.

The tool expects an installed BodySlide data folder (normally
`CalienteTools\BodySlide`). Pass it with `--app-dir` or set
`BODYSLIDE_APP_DIR`. Builds use an upstream `BodySlide x64.exe`, `BodySlide.exe`,
or an explicit `--engine` path. The included MSVC-built engine is used
automatically when no installed engine is present. Inventory commands do not
launch the GUI.

Exit codes: `0` success, `1` unexpected error, `2` usage error, `3` missing or
invalid BodySlide data, `4` missing build engine. Native engine errors are
passed through.
