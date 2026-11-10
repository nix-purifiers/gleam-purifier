# SPDX-License-Identifier: MIT
{
  lib,
  runCommand,
  fetchurl,
  nativeGleam,
  toolchain,
  purifier,
  gnutar,
  gzip,
  python3,
  esbuild,
}:
{
  src,
  lockFile ? src + "/gleam-purifier.lock.json",
  manifestLock ? src + "/manifest.toml",
  fetchers ? { },
  test ? true,
  target ? null,
  javascriptModules ? { },
  javascriptWebjars ? { },
  srcFilter ?
    path: type:
    !(builtins.elem (baseNameOf path) [
      ".git"
      ".gleam-purifier"
      "build"
      "result"
      "__pycache__"
    ]),
}:
let
  lock = purifier.checkLock (
    import ./read-lock.nix { inherit lib; } { inherit src lockFile manifestLock; }
  );
  environment = import ./environment.nix {
    inherit
      runCommand
      fetchurl
      lib
      nativeGleam
      toolchain
      purifier
      ;
  } { inherit lock fetchers; };
  source = lib.cleanSourceWith {
    inherit src;
    filter = srcFilter;
  };
  javascriptSelected = javascriptModules != { };
  validCoordinate =
    value:
    builtins.isString value
    && builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*" value != null
    && !(lib.hasInfix ".." value);
  validWebjar =
    value:
    builtins.isAttrs value
    && (
      builtins.attrNames value == [
        "artifactId"
        "version"
      ]
      ||
        builtins.attrNames value == [
          "artifactId"
          "groupId"
          "version"
        ]
    )
    && builtins.all validCoordinate (builtins.attrValues value);
  effectiveTarget = if javascriptSelected then "javascript" else target;
  targetArgs = lib.optionalString (effectiveTarget != null) (
    " --target " + lib.escapeShellArg effectiveTarget
  );
  rawProject = runCommand "purified-gleam-project" { nativeBuildInputs = [ toolchain ]; } ''
    export HOME="$TMPDIR/home" XDG_CACHE_HOME=${environment}/cache
    export SOURCE_DATE_EPOCH=1
    mkdir -p "$HOME" project "$out"
    cp -r ${source}/. project/
    chmod -R u+w project
    cd project
    cp ${manifestLock} manifest.toml
    export GLEAM_PURIFIER_PROJECT_ROOT="$PWD" GLEAM_PURIFIER_NATIVE_LOCKFILE="$PWD/manifest.toml"
    ${nativeGleam}/bin/gleam deps download
    # Native compiler cache metadata records source mtimes.
    find . -type f -exec touch -d @1 {} +
    ${nativeGleam}/bin/gleam build${targetArgs}
    ${lib.optionalString test "${nativeGleam}/bin/gleam test${targetArgs}"}
    # Incremental caches serialize unordered compiler maps; runtime outputs
    # live alongside them and remain intact.
    find build -type f \( -name '*.cache' -o -name '*.cache_meta' \) -delete
    cp -r . "$out/"
    ${lib.optionalString javascriptSelected ''
      ${nativeGleam}/bin/gleam export package-information --out "$out/javascript-package.json"
      ${nativeGleam}/bin/gleam export package-interface --out "$out/javascript-interface.json"
      ${nativeGleam}/bin/gleam --version > "$out/javascript-compiler-version.txt"
      node --version > "$out/javascript-node-version.txt"
    ''}
  '';
  selectedJavascript = lib.mapAttrs (
    label: module:
    runCommand "gleam-javascript-${label}"
      {
        outputs = [
          "out"
          "proof"
        ];
        nativeBuildInputs = [
          python3
          esbuild
        ];
        spec = builtins.toJSON {
          inherit module;
          producer = toString rawProject;
          compilerPath = toString nativeGleam;
          nodePath = "${toolchain}/bin/node";
          webjar = javascriptWebjars.${label} or null;
        };
        passAsFile = [ "spec" ];
      }
      ''
        python3 ${./javascript-output.py} "$specPath" "$out" "$proof" ${esbuild}/bin/esbuild
      ''
  ) javascriptModules;
  javascript = lib.mapAttrs (
    label: artifact:
    artifact
    // {
      projections =
        (purifier.resourceProjections {
          producer = artifact;
          roots."." = ".";
          inherit runCommand python3;
        })
        // lib.optionalAttrs (javascriptWebjars ? ${label}) (
          purifier.webjarProjections (
            javascriptWebjars.${label}
            // {
              producer = artifact;
              assets = artifact;
              inherit runCommand python3;
            }
          )
        );
    }
  ) selectedJavascript;
  projections = lib.mapAttrs (_: artifact: artifact.projections) javascript;
  project = rawProject // {
    inherit projections;
  };
  release =
    assert lock.problems == [ ];
    runCommand "gleam-project-release"
      {
        nativeBuildInputs = [
          gnutar
          gzip
        ];
      }
      ''
        mkdir source "$out"
        cp -r ${source}/. source/
        chmod -R u+w source
        cp ${lockFile} source/gleam-purifier.lock.json
        cp ${manifestLock} source/manifest.toml
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -C source -cf - . | gzip -n > "$out/project.tar.gz"
      '';
in
assert lib.assertMsg (
  builtins.isAttrs javascriptModules
  && builtins.all (
    label:
    builtins.match "[A-Za-z_][A-Za-z0-9_-]*" label != null
    && builtins.isString javascriptModules.${label}
    && builtins.match "[a-z][a-z0-9_]*(/[a-z][a-z0-9_]*)*" javascriptModules.${label} != null
  ) (builtins.attrNames javascriptModules)
) "gleam-purifier: javascriptModules must select named Gleam modules";
assert lib.assertMsg (
  !javascriptSelected || target == null || target == "javascript"
) "gleam-purifier: javascriptModules requires the JavaScript target";
assert lib.assertMsg (
  builtins.isAttrs javascriptWebjars
  && builtins.all (
    label: builtins.hasAttr label javascriptModules && validWebjar javascriptWebjars.${label}
  ) (builtins.attrNames javascriptWebjars)
) "gleam-purifier: javascriptWebjars must name selected JavaScript modules";
{
  packages = {
    inherit project environment;
    default = project;
  };
  tests = project;
  inherit release javascript projections;
  fetches = lock.entries;
}
