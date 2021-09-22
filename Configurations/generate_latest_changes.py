#!/usr/bin/env python3

import os, sys

# Ignore the first version line starting with # x.y.z..
# and print everything until the second version line starting with # x.y.z..

hit_first_changelog_note = False
with open("CHANGELOG", "r") as changelog_file:
    for line in changelog_file:
        if line.startswith("#"):
            if hit_first_changelog_note:
                # We are done with printing changes
                break
            else:
                # We haven't hit an important changelog line yet, so continue
                continue

        if not hit_first_changelog_note and len(line.strip()) == 0:
            continue

        hit_first_changelog_note = True
        sys.stdout.write(line)
