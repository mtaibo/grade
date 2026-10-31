.PHONY: build test generate open clean todo device web

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

todo:
	python3 scripts/todo_server.py

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

# The site at grade.migueltaibo.com, run on the Pi: tpcloud must be up first (its gateway network
# and Caddy, which proxies the subdomain to this container).
web:
	docker compose -f web/docker-compose.yml up -d --build
