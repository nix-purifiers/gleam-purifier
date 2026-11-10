{
  pkgs,
  src1 ? ./fixtures/otp-hello,
  src2 ? ./fixtures/otp-hola,
}:
let
  build =
    src:
    pkgs.gleam-purifier.buildGleamProject {
      inherit src;
      otpApplications = [ "locked_gleam" ];
    };
  first = build src1;
  second = build src2;
  erlang = first.projections.erlang.otp.runtime;
  elixir = pkgs.beam.packages.erlang_28.elixir;
  version = built: marker: {
    inherit marker;
    catalog = built.projections.erlang.otp.catalog;
    library = built.projections.erlang.otp.applicationRoot;
    web = built.projections.erlang.web.documentRoot;
    jar = built.projections.erlang.java-resources.classPath;
  };
  spec = pkgs.writeText "gleam-otp-consumer-spec.json" (
    builtins.toJSON {
      erlang = toString erlang;
      elixir = toString elixir;
      versions = [
        (version first "HELLO")
        (version second "HOLA")
      ];
    }
  );
in

pkgs.runCommand "gleam-compiled-otp-cross-language-consumers"
  {
    nativeBuildInputs = [
      pkgs.python3
      erlang
      elixir
      pkgs.jdk25
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    cp ${./otp/consumer.erl} otp_consumer.erl
    cp ${./otp/Resources.java} Resources.java
    python3 ${./otp/consumers.py} ${spec} "$out"
  ''
