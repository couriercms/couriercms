#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package_directory="$repository_root/.local/packages"
package_path="$package_directory/couriercms-connector-0.1.0.zip"
mkdir -p "$package_directory"
rm -f "$package_path"
cd "$repository_root/connectors"
zip -qr "$package_path" wordpress
printf 'Built %s\n' "$package_path"
