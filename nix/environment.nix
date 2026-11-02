# SPDX-License-Identifier: MIT
{
  runCommand,
  fetchurl,
  lib,
  nativeGleam,
  toolchain,
  purifier,
}:
{
  lock,
  fetchers ? { },
}:
let
  checked = purifier.checkLock lock;
  cache = purifier.tree (
    {
      name = "locked-gleam-hex-cache";
      entries = checked.entries;
      inherit runCommand fetchurl;
    }
    // fetchers
  );
in
runCommand "purified-gleam-environment" { nativeBuildInputs = [ toolchain ]; } ''
  mkdir -p "$out" project "$TMPDIR/home"
  export HOME="$TMPDIR/home" XDG_CACHE_HOME=${cache}
  ln -s ${cache} "$out/cache"
  cd project
  cp ${builtins.toFile "gleam.toml" checked.data.config} gleam.toml
  cp ${builtins.toFile "manifest.toml" checked.data.nativeLock} manifest.toml
  export GLEAM_PURIFIER_PROJECT_ROOT="$PWD" GLEAM_PURIFIER_NATIVE_LOCKFILE="$PWD/manifest.toml"
  ${nativeGleam}/bin/gleam deps download
  cp -r build/packages "$out/packages"
''
