#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
platform_profile=${1:-both}

case "$platform_profile" in
  local) platform_profiles="local" ;;
  server) platform_profiles="server" ;;
  both) platform_profiles="server local" ;;
  *) echo "usage: $0 [local|server|both]" >&2; exit 2 ;;
esac

sh "$repository_root/scripts/prepare-extensions.sh" --include-fake

for project in sdk fake wordpress sanity; do
  (
    cd "$repository_root/extensions/$project"
    MIX_ENV=test mix deps.get
    MIX_ENV=test mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    MIX_ENV=test mix test
  )
done

export COURIERCMS_EXTENSIONS_PATH="$repository_root/.local/extensions"
cd "$repository_root/platform"
for profile in $platform_profiles; do
  COURIERCMS_RELEASE_PROFILE="$profile" MIX_ENV=test mix deps.get
  COURIERCMS_RELEASE_PROFILE="$profile" MIX_ENV=test mix format --check-formatted
  COURIERCMS_RELEASE_PROFILE="$profile" MIX_ENV=test mix compile --warnings-as-errors
  COURIERCMS_RELEASE_PROFILE="$profile" MIX_ENV=test mix test
  COURIERCMS_RELEASE_PROFILE="$profile" MIX_ENV=test mix test test/load/planner_load_test.exs --include load
done
