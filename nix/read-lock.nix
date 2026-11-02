# SPDX-License-Identifier: MIT
{ lib }:
{
  src,
  lockFile ? src + "/gleam-purifier.lock.json",
  manifestLock ? src + "/manifest.toml",
}:
let
  exists =
    builtins.pathExists lockFile
    && builtins.pathExists manifestLock
    && builtins.pathExists (src + "/gleam.toml");
  raw = if exists then builtins.fromJSON (builtins.readFile lockFile) else { };
  data = if builtins.isAttrs raw then raw else { };
  nativeText = if exists then builtins.readFile manifestLock else "";
  native = if exists then builtins.fromTOML nativeText else { };
  validPackage =
    p:
    builtins.isAttrs p
    && (p.source or null) == "hex"
    && (p.build_tools or null) == [ "gleam" ]
    && builtins.isString (p.name or null)
    && builtins.match "[a-z][a-z0-9_]*" p.name != null
    && builtins.isString (p.version or null)
    && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+([-+][A-Za-z0-9.-]+)?" p.version != null
    && builtins.isString (p.outer_checksum or null)
    && builtins.match "[A-Fa-f0-9]{64}" p.outer_checksum != null;
  packages = native.packages or null;
  sourcesOK =
    builtins.isList packages
    && builtins.all validPackage packages
    && builtins.isAttrs (native.requirements or null);
  expected = builtins.sort (a: b: a.path < b.path) (
    map (p: {
      path = "gleam/hex/hexpm/packages/${lib.toUpper p.outer_checksum}.tar";
      url = "https://repo.hex.pm/tarballs/${p.name}-${p.version}.tar";
      hash = builtins.convertHash {
        hash = p.outer_checksum;
        hashAlgo = "sha256";
        toHashFormat = "sri";
      };
      mirrors = [ ];
    }) packages
  );
  problems = map (message: "gleam-purifier: ${message}; run gleam-purifier lock") (
    if !exists then
      [ "missing native/companion lock or manifest" ]
    else if !builtins.isAttrs raw || (data.version or null) != 1 then
      [ "unsupported companion format" ]
    else if
      (data.contentHash or null)
      != builtins.hashString "sha256" (builtins.toJSON (removeAttrs data [ "contentHash" ]))
    then
      [ "companion contentHash mismatch" ]
    else if
      (data.configHash or null) != builtins.hashFile "sha256" (src + "/gleam.toml")
      || (data.config or null) != builtins.readFile (src + "/gleam.toml")
    then
      [ "project manifest changed" ]
    else if
      (data.nativeHash or null) != builtins.hashString "sha256" nativeText
      || (data.nativeLock or null) != nativeText
    then
      [ "native lock changed" ]
    else if !sourcesOK then
      [ "unsupported native source graph" ]
    else if
      (data.entries or null) != expected
      || builtins.length (lib.unique (map (p: p.name) packages)) != builtins.length packages
      || builtins.length (lib.unique (map (e: e.path) expected)) != builtins.length expected
    then
      [ "native source graph changed" ]
    else
      [ ]
  );
in
{
  purifier = "gleam-purifier";
  inherit problems data;
  entries = if problems == [ ] then expected else [ ];
  outputs =
    if problems == [ ] then
      {
        project = { };
        environment = { };
      }
    else
      { };
}
