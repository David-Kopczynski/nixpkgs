#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update

nix-update nav
$(nix-build -A nav.mitmCache.updateScript)
