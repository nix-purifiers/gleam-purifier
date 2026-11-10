{ pkgs }:
let
  build = pkgs.gleam-purifier.buildGleamProject;
  src = ./fixtures/otp-hello;
  refused =
    args: !(builtins.tryEval (build ({ inherit src; } // args)).packages.default.drvPath).success;
  cross =
    if pkgs.stdenv.buildPlatform.isAarch64 then
      pkgs.pkgsCross.gnu64
    else
      pkgs.pkgsCross.aarch64-multiplatform;
  crossBuild = build.override { stdenv = cross.stdenv; };
in
assert builtins.all refused [
  { otpApplications = [ "nonexistent" ]; }
  {
    otpApplications = [
      "locked_gleam"
      "locked_gleam"
    ];
  }
  { otpApplications = [ "gleam_stdlib" ]; }
  { otpApplications = [ "../locked_gleam" ]; }
  {
    otpApplications = [ "locked_gleam" ];
    target = "javascript";
  }
  {
    otpApplications = [ "locked_gleam" ];
    javascriptModules.main = "locked_gleam";
  }
];
assert (build { inherit src; }).projections == { };
assert cross.stdenv.buildPlatform != cross.stdenv.hostPlatform;
assert
  !(builtins.tryEval
    (crossBuild {
      inherit src;
      otpApplications = [ "locked_gleam" ];
    }).packages.default.drvPath
  ).success;
true
