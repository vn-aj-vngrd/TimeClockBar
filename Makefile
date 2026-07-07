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
PROJECT_VERSION := $(shell sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' TimeClockBar.xcodeproj/project.pbxproj | head -n 1)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
LATEST_TAG := $(shell git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)
BASE_VERSION := $(shell if [ -n "$(LATEST_TAG)" ]; then echo "$(LATEST_TAG)" | sed 's/^v//'; else echo "$(PROJECT_VERSION)"; fi)
COMMIT_RANGE := $(shell if [ -n "$(LATEST_TAG)" ]; then echo "$(LATEST_TAG)..HEAD"; else echo HEAD; fi)
AUTO_VERSION := $(shell scripts/next-version.sh)
VERSION ?= $(AUTO_VERSION)
ZIP_PATH := dist/TimeClockBar-$(VERSION)-internal.zip
XCODE_VERSION_FLAGS := MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

.PHONY: help version dev build run test test-version package verify quit-local install-local tag-version release clean distclean

help:
	@echo "Time Clock Bar commands:"
	@echo "  make version   Show app, build, and git version info"
	@echo "  make dev       Open the Xcode project"
	@echo "  make build     Build Debug"
	@echo "  make run       Build Debug and open the app"
	@echo "  make test      Run XCTest"
	@echo "  make test-version Run version script checks"
	@echo "  make package   Build Release and create $(ZIP_PATH)"
	@echo "  make verify    Verify the Release app code signature"
	@echo "  make quit-local Quit the locally running app if needed"
	@echo "  make install-local Build Release, install to ~/Applications, and open it"
	@echo "  make tag-version Tag HEAD as v$(VERSION)"
	@echo "  make release   Clean, package, and verify"
	@echo "  make clean     Remove build artifacts"
	@echo "  make distclean Remove build artifacts and packaged zips"

version:
	@echo "App version: $(VERSION)"
	@echo "Build number: $(BUILD_NUMBER)"
	@echo "Git SHA: $(GIT_SHA)"
	@echo "Latest tag: $(or $(LATEST_TAG),none)"
	@echo "Base version: $(BASE_VERSION)"
	@echo "Commit range: $(COMMIT_RANGE)"
	@echo "Package: $(ZIP_PATH)"

dev:
	open $(PROJECT)

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug $(XCODE_VERSION_FLAGS) build

run:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DEBUG_DERIVED_DATA) $(XCODE_VERSION_FLAGS) build
	open '$(DEBUG_APP_PATH)'

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' $(XCODE_VERSION_FLAGS)

test-version:
	scripts/test-next-version.sh

package:
	mkdir -p dist
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) $(XCODE_VERSION_FLAGS) build
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

tag-version:
	@git diff --quiet || (echo "Commit version changes before tagging."; exit 1)
	@! git rev-parse -q --verify 'refs/tags/v$(VERSION)' >/dev/null || (echo "Tag v$(VERSION) already exists."; exit 1)
	git tag -a 'v$(VERSION)' -m 'Time Clock Bar $(VERSION)'

release: clean test-version test package verify

clean:
	rm -rf build

distclean: clean
	rm -rf dist
