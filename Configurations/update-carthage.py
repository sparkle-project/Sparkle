#!/usr/bin/env python3

import os, sys, json

if len(sys.argv) < 3:
    print("Usage: path-to-carthage-file release-tag")
    sys.exit(1)

carthage_file = sys.argv[1]
release_tag = sys.argv[2]

with open(carthage_file, "r") as json_file:
    data = json.load(json_file)
    if release_tag in data:
        sys.exit(0)
    
with open(carthage_file, "w") as json_file:
    data[release_tag] = "https://github.com/sparkle-project/Sparkle/releases/download/" + release_tag + "/Sparkle-" + release_tag + ".tar.xz"

    json.dump(data, json_file)
