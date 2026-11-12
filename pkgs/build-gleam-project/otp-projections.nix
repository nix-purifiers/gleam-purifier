{
  lib,
  stdenv,
  runCommand,
  python3,
  writeText,
  purifier,
  erlang,
}:
{
  producer,
  roots,
  applications,
  projectName,
}:
let
  spec = writeText "gleam-otp-selection.json" (
    builtins.toJSON {
      inherit roots applications;
      runtimeRoot = "${erlang}/lib/erlang";
    }
  );
  selected =
    runCommand "${projectName}-compiled-otp-applications"
      {
        nativeBuildInputs = [
          erlang
          python3
        ];
      }
      ''
        export ERL_LIBS="" ERL_FLAGS="" ERL_AFLAGS=""
        ${erlang}/bin/escript ${./otp-applications.escript} ${producer} ${spec} plan.json
        python3 ${./otp-copy.py} ${producer} plan.json "$out"
      '';
  resources = purifier.resourceProjections {
    producer = selected;
    roots."." = "lib";
    inherit runCommand python3;
  };
  otp = selected // {
    applicationRoot = "${selected}/lib";
    catalog = "${selected}/catalog.json";
    runtime = erlang;
  };
in
assert lib.assertMsg (
  roots == [ projectName ]
  && stdenv.hostPlatform.isLinux
  && stdenv.buildPlatform == stdenv.hostPlatform
  && lib.versionAtLeast erlang.version "27"
) "gleam-purifier: otpApplications selects the project application with a native Linux OTP27+ SDK";
{
  validated = true;
  package = selected // {
    projections = resources // {
      inherit otp;
    };
  };
  projections = resources // {
    inherit otp;
  };
}
