SWIFT ?= swift
BIN = .build/release/gargantua
APP = Gargantua.app
BASE ?= origin/main

# Command Line Tools installs package Swift Testing as a framework where
# swift test does not look; Xcode toolchains need none of this.
DEVDIR := $(shell xcode-select -p 2>/dev/null)
ifeq ($(DEVDIR),/Library/Developer/CommandLineTools)
TESTFLAGS := -Xswiftc -F$(DEVDIR)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(DEVDIR)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(DEVDIR)/Library/Developer/usr/lib
endif

.PHONY: build release test check app constants hooks clean lint-commits dashes

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release

test:
	$(SWIFT) test $(TESTFLAGS)

check: test dashes lint-commits

dashes:
	@if git ls-files -z | xargs -0 perl -CSD -ne 'print "$$ARGV:$$.\n" if /[\x{2013}\x{2014}]/' | grep .; then echo "em dash or en dash found"; exit 1; fi

lint-commits:
	@git log --format=%s $(BASE)..HEAD | while IFS= read -r title; do printf '%s\n' "$$title" | .githooks/lint-title || exit 1; done

app: release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/gargantua
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>CFBundleExecutable</key><string>gargantua</string>' \
	  '<key>CFBundleIdentifier</key><string>dev.mithrilbytes.gargantua</string>' \
	  '<key>CFBundleName</key><string>Gargantua</string>' \
	  '<key>CFBundlePackageType</key><string>APPL</string>' \
	  '<key>CFBundleShortVersionString</key><string>0.1.0</string>' \
	  '<key>LSMinimumSystemVersion</key><string>14.0</string>' \
	  '<key>NSHighResolutionCapable</key><true/>' \
	  '</dict></plist>' > $(APP)/Contents/Info.plist
	@echo "built $(APP)"

constants:
	$(SWIFT) run gargantua constants > Sources/Gargantua/Shaders/Constants.h

hooks:
	git config core.hooksPath .githooks

clean:
	rm -rf .build $(APP)
