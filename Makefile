.PHONY: all localizable-strings release build test ci

all: build

ifndef BUILDDIR
    BUILDDIR := $(shell mkdir -p "build" && mktemp -d "build/Sparkle.XXXXXX")
endif

localizable-strings:
	rm -f Sparkle/Base.lproj/Sparkle.strings
	genstrings -o Sparkle/Base.lproj -s SULocalizedString Sparkle/*.m
	iconv -f UTF-16 -t UTF-8 < Sparkle/Base.lproj/Localizable.strings > Sparkle/Base.lproj/Sparkle.strings
	rm Sparkle/Base.lproj/Localizable.strings

release:
	xcodebuild -scheme Distribution -configuration Release -derivedDataPath "$(BUILDDIR)" build
	./Configurations/release-move-tag.sh
	open "$(BUILDDIR)/Build/Products/Release/"
	cat Sparkle.podspec
	@echo "Don't forget to update CocoaPods! pod trunk push"
	@echo "Don't forget to upload Sparkle-for-Swift-Package-Manager.zip!"

build:
	xcodebuild clean build
	
# Need to first gem install jazzy to run this rule
docs:
	jazzy --author "Sparkle Project" --objc --umbrella-header Sparkle/Sparkle.h --framework-root . --readme Documentation/API_README.markdown --theme jony --output Documentation/html

uitest:
	xcodebuild -scheme UITests -configuration Debug test

check-localizations:
	./Sparkle/CheckLocalizations.swift -root . -htmlPath "$(TMPDIR)/LocalizationsReport.htm"
	open "$(TMPDIR)/LocalizationsReport.htm"
