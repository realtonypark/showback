#!/bin/bash
set -euo pipefail

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
prefix=${1:-$HOME}
if [[ "$prefix" != /* || "$prefix" == / || $# -gt 1 ]]; then
  echo "Usage: ./scripts/install.sh [/absolute/install-prefix]" >&2
  exit 1
fi
if [[ $(uname -m) == x86_64 && $(sysctl -n hw.optional.avx2_0 2>/dev/null || true) != 1 ]]; then
  echo "The local speech runtime needs AVX2 on Intel. On Apple Silicon, use a native terminal." >&2
  exit 1
fi

app_parent="$prefix/Applications"
bin_parent="$prefix/.local/bin"
skill_parent="$prefix/.agents/skills"
app="$app_parent/Showback.app"
entry="$bin_parent/showback"
skill="$skill_parent/showback"
mkdir -p "$app_parent" "$bin_parent" "$skill_parent"
stage=$(mktemp -d "$app_parent/.showback-install.XXXXXX")
committed=0
app_changed=0
entry_changed=0
skill_changed=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ $committed == 0 ]]; then
    if [[ $skill_changed == 1 ]]; then rm -rf "$skill"; fi
    if [[ $entry_changed == 1 ]]; then rm -f "$entry"; fi
    if [[ $app_changed == 1 ]]; then rm -rf "$app"; fi
    if [[ -e "$stage/previous-app" ]]; then mv "$stage/previous-app" "$app"; fi
    if [[ -e "$stage/previous-entry" || -L "$stage/previous-entry" ]]; then mv "$stage/previous-entry" "$entry"; fi
    if [[ -e "$stage/previous-skill" ]]; then mv "$stage/previous-skill" "$skill"; fi
  fi
  rm -rf "$stage"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Building Showback"
cd "$repo"
taskpolicy -c utility swift build -c release -j 3
release_dir=$(swift build -c release --show-bin-path)
version=$(cat "$repo/Sources/ShowbackCore/Resources/version.txt")
minimum_os=$(swift package dump-package | plutil -extract platforms.0.version raw -o - -)
staged_app="$stage/Showback.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$release_dir/showback" "$staged_app/Contents/MacOS/showback"
cp -R "$release_dir/Showback_ShowbackCore.bundle" "$staged_app/Contents/Resources/"
cp "$repo/LICENSE" "$staged_app/Contents/Resources/LICENSE"
cat > "$staged_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>showback</string>
<key>CFBundleIdentifier</key><string>dev.showback.app</string>
<key>CFBundleName</key><string>Showback</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>$minimum_os</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

"$staged_app/Contents/MacOS/showback" install-assets "$staged_app/Contents/Resources/Assets"
cp -R "$repo/skills/showback" "$stage/skill"
cat > "$stage/entry" <<'ENTRY'
#!/bin/sh
showback_prefix=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
exec "$showback_prefix/Applications/Showback.app/Contents/MacOS/showback" "$@"
ENTRY
chmod 755 "$stage/entry"
codesign --force --sign - "$staged_app"
codesign --verify --strict "$staged_app"

if [[ -e "$app" ]]; then mv "$app" "$stage/previous-app"; fi
mv "$staged_app" "$app"
app_changed=1
if [[ -e "$entry" || -L "$entry" ]]; then mv "$entry" "$stage/previous-entry"; fi
mv "$stage/entry" "$entry"
entry_changed=1
if [[ -e "$skill" ]]; then mv "$skill" "$stage/previous-skill"; fi
mv "$stage/skill" "$skill"
skill_changed=1

env -u SHOWBACK_ASSETS "$entry" doctor
committed=1
echo "Installed: $entry"
echo "Skill: $skill"
