# SPDX-License-Identifier: MIT
{
  projectRoot,
  src,
  module,
  version ? "1.0.0",
}:
let
  f = builtins.getFlake projectRoot;
  pkgs = import f.inputs.nixpkgs {
    system = builtins.currentSystem;
    overlays = [ f.overlays.default ];
  };
  built = pkgs.gleam-purifier.buildGleamProject {
    src = /. + src;
    javascriptModules.probe = module;
    javascriptWebjars.probe = {
      artifactId = "probe";
      inherit version;
    };
  };
in
built.javascript.probe
