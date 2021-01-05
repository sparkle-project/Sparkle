#!/bin/bash
set -e

# Finishing up - force re-tag
latest_git_tag=$(git describe --abbrev=0) # gets the latest tag name
read -p "Do you want to commit changes to Package.swift and force move tag '$latest_git_tag'? (required for Swift Package Manager release) " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    long_message=$(git tag -n99 -l $latest_git_tag) # gets corresponding message
    long_message=${long_message/$latest_git_tag} # trims tag name
    long_message="$(echo -e "${long_message}" | sed -e 's/^[[:space:]]*//')" # trim leading whitespace
    git add Package.swift
    git commit -m "Update Package.swift"
    git tag -fa $latest_git_tag -m "${long_message}"
fi
