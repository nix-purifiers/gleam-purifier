# SPDX-License-Identifier: MIT
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  nix,
  gh,
  nativeGleam,
  toolchain,
  cacert,
  nixpkgsSrc,
  purifierSrc,
}:
stdenvNoCC.mkDerivation {
  pname = "gleam-purifier";
  version = "0.1.0";
  src = ../.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p "$out/bin" "$out/lib/gleam-purifier"
    cp -r gleam_purifier nix "$out/lib/gleam-purifier/"
    install -m755 bin/gleam-purifier "$out/bin/gleam-purifier"
    substituteInPlace "$out/lib/gleam-purifier/nix/realize.nix" \
      --replace-fail '@nixpkgs@' '${nixpkgsSrc}' \
      --replace-fail '@purifier@' '${purifierSrc}' \
      --replace-fail '@runtime@' "$out"
    wrapProgram "$out/bin/gleam-purifier" \
      --prefix PATH : ${
        lib.makeBinPath [
          python3
          nix
          gh
          toolchain
        ]
      } \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set GLEAM_PURIFIER_GLEAM ${nativeGleam}/bin/gleam \
      --set GLEAM_PURIFIER_GLEAM_VERSION ${nativeGleam.version}
    makeWrapper "$out/bin/gleam-purifier" "$out/bin/gleam" --add-flags 'native --'
    for program in ${toolchain}/bin/*; do
      name=$(basename "$program")
      if [ ! -e "$out/bin/$name" ]; then ln -s "$program" "$out/bin/$name"; fi
    done
  '';
  meta = {
    description = "Native Gleam workflow with locked Nix-resolved dependencies";
    homepage = "https://nix-purifiers.github.io/";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "gleam-purifier";
  };
}
