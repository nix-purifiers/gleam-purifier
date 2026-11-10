#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build ".#checks.$system.project" --no-link
nix build ".#checks.$system.project" --no-link --rebuild
nix build ".#checks.$system.erlang" --no-link
nix build ".#checks.$system.erlang" --no-link --rebuild
nix build ".#checks.$system.release" --no-link
nix build ".#checks.$system.release" --no-link --rebuild
bash tests/javascript-projections.sh
