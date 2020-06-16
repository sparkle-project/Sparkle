#!/bin/sh

here=$(dirname "$0")
cd "$here"

codesign -f -s - -i org.sparkle-project.Sparkle.SUUpdateValidatorTestBundle.CodeSigned -r='designated => identifier "org.sparkle-project.Sparkle.SUUpdateValidatorTestBundle.CodeSigned"' CodeSignedOnly.bundle CodeSignedBoth.bundle CodeSignedOldED.bundle

codesign -f -s - -i org.sparkle-project.Sparkle.SUUpdateValidatorTestBundle.CodeSignedNew -r='designated => identifier "org.sparkle-project.Sparkle.SUUpdateValidatorTestBundle.CodeSignedNew"' CodeSignedOnlyNew.bundle CodeSignedBothNew.bundle

for invalidBundle in CodeSignedInvalid.bundle CodeSignedInvalidOnly.bundle; do
    cp -rf CodeSignedOnly.bundle/Contents/_CodeSignature ${invalidBundle}/Contents
    echo ${invalidBundle}: copied code signature from CodeSignedOnly.bundle
done
