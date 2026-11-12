{ pkgs, purifier }:
let
  built = pkgs.gleam-purifier.buildGleamProject {
    src = ./fixtures/otp-hello;
    otpApplications = [ "locked_gleam" ];
  };
  producer = built.packages.project;
  erlang = pkgs.beamPackages.erlang;
  selection =
    producer: runtime:
    pkgs.callPackage ../pkgs/build-gleam-project/otp-projections.nix
      {
        inherit purifier;
        erlang = runtime;
      }
      {
        inherit producer;
        roots = [ "locked_gleam" ];
        projectName = "locked_gleam";
        applications = [
          {
            package = "locked_gleam";
            name = "locked_gleam";
            version = "0.1.0";
          }
          {
            package = "gleam_stdlib";
            name = "gleam_stdlib";
            version = "0.71.0";
          }
        ];
      };
  # Adversarial copies of a genuine native producer, using actual compiled bytes.
  mutated =
    name: command:
    pkgs.runCommand "gleam-otp-control-${name}" { } ''
      cp -rL ${producer} "$out"
      chmod -R u+w "$out"
      ${command}
    '';
  app = "$out/build/erlang-shipment/locked_gleam";
  dep = "$out/build/erlang-shipment/gleam_stdlib";
in
{
  wrongSdk = (selection producer pkgs.beam.packages.erlang_27.erlang).package;
  sdkCollision =
    (selection (mutated "sdk-module" ''
      cp ${erlang}/lib/erlang/lib/stdlib-*/ebin/sets.beam "${app}/ebin/"
    '') erlang).package;
  duplicateModule =
    (selection (mutated "duplicate-module" ''
      cp "${app}/ebin/locked_gleam.beam" "${dep}/ebin/"
    '') erlang).package;
  nativePayload =
    (selection (mutated "actual-native-payload" ''
      mkdir -p "${app}/priv"
      cp ${erlang}/lib/erlang/erts-*/bin/erl_child_setup "${app}/priv/helper"
    '') erlang).package;
}
