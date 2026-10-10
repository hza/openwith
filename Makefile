APP     := build/Open With.app
BIN     := build/openwith
DEST    := $(HOME)/Applications
ARCH    ?= $(shell uname -m)
CFLAGS  := -fobjc-arc -O2 -Wall -mmacosx-version-min=12.0 $(foreach a,$(ARCH),-arch $(a))
LDFLAGS := -framework Cocoa -framework UniformTypeIdentifiers

all: build/.app-stamp ## Build and ad-hoc codesign build/Open With.app (default)

build/.app-stamp: $(BIN) Info.plist icon/app.icns
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp $(BIN) "$(APP)/Contents/MacOS/openwith"
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp icon/app.icns "$(APP)/Contents/Resources/app.icns"
	codesign --force --sign - "$(APP)"
	touch $@

icns: ## Regenerate icon/app.icns from icon/source.png (see icon/Makefile)
	$(MAKE) -C icon

SRCS    := $(wildcard src/*.m)
HDRS    := $(wildcard src/*.h)

$(BIN): $(SRCS) $(HDRS)
	mkdir -p build
	clang $(CFLAGS) $(SRCS) -o $@ $(LDFLAGS)

run: all ## Build and launch the app from build/
	open "$(APP)"

kill: ## Quit the running instance
	-pkill -x openwith

clean: ## Remove build/
	rm -rf build

install: all ## Install to ~/Applications and register with LaunchServices
	mkdir -p "$(DEST)"
	rm -rf "$(DEST)/Open With.app"
	cp -R "$(APP)" "$(DEST)/"
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(DEST)/Open With.app"

open: kill install ## Kill, reinstall to ~/Applications, and launch
	open "$(DEST)/Open With.app"

uninstall: ## Remove from ~/Applications and delete the app's defaults
	-rm -rf "$(DEST)/Open With.app"
	-defaults delete io.github.hza.openwith

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: icns all run kill clean install open uninstall help
