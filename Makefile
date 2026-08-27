.DEFAULT_GOAL := help

MOBILE_DIR := mobile

ifeq ($(OS),Windows_NT)
USER_HOME := $(subst \,/,$(USERPROFILE))
LOCAL_FLUTTER := $(USER_HOME)/development/flutter/bin/flutter.bat
LOCAL_DART := $(USER_HOME)/development/flutter/bin/dart.bat
FLUTTER ?= $(if $(wildcard $(LOCAL_FLUTTER)),$(LOCAL_FLUTTER),flutter)
DART ?= $(if $(wildcard $(LOCAL_DART)),$(LOCAL_DART),dart)
else
FLUTTER ?= flutter
DART ?= dart
endif

.PHONY: help sdk get format format-check analyze test verify build debug release clean

help:
	@echo Mobile commands:
	@echo   make sdk          Show the Flutter SDK selected by this repository
	@echo   make get          Restore locked Flutter dependencies
	@echo   make format       Format mobile source and tests
	@echo   make format-check Report mobile files that need formatting
	@echo   make analyze      Run Flutter static analysis
	@echo   make test         Run the complete Flutter test suite
	@echo   make verify       Analyze and run the complete test suite
	@echo   make build        Build the debug APK
	@echo   make debug        Alias for make build
	@echo   make release      Verify and build split arm64 release APK
	@echo   make clean        Remove Flutter build outputs

sdk:
	@echo Flutter: $(FLUTTER)
	@"$(FLUTTER)" --version

get:
	@cd $(MOBILE_DIR) && "$(FLUTTER)" pub get --enforce-lockfile

format:
	@cd $(MOBILE_DIR) && "$(DART)" format lib test integration_test

format-check:
	@cd $(MOBILE_DIR) && "$(DART)" format --output=none --set-exit-if-changed lib test integration_test

analyze: get
	@cd $(MOBILE_DIR) && "$(FLUTTER)" analyze --no-pub

test: get
	@cd $(MOBILE_DIR) && "$(FLUTTER)" test --no-pub

verify: get analyze test

build: get
	@cd $(MOBILE_DIR) && "$(FLUTTER)" build apk --debug --no-pub

debug: build

release: verify
	@cd $(MOBILE_DIR) && "$(FLUTTER)" clean
	@cd $(MOBILE_DIR) && "$(FLUTTER)" build apk --release --target-platform android-arm64

clean:
	@cd $(MOBILE_DIR) && "$(FLUTTER)" clean
