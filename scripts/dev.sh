#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sh "$repository_root/scripts/prepare-extensions.sh" --include-fake
export COURIERCMS_EXTENSIONS_PATH="$repository_root/.local/extensions"
cd "$repository_root/platform"
mix setup
exec mix phx.server
