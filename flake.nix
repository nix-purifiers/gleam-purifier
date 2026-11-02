# SPDX-License-Identifier: MIT
{
  description = "Locked, Nix-resolved dependencies for Gleam";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.purifier = {
    url = "github:nix-purifiers/purifier";
    flake = false;
  };
  outputs =
    {
      self,
      nixpkgs,
      purifier,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = nixpkgs.lib.genAttrs systems;
      overlay = final: prev: {
        gleam-purifier = final.lib.makeScope final.newScope (scope: {
          nativeGleam = scope.callPackage ./nix/gleam.nix { };
          toolchain = final.buildEnv {
            name = "gleam-purifier-toolchain";
            paths = [
              scope.nativeGleam
              final.beamPackages.erlang
              final.nodejs
              final.git
              final.coreutils
            ];
          };
          cli = scope.callPackage ./nix/cli.nix {
            nixpkgsSrc = nixpkgs;
            purifierSrc = purifier;
          };
          buildGleamProject = scope.callPackage ./nix/build-project.nix {
            purifier = import (purifier + "/nix/lib") { inherit (final) lib; };
          };
        });
      };
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
    in
    {
      overlays.default = overlay;
      packages = forAll (system: {
        native = (pkgsFor system).gleam-purifier.nativeGleam;
        default = (pkgsFor system).gleam-purifier.cli;
        cli = self.packages.${system}.default;
      });
      lib.gleam-purifier.readLock = import ./nix/read-lock.nix { lib = nixpkgs.lib; };
      apps = forAll (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/gleam-purifier";
          meta.description = "Lock and prefetch Gleam dependencies";
        };
      });
      checks = forAll (
        system:
        import ./tests {
          pkgs = pkgsFor system;
          inherit self;
        }
      );
      formatter = forAll (system: (pkgsFor system).nixfmt-tree);
    };
}
