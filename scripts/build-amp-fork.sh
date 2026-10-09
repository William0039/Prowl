#!/usr/bin/env bash
set -euo pipefail

root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
if [[ "$(git -C "$root" branch --show-current)" != "local/amp-build-workflow" ]]; then
  echo "Run this script from the local/amp-build-workflow checkout." >&2
  exit 1
fi
if [[ -n "$(git -C "$root" status --porcelain)" ]]; then
  echo "Commit or preserve pending changes before building an update." >&2
  exit 1
fi

version="${1:-$(gh release view --repo onevcat/Prowl --json tagName --jq .tagName)}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Expected an official release tag such as v2026.10.6." >&2
  exit 1
fi

fix="$(git -C "$root" rev-parse fix/amp-state-detection)"
maintenance="$(git -C "$root" rev-parse HEAD)"
patch_commits=(70bc261a8cbfb4f68eb2a1c28c254b9727785ede)
stamp="${version}-$(date +%Y%m%d-%H%M%S)"
worktree="$(dirname "$root")/Prowl-amp-build-$stamp"
git -C "$root" fetch upstream "refs/tags/$version:refs/tags/$version"
git -C "$root" worktree add --detach "$worktree" "$version"
if ! git -C "$worktree" cherry-pick "${patch_commits[@]}"; then
  echo "Patch application stopped. Resolve the retained worktree: $worktree" >&2
  echo "No installed application was changed." >&2
  exit 1
fi
git -C "$root" diff "$fix" "$maintenance" -- \
  App/Sources/Clients/Updates/UpdaterClient.swift scripts/build-amp-fork.sh docs/local-amp-fork.md \
  | git -C "$worktree" apply --index
git -C "$worktree" commit -m "chore(local): apply isolated Amp fork build tooling"

export PATH="/opt/homebrew/opt/python@3.13/libexec/bin:$(dirname "$(xcrun --find swift-format)"):$PATH"
python3 -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ is required"'
if (( BASH_VERSINFO[0] < 4 )); then
  echo "Bash 4+ is required by the upstream Makefile." >&2
  exit 1
fi
git -C "$worktree" submodule update --init --recursive --depth 1
mise trust "$worktree/mise.toml"
make -C "$worktree" check test build-app SHELL="$(command -v bash)" FORMAT_BASE_REF="$version"

settings="$(xcodebuild -workspace "$worktree/Prowl.xcworkspace" -scheme Prowl -configuration Debug -showBuildSettings -json)"
source_app="$(printf '%s' "$settings" | jq -er '.[0].buildSettings | .BUILT_PRODUCTS_DIR + "/" + .FULL_PRODUCT_NAME')"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")"
if [[ "$bundle_id" != "com.onevcat.prowl.debug" ]]; then
  echo "Refusing to install a non-Debug application." >&2
  exit 1
fi

base="$HOME/Library/Application Support/Prowl-Amp-Fork"
destination="$base/versions/$stamp/Prowl Debug.app"
mkdir -p "$(dirname "$destination")"
ditto "$source_app" "$destination"
codesign --verify --deep --strict "$destination"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$destination/Contents/Info.plist")"
launcher="$(dirname "$destination")/launch.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'export PROWL_DEBUG_DATA_DIRECTORY=%q\n' "$base/runtime"
  printf 'export PROWL_CLI_SOCKET=%q\n' "/private/tmp/prowl-amp-$UID.sock"
  printf 'export PATH=%q:"$PATH"\n' "$destination/Contents/Resources/prowl-cli"
  printf 'exec %q\n' "$destination/Contents/MacOS/$executable"
} > "$launcher"
chmod +x "$launcher"
printf '\nValidated build saved to: %s\nLaunch with: %s\n' "$destination" "$launcher"
echo "Previous versions and the official Prowl application were left untouched."
