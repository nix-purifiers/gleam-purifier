# SPDX-License-Identifier: MIT
{
  project,
  lockFile,
  manifestLock,
  target,
}:
let
  pkgs = import (/. + "@nixpkgs@") { };
  purifier = import (/. + "@purifier@/nix/lib") { inherit (pkgs) lib; };
  nativeGleam = pkgs.callPackage ./gleam.nix { };
  toolchain = pkgs.buildEnv {
    name = "gleam-purifier-toolchain";
    paths = [
      nativeGleam
      pkgs.beamPackages.erlang
      pkgs.nodejs
      pkgs.git
      pkgs.coreutils
    ];
  };
  args = {
    src = /. + project;
    lockFile = /. + lockFile;
    manifestLock = /. + manifestLock;
  };
  lock = import ../../lib-overlays/default/read-lock.nix { inherit (pkgs) lib; } args;
in
if target == "environment" then
  pkgs.callPackage ./environment.nix { inherit purifier nativeGleam toolchain; } { inherit lock; }
else if target == "runtime" then
  pkgs.runCommand "gleam-purifier-runtime" { } ''ln -s @runtime@ "$out"''
else if target == "release" then
  (pkgs.callPackage ./default.nix { inherit purifier nativeGleam toolchain; } args).release
else
  throw "gleam-purifier: unknown realization target ${target}"
