#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
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
MIX_ENV=test mix deps.get
MIX_ENV=test mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test
