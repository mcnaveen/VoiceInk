# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
# Same Xcode configuration as `make local` (Debug + LocalBuild.xcconfig)
LOCAL_BUILD_CONFIG := Debug
# CI release packaging: copy the built .app here instead of ~/Downloads
DIST_DIR ?= $(CURDIR)/dist

.PHONY: all clean whisper setup build local ci-release _local-app-bundle check healthcheck help dev run

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Shared xcodebuild for `make local` and `make ci-release` (identical product)
_local-app-bundle: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration $(LOCAL_BUILD_CONFIG) \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/VoiceInk/VoiceInk.local.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build

# Build for local use without Apple Developer certificate
local: _local-app-bundle
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/$(LOCAL_BUILD_CONFIG)/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying VoiceInk.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/VoiceInk.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/VoiceInk.app"; \
		xattr -cr "$$HOME/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/VoiceInk.app"; \
		echo "Run with: open ~/Downloads/VoiceInk.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Same build as `make local`; copy .app to $(DIST_DIR) for CI zipping (not ~/Downloads)
ci-release: _local-app-bundle
	@rm -rf "$(DIST_DIR)"
	@mkdir -p "$(DIST_DIR)"
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/$(LOCAL_BUILD_CONFIG)/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		ditto "$$APP_PATH" "$(DIST_DIR)/VoiceInk.app"; \
		xattr -cr "$(DIST_DIR)/VoiceInk.app"; \
		echo "Built (same as make local): $(DIST_DIR)/VoiceInk.app"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
run:
	@if [ -d "$$HOME/Downloads/VoiceInk.app" ]; then \
		echo "Opening ~/Downloads/VoiceInk.app..."; \
		open "$$HOME/Downloads/VoiceInk.app"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceInk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  ci-release         CI: same as local build, app in ./dist/VoiceInk.app"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"