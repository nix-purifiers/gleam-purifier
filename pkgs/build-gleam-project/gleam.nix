# SPDX-License-Identifier: MIT
{ gleam }:
gleam.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    substituteInPlace compiler-core/src/paths.rs \
      --replace-fail 'self.root.join("manifest.toml")' \
        'if let (Ok(root), Ok(path)) = (std::env::var("GLEAM_PURIFIER_PROJECT_ROOT"), std::env::var("GLEAM_PURIFIER_NATIVE_LOCKFILE")) {
            if self.root.as_str() == root { return Utf8PathBuf::from(path); }
        }
        self.root.join("manifest.toml")' \
      --replace-fail 'self.build_directory().join("packages")' \
        'if let (Ok(root), Ok(path)) = (std::env::var("GLEAM_PURIFIER_PROJECT_ROOT"), std::env::var("GLEAM_PURIFIER_PACKAGE_DIR")) {
            if self.root.as_str() == root { return Utf8PathBuf::from(path); }
        }
        self.build_directory().join("packages")'
  '';
})
