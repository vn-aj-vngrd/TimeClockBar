PROJECT := TimeClockBar.xcodeproj
SCHEME := TimeClockBar
DESTINATION := platform=macOS
BUNDLE_ID := com.vanajvanguardia.TimeClockBar
DERIVED_DATA := build/TimeClockBarPackage
DEBUG_DERIVED_DATA := build/TimeClockBarDebug
APP_NAME := Time Clock Bar.app
APP_PATH := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME)
DEBUG_APP_PATH := $(DEBUG_DERIVED_DATA)/Build/Products/Debug/$(APP_NAME)
INSTALL_DIR ?= $(HOME)/Applications
INSTALLED_APP_PATH := $(INSTALL_DIR)/$(APP_NAME)
VERSION ?= 1.0
ZIP_PATH := dist/TimeClockBar-$(VERSION)-internal.zip

.PHONY: help dev build run test package verify quit-local install-local release clean distclean

help:
	@echo "Time Clock Bar commands:"
	@echo "  make dev       Open the Xcode project"
	@echo "  make build     Build Debug"
	@echo "  make run       Build Debug and open the app"
	@echo "  make test      Run XCTest"
	@echo "  make package   Build Release and create $(ZIP_PATH)"
	@echo "  make verify    Verify the Release app code signature"
	@echo "  make quit-local Quit the locally running app if needed"
	@echo "  make install-local Build Release, install to ~/Applications, and open it"
	@echo "  make release   Clean, package, and verify"
	@echo "  make clean     Remove build artifacts"
	@echo "  make distclean Remove build artifacts and packaged zips"

dev:
	open $(PROJECT)

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

run:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DEBUG_DERIVED_DATA) build
	open '$(DEBUG_APP_PATH)'

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)'

package:
	mkdir -p dist
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) build
	ditto -c -k --keepParent '$(APP_PATH)' '$(ZIP_PATH)'

verify:
	codesign --verify --deep --strict --verbose=2 '$(APP_PATH)'

quit-local:
	@osascript -e 'if application id "$(BUNDLE_ID)" is running then tell application id "$(BUNDLE_ID)" to quit' || true
	@sleep 1

install-local: package verify quit-local
	mkdir -p '$(INSTALL_DIR)'
	rm -rf '$(INSTALLED_APP_PATH)'
	cp -R '$(APP_PATH)' '$(INSTALLED_APP_PATH)'
	open '$(INSTALLED_APP_PATH)'

release: clean package verify

clean:
	rm -rf build

distclean: clean
	rm -rf dist
