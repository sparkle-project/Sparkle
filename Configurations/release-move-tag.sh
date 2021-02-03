#!/bin/bash
set -e

# Convenience script to automatically commit Package.swift after updating the checksum and move the latest tag
latest_git_tag=$(git describe --abbrev=0 --tags) # gets the latest tag name
commits_since_tag=$(git rev-list ${latest_git_tag}.. --count)
if [ "$commits_since_tag" -gt 0 ]; then
    # If there have been commits since the latest tag, it's highly likely that we did not intend to do a full release
    echo "WARNING: $commits_since_tag commit(s) since tag '$latest_git_tag'. Did you tag a new version?"
    echo "Package.swift has not been committed and tag has not been moved."
else
    # TODO: add sanity check to see if version is actually being updated or not?
    read -p "Do you want to commit changes to Package.swift and force move tag '$latest_git_tag'? (required for SPM release) [Y/n]" -n 1 -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Package.swift has not been committed and tag has not been moved."
    else
        git add Package.swift
        git commit -m "Update Package.swift"
        git tag -f $latest_git_tag
        echo "Package.swift committed and tag '$latest_git_tag' moved."
    fi
fi
