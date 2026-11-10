{ projectRoot, case }:
let
  f = builtins.getFlake projectRoot;
  pkgs = import f.inputs.nixpkgs {
    system = builtins.currentSystem;
    overlays = [ f.overlays.default ];
  };
in
(import ./otp-controls.nix {
  inherit pkgs;
  purifier = import (f.inputs.purifier + "/nix/lib") { inherit (pkgs) lib; };
}).${case}
