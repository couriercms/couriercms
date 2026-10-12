#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
install_path="$repository_root/.local/extensions"
include_fake=${1:-}

mkdir -p "$install_path"
find "$install_path" -maxdepth 1 -type f -name '*.couriercms' -delete

(
  cd "$repository_root/extensions/sdk"
  MIX_ENV=prod mix deps.get
  MIX_ENV=prod mix compile --warnings-as-errors
)

projects="content wordpress sanity"
if [ "$include_fake" = "--include-fake" ]; then
  projects="$projects fake"
fi

for project in $projects; do
  (
    cd "$repository_root/extensions/$project"
    MIX_ENV=prod mix deps.get --only prod
    MIX_ENV=prod mix couriercms.extension.build \
      --output "$install_path/couriercms_$project-0.1.0.couriercms"
  )
done

printf 'Installed CourierCMS extensions in %s\n' "$install_path"
