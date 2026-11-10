# SPDX-License-Identifier: MIT
{ pkgs, self }:
let
  project = pkgs.gleam-purifier.buildGleamProject { src = ../examples/minimal; };
in
{
  editor = import ./editor.nix {
    inherit pkgs;
    environment = project.packages.environment;
  };
  cli = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  environment = project.packages.environment;
  project = project.tests;
  erlang =
    (pkgs.gleam-purifier.buildGleamProject {
      src = ../examples/minimal;
      target = "erlang";
    }).tests;
  release = project.release;
  javascript-projections = import ./javascript-projections.nix { inherit pkgs; };
}
