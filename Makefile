.PHONY: all localizable-strings

builddir := $(shell mktemp -d "$(TMPDIR)/Sparkle.XXXXXX")

localizable-strings:
	rm Sparkle/en.lproj/Sparkle.strings || TRUE
	genstrings -o Sparkle/en.lproj -s SULocalizedString Sparkle/*.m Sparkle/*.h
	iconv -f UTF-16 -t UTF-8 < Sparkle/en.lproj/Localizable.strings > Sparkle/en.lproj/Sparkle.strings
	rm Sparkle/en.lproj/Localizable.strings

release:
	xcodebuild -scheme Distribution -configuration Release -derivedDataPath "$(builddir)"
	open -R "$(builddir)/Build/Products/Release/Sparkle-"*.zip
