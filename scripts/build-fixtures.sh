#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/gui
for name in Desktop Browser; do
  if [[ $name == Desktop ]]; then app='Showback Fixture'; source=DesktopFixture; executable=ShowbackFixture; identifier=dev.showback.fixture; else app='Showback Browser Fixture'; source=BrowserFixture; executable=ShowbackBrowserFixture; identifier=dev.showback.browserfixture; fi
  destination=".local/gui/$app.app/Contents"
  mkdir -p "$destination/MacOS"
  swiftc -O "Tests/Fixtures/$source.swift" -o "$destination/MacOS/$executable"
  cat > "$destination/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$executable</string>
<key>CFBundleIdentifier</key><string>$identifier</string>
<key>CFBundleName</key><string>$app</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
  codesign --force --sign - ".local/gui/$app.app"
done
swiftc -O Tests/Fixtures/VirtualDisplay.swift -o .local/gui/virtual-display
echo 'Fixtures built in .local/gui. Launch with --display VIRTUAL_DISPLAY_ID.'
