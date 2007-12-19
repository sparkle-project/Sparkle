.PHONY: all localizable-strings

localizable-strings:
	rm en.lproj/Sparkle.strings || TRUE
	genstrings -o en.lproj -s SULocalizedString *.m *.h
	mv en.lproj/Localizable.strings en.lproj/Sparkle.strings

