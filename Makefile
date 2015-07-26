.PHONY: all localizable-strings

localizable-strings:
	rm Sparkle/en.lproj/Sparkle.strings || TRUE
	genstrings -o Sparkle/en.lproj -s SULocalizedString Sparkle/*.m Sparkle/*.h
	mv Sparkle/en.lproj/Localizable.strings Sparkle/en.lproj/Sparkle.strings
