#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/install-iphone.sh DEVICE_IDENTIFIER"
  echo "Find the paired device with: xcrun devicectl list devices"
  exit 1
fi
device_identifier="$1"
xcodebuild -project Muyar.xcodeproj -scheme Muyar -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/iPhone \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device "$device_identifier" build/iPhone/Build/Products/Release-iphoneos/Muyar.app
xcrun devicectl device process launch --device "$device_identifier" com.eimg.Muyar
