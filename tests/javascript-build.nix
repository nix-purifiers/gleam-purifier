# SPDX-License-Identifier: MIT
{
  projectRoot,
  src42,
  src43,
}:
let
  f = builtins.getFlake projectRoot;
  pkgs = import f.inputs.nixpkgs {
    system = builtins.currentSystem;
    overlays = [ f.overlays.default ];
  };
in
import ./javascript-projections.nix {
  inherit pkgs;
  src42 = /. + src42;
  src43 = /. + src43;
}
