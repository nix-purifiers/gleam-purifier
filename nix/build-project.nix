# SPDX-License-Identifier: MIT
{
  lib,
  runCommand,
  fetchurl,
  nativeGleam,
  toolchain,
  purifier,
  gnutar,
  gzip,
}:
{
  src,
  lockFile ? src + "/gleam-purifier.lock.json",
  manifestLock ? src + "/manifest.toml",
  fetchers ? { },
  test ? true,
  target ? null,
  srcFilter ?
    path: type:
    !(builtins.elem (baseNameOf path) [
      ".git"
      ".gleam-purifier"
      "build"
      "result"
      "__pycache__"
    ]),
}:
let
  lock = purifier.checkLock (
    import ./read-lock.nix { inherit lib; } { inherit src lockFile manifestLock; }
  );
  environment = import ./environment.nix {
    inherit
      runCommand
      fetchurl
      lib
      nativeGleam
      toolchain
      purifier
      ;
  } { inherit lock fetchers; };
  source = lib.cleanSourceWith {
    inherit src;
    filter = srcFilter;
  };
  targetArgs = lib.optionalString (target != null) (" --target " + lib.escapeShellArg target);
  project = runCommand "purified-gleam-project" { nativeBuildInputs = [ toolchain ]; } ''
    export HOME="$TMPDIR/home" XDG_CACHE_HOME=${environment}/cache
    export SOURCE_DATE_EPOCH=1
    mkdir -p "$HOME" project "$out"
    cp -r ${source}/. project/
    chmod -R u+w project
    cd project
    cp ${manifestLock} manifest.toml
    export GLEAM_PURIFIER_PROJECT_ROOT="$PWD" GLEAM_PURIFIER_NATIVE_LOCKFILE="$PWD/manifest.toml"
    ${nativeGleam}/bin/gleam deps download
    # Native compiler cache metadata records source mtimes.
    find . -type f -exec touch -d @1 {} +
    ${nativeGleam}/bin/gleam build${targetArgs}
    ${lib.optionalString test "${nativeGleam}/bin/gleam test${targetArgs}"}
    # Incremental caches serialize unordered compiler maps; runtime outputs
    # live alongside them and remain intact.
    find build -type f \( -name '*.cache' -o -name '*.cache_meta' \) -delete
    cp -r . "$out/"
  '';
  release =
    assert lock.problems == [ ];
    runCommand "gleam-project-release"
      {
        nativeBuildInputs = [
          gnutar
          gzip
        ];
      }
      ''
        mkdir source "$out"
        cp -r ${source}/. source/
        chmod -R u+w source
        cp ${lockFile} source/gleam-purifier.lock.json
        cp ${manifestLock} source/manifest.toml
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -C source -cf - . | gzip -n > "$out/project.tar.gz"
      '';
in
{
  packages = {
    inherit project environment;
    default = project;
  };
  tests = project;
  inherit release;
  fetches = lock.entries;
}
