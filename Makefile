APP_NAME = MacOS Ultrabright
BINARY = macos-ultrabright
BUILD_DIR ?= .build
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
CODE_SIGN_IDENTITY ?= -
ARCH ?= arm64
SWIFT_TARGET ?= $(ARCH)-apple-macos12.0
SOURCES = Sources/main.swift Sources/GammaTable.swift Sources/Brightness.swift Sources/BrightnessSlider.swift Sources/BrightnessKeys.swift Sources/BrightnessTransition.swift

.PHONY: build app dmg clean

build:
	@mkdir -p "$(BUILD_DIR)"
	swiftc -target $(SWIFT_TARGET) -O -o "$(BUILD_DIR)/$(BINARY).next" $(SOURCES) \
		-framework Cocoa -framework MetalKit -framework Metal -framework QuartzCore
	mv -f "$(BUILD_DIR)/$(BINARY).next" "$(BUILD_DIR)/$(BINARY)"

app: build
	@mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$(BUILD_DIR)/$(BINARY)" "$(APP_DIR)/Contents/MacOS/$(BINARY).next"
	mv -f "$(APP_DIR)/Contents/MacOS/$(BINARY).next" "$(APP_DIR)/Contents/MacOS/$(BINARY)"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	swiftc -o "$(BUILD_DIR)/make-icon" Scripts/make-icon.swift -framework AppKit
	"$(BUILD_DIR)/make-icon" "$(BUILD_DIR)/AppIcon.iconset"
	iconutil -c icns "$(BUILD_DIR)/AppIcon.iconset" -o "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	cp LICENSE "$(APP_DIR)/Contents/Resources/LICENSE"
	cp Resources/INSTALL.txt "$(BUILD_DIR)/INSTALL.txt"
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$(APP_DIR)"

dmg: app
	sh Scripts/package-dmg.sh "$(BUILD_DIR)" "$(ARCH)"

clean:
	rm -rf "$(BUILD_DIR)"
