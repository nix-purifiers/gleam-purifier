# SPDX-License-Identifier: MIT
{ pkgs, environment }:
pkgs.runCommand "gleam-editor-check"
  {
    nativeBuildInputs = [
      pkgs.gleam-purifier.toolchain
      pkgs.python3
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CACHE_HOME=${environment}/cache
    mkdir -p "$HOME" project "$TMPDIR/packages"
    cp -r ${../examples/minimal}/. project/
    chmod -R u+w project
    for source in ${environment}/packages/*; do
      if [ -d "$source" ]; then ln -s "$source" "$TMPDIR/packages/$(basename "$source")";
      else cp "$source" "$TMPDIR/packages/"; chmod u+w "$TMPDIR/packages/$(basename "$source")"; fi
    done
    export GLEAM_PURIFIER_PACKAGE_DIR="$TMPDIR/packages"
    export GLEAM_PURIFIER_PROJECT_ROOT="$PWD/project"
    export GLEAM_PURIFIER_NATIVE_LOCKFILE="$PWD/project/manifest.toml"
    python3 ${./editor.py} "$PWD/project" ${pkgs.gleam-purifier.nativeGleam}/bin/gleam lsp
    touch "$out"
  ''
