PROJECT := AppTimer.xcodeproj
SCHEME := AppTimer
DERIVED_DATA ?= $(CURDIR)/.build/DerivedData
BUILD_DIR ?= $(CURDIR)/.build/Release
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" AppTimer/Info.plist)
APP := $(DERIVED_DATA)/Build/Products/Release/AppTimer.app
DMG := $(BUILD_DIR)/AppTimer-$(VERSION)-installer-arm64.dmg
STAGE := $(BUILD_DIR)/stage

.PHONY: build test install dmg clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO

install: build
	rm -rf /Applications/AppTimer.app
	cp -R $(APP) /Applications/AppTimer.app
	@echo "AppTimer установлен в /Applications. Локальная сборка не получает атрибут карантина."

dmg: build
	rm -rf $(STAGE)
	mkdir -p $(STAGE)
	cp -R $(APP) $(STAGE)/AppTimer.app
	codesign --force --deep --sign - $(STAGE)/AppTimer.app
	ln -s /Applications $(STAGE)/Applications
	mkdir -p $(BUILD_DIR)
	hdiutil create -volname 'AppTimer $(VERSION)' -srcfolder $(STAGE) -ov -format UDZO $(DMG)
	shasum -a 256 $(DMG) > $(DMG).sha256
	@echo "Создано: $(DMG)"

clean:
	rm -rf $(CURDIR)/.build
