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
