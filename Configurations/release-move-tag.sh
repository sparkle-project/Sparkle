#!/bin/bash
set -e

# Convenience script to automatically commit Package.swift after updating the checksum and move the latest tag
latest_git_tag=$( git describe --tags --abbrev=0 || true ) # gets the latest tag name
if [ -z "$latest_git_tag" ] ; then
    exit 0
fi

commits_since_tag=$(git rev-list ${latest_git_tag}.. --count)

function move_tag() {
    long_message=$(git tag -n99 -l $latest_git_tag) # gets corresponding message
    long_message=${long_message/$latest_git_tag} # trims tag name
    long_message="$(echo -e "${long_message}" | sed -e 's/^[[:space:]]*//')" # trim leading whitespace
    git add Package.swift Sparkle.podspec Carthage-dev.json
    git commit -m "Update Package management files for version ${latest_git_tag}"
    git tag -fa $latest_git_tag -m "${long_message}"
    echo "Package.swift and Sparkle.podspec committed and tag '$latest_git_tag' moved."
}

if [ "$commits_since_tag" -gt 0 ]; then
    # If there have been commits since the latest tag, it's highly likely that we did not intend to do a full release
    echo "WARNING: $commits_since_tag commit(s) since tag '$latest_git_tag'. Did you tag a new version?"
    echo "Package management files have not been committed and tag has not been moved."
elif [ "$CI" == true ]; then
    move_tag
else
# TODO: add sanity check to see if version is actually being updated or not?
    read -p "Do you want to commit changes to Package.swift, Sparkle.podspec, Carthage-dev.json and force move tag '$latest_git_tag'? (required for official release) [Y/n]" -n 1 -r
        echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        move_tag
    else
        echo "Package.swift, Sparkle.podspec, and Carthage-dev.json have not been committed and tag has not been moved."
    fi
fi
