#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile=${1:-server}

case "$profile" in
  local|server) ;;
  *) echo "usage: $0 [local|server]" >&2; exit 2 ;;
esac

sh "$repository_root/scripts/prepare-extensions.sh" --include-fake
export COURIERCMS_EXTENSIONS_PATH="$repository_root/.local/extensions"
export COURIERCMS_RELEASE_PROFILE="$profile"
cd "$repository_root/platform"
mix setup
exec mix phx.server
