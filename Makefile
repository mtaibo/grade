.PHONY: build test generate open clean device mac testflight web

build:
	swift build

test:
	swift test

generate:
	cd App && xcodegen generate

open: generate
	open App/Grade.xcodeproj

clean:
	swift package clean
	rm -rf App/Grade.xcodeproj

# Builds the app, installs it on the first connected iPhone and opens it. Needs DEVELOPMENT_TEAM in
# App/Config/Local.xcconfig and the iPhone paired (by cable, or on the same Wi-Fi once paired),
# unlocked and in Developer Mode.
# DEVICE=<udid> picks another one.
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null | awk '/physical/ {for (i=1;i<=NF;i++) if ($$i ~ /^[0-9A-F]+-[0-9A-F]+$$/ && length($$i) == 25) {print $$i; exit}}')
DEVICE_BUILD = build/device

device: generate
	@test -n "$(DEVICE)" || (echo "No hay ningún iPhone conectado." && exit 1)
	xcodebuild -project App/Grade.xcodeproj -scheme Grade-iOS -configuration Debug \
		-destination 'generic/platform=iOS' -derivedDataPath $(DEVICE_BUILD) -allowProvisioningUpdates -quiet build
	@# Over Wi-Fi the first connection is often reset; a second try goes through.
	xcrun devicectl device install app --device $(DEVICE) $(DEVICE_BUILD)/Build/Products/Debug-iphoneos/Grade-iOS.app \
		|| (sleep 2 && xcrun devicectl device install app --device $(DEVICE) $(DEVICE_BUILD)/Build/Products/Debug-iphoneos/Grade-iOS.app)
	xcrun devicectl device process launch --device $(DEVICE) com.migueltaibo.grade

# Builds the Mac app and opens it. Needs DEVELOPMENT_TEAM in App/Config/Local.xcconfig: without signing it
# has no iCloud entitlement, and CloudKit stops the app on launch.
# The first build registers this Mac in the developer account.
MAC_BUILD = build/mac

mac: generate
	xcodebuild -project App/Grade.xcodeproj -scheme Grade-macOS -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath $(MAC_BUILD) -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build
	open $(MAC_BUILD)/Build/Products/Debug/Grade.app

# Archives the iPhone and Mac apps and uploads both to App Store Connect (TestFlight). Needs DEVELOPMENT_TEAM in
# App/Config/Local.xcconfig, Xcode signed in with the developer account and the app created in App Store
# Connect with bundle id com.migueltaibo.grade. Every upload needs a build number higher than the last:
# it defaults to the current date and time, BUILD=<n> overrides it. The marketing version is in Shared.xcconfig.
BUILD ?= $(shell date +%y%m%d%H%M)
# Fixed once, so the iPhone and the Mac uploads share a number.
BUILD := $(BUILD)
TEAM = $(shell awk -F= '/^DEVELOPMENT_TEAM/ {gsub(/ /, "", $$2); print $$2}' App/Config/Local.xcconfig 2>/dev/null)
ARCHIVE = build/Grade.xcarchive
MAC_ARCHIVE = build/Grade-macOS.xcarchive

testflight: generate
	@test -n "$(TEAM)" || (echo "Falta DEVELOPMENT_TEAM en App/Config/Local.xcconfig." && exit 1)
	@mkdir -p build
	@printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
		'<plist version="1.0"><dict>' \
		'<key>method</key><string>app-store-connect</string>' \
		'<key>destination</key><string>upload</string>' \
		'<key>teamID</key><string>$(TEAM)</string>' \
		'<key>signingStyle</key><string>automatic</string>' \
		'</dict></plist>' > build/ExportOptions.plist
	rm -rf $(ARCHIVE) $(MAC_ARCHIVE)
	xcodebuild -project App/Grade.xcodeproj -scheme Grade-iOS -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVE) -allowProvisioningUpdates \
		CURRENT_PROJECT_VERSION=$(BUILD) -quiet archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportOptionsPlist build/ExportOptions.plist \
		-allowProvisioningUpdates
	xcodebuild -project App/Grade.xcodeproj -scheme Grade-macOS -configuration Release \
		-destination 'generic/platform=macOS' -archivePath $(MAC_ARCHIVE) -allowProvisioningUpdates \
		CURRENT_PROJECT_VERSION=$(BUILD) -quiet archive
	xcodebuild -exportArchive -archivePath $(MAC_ARCHIVE) -exportOptionsPlist build/ExportOptions.plist \
		-allowProvisioningUpdates

# The site at grade.migueltaibo.com, run on the Pi: tpcloud must be up first (its gateway network
# and Caddy, which proxies the subdomain to this container).
web:
	docker compose -f web/docker-compose.yml up -d --build
