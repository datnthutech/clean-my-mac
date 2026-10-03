# Clean My Mac — common tasks. Run `make help`.
.PHONY: help bootstrap project open build test test-linux lint-strings icon dmg clean run

help:
	@echo "make bootstrap    Install build tools (XcodeGen via Homebrew)"
	@echo "make project      Generate CleanMyMac.xcodeproj from project.yml"
	@echo "make open         Generate and open the project in Xcode"
	@echo "make test         Run DiskKit unit tests (swift test)"
	@echo "make build        Full build: tests + universal Release app + DMG in build/"
	@echo "make run          Build and launch the app"
	@echo "make test-linux   Run DiskKit tests in Docker (no Mac needed)"
	@echo "make lint-strings Check that vi/en translations are complete"
	@echo "make icon         Regenerate the app icon (needs Pillow)"
	@echo "make clean        Remove build output"

bootstrap:
	@command -v xcodegen >/dev/null || brew install xcodegen

project: bootstrap
	xcodegen generate

open: project
	open CleanMyMac.xcodeproj

test:
	swift test --package-path Packages/DiskKit

build:
	scripts/build.sh

run: build
	open "build/Clean My Mac.app"

test-linux:
	scripts/test_linux.sh

lint-strings:
	python3 scripts/check_localization.py

icon:
	python3 scripts/generate_icon.py

clean:
	rm -rf build CleanMyMac.xcodeproj Packages/DiskKit/.build
