.PHONY: all localizable-strings

localizable-strings:
	rm English.lproj/Sparkle.strings || TRUE
	genstrings -o English.lproj -s SULocalizedString *.m *.h
	mv English.lproj/Localizable.strings English.lproj/Sparkle.strings

