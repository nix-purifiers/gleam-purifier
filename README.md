# gleam-purifier

Locked, Nix-resolved dependencies for Gleam.

## Quickstart

From a project with `gleam.toml`:

```sh
nix shell 'github:nix-purifiers/gleam-purifier'
gleam-purifier lock
gleam-purifier prefetch
gleam build
gleam test
```

The shell supplies a Gleam wrapper, Erlang and Node.js. Start your editor
from this shell to use the same dependencies with `gleam lsp`.
You can install the wrapper through your usual Nix configuration.

Commit `manifest.toml` and `gleam-purifier.lock.json`; ignore
`.gleam-purifier/` and the native `build/` directory. The wrapper uses a
private package directory backed by Nix-verified sources. Native compiled
outputs remain in `build/`.

Without a companion lock, the wrapper warns and runs ordinary, impure
Gleam. Invalid or stale locks fail with a repair instruction.

## Lock and update

```sh
gleam-purifier lock
gleam-purifier update gleam_stdlib
gleam-purifier update
```

Gleam resolves versions and writes its native lock. Nix fetches the Hex
archives using its checksums; native Gleam extracts and prepares them.
`lock` retains valid selections; `update NAME` updates that dependency,
and `update` updates the graph. Use the helper for dependency changes;
guarded `gleam add`, `remove`, `update` and `new` are rejected.

`prefetch` roots the dependency environment and SDK. Build, test, run and
editor commands execute in your working tree.

## External locks

```sh
gleam-purifier \
  --project ./app \
  --lockfile ./locks/companion.json \
  --tool-lockfile ./locks/manifest.toml \
  lock

export GLEAM_PURIFIER_LOCKFILE="$PWD/locks/companion.json"
export GLEAM_PURIFIER_TOOL_LOCKFILE="$PWD/locks/manifest.toml"
cd app
gleam build
```

The scoped Gleam SDK reads the selected native lock directly, preserving
the working tree's `manifest.toml`. `--native-lock` and
`GLEAM_PURIFIER_NATIVE_LOCKFILE` also select the native lock.

## Nix builds

The overlay exposes `pkgs.gleam-purifier.buildGleamProject`:

```nix
pkgs.gleam-purifier.buildGleamProject {
  src = ./.;
}
```

It returns `packages`, `tests`, `release` and `fetches`.
`packages.project` builds and tests the project;
`packages.environment` prepares dependencies. Output names and fetches
are available during evaluation without building. `lockFile` and
`manifestLock` select external locks, `target` selects `"erlang"` or
`"javascript"`, and `test = false` skips tests.

## JavaScript modules and resources

Select an actual project module to export its compiled JavaScript and complete
static `.mjs` import closure:

```nix
let
  built = pkgs.gleam-purifier.buildGleamProject {
    src = ./.;
    javascriptModules.answer = "answer";
    javascriptWebjars.answer = {
      groupId = "org.webjars.gleam";
      artifactId = "my-answer";
      version = "1.0.0"; # Must match the native Gleam package version.
    };
  };
in {
  modules = built.javascript.answer;
  documentRoot = built.projections.answer.web.documentRoot;
  classPath = built.projections.answer.java-resources.classPath;
  maven = built.projections.answer.maven;
}
```

The option selects the JavaScript target and rejects a conflicting explicit
Erlang target. The native compiler's package interface validates the module.
esbuild supplies import-graph metadata; its temporary bundle is discarded.
The exported modules retain their original compiler-produced bytes and relative
paths, including compiled locked dependencies. Unimported modules, tests,
compiler caches and unrelated source files are excluded.

The selected module tree is available through `javascript.<name>`. Its separate
`javascript.<name>.proof` output contains `selection.json`, recording the entrypoint, native manifest hash, compiler and
Node identities, actual native file origins and byte hashes. The resource views
provide an HTTP document root and Java resource JAR. Optional WebJars use the
published Maven/Ivy projector's immutable identity-qualified coordinates.

This supports closed static relative `.mjs` imports. Computed or dynamic imports,
bare/external imports and paths outside the compiler's JavaScript
runtime tree are rejected. CommonJS and other runtime assets are outside this contract.
The ordinary consumer tests use the pinned Node SDK; serving JavaScript bytes
does not establish browser compatibility or Erlang/OTP/NIF support.

Both options default to empty sets, preserving existing builds and outputs.
`tests/javascript-projections.sh`, called by the rebuild conformance entry,
performs fresh native captures, Node/HTTP/Java/Gradle consumption, producer
revision checks and invalid-selection controls on each native CI runner.

## Releases

```sh
gleam-purifier publish \
  --repo OWNER/REPOSITORY \
  --tag v0.1.0
```

This creates or updates a GitHub release with a deterministic Nix-built
source archive containing both locks. Authentication uses ordinary `gh`
configuration.

## Scope

Supports Hex packages built by Gleam, for Erlang and JavaScript targets.
Git/path dependencies and packages built by Mix or rebar3 are not yet
supported. The SDK targets x86_64-linux and aarch64-linux.

## Credits

The purifier idea was inspired by nixcloud's
[cargo (libnix)](https://github.com/nixcloud/cargo).
