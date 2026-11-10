# SPDX-License-Identifier: MIT
{
  pkgs,
  src42 ? ../examples/javascript-projection,
  src43 ? ../examples/javascript-projection-v2,
}:
let
  build = pkgs.gleam-purifier.buildGleamProject;
  make =
    src: version:
    build {
      inherit src;
      javascriptModules.answer = "answer";
      javascriptWebjars.answer = {
        groupId = "org.webjars.gleam";
        artifactId = "projection-proof";
        inherit version;
      };
    };
  first = make src42 "1.0.0";
  second = make src43 "1.0.1";
  version = built: value: {
    artifact = toString built.javascript.answer;
    proof = toString built.javascript.answer.proof;
    web = toString built.projections.answer.web;
    maven = toString built.projections.answer.maven;
    inherit value;
  };
  rejects =
    args: !(builtins.tryEval (build ({ src = src42; } // args)).packages.project.drvPath).success;
in
assert (build { src = src42; }).projections == { };
assert rejects { javascriptModules.answer = "../answer"; };
assert rejects {
  javascriptModules.answer = "answer";
  target = "erlang";
};
assert rejects {
  javascriptWebjars.missing = {
    artifactId = "missing";
    version = "1.0.0";
  };
};
assert rejects {
  javascriptModules.answer = "answer";
  javascriptWebjars.answer = "invalid";
};
assert rejects {
  javascriptModules.answer = "answer";
  javascriptWebjars.answer = {
    artifactId = "../bad";
    version = "1.0.0";
  };
};
pkgs.runCommand "gleam-javascript-projection-consumers"
  {
    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.python3
      pkgs.jdk
      pkgs.gradle
    ];
    spec = builtins.toJSON {
      versions = [
        (version first 42)
        (version second 43)
      ];
    };
    passAsFile = [ "spec" ];
  }
  ''
    export HOME="$TMPDIR/home" GRADLE_USER_HOME="$TMPDIR/gradle-home"
    mkdir -p "$HOME"
    python3 ${./javascript}/proof.py "$specPath" "$out"
  ''
