# You can run this by creating a new sh run script in your application target's build phase eg like so:
# /usr/bin/python ${SRCROOT}/codesign_sparkle.py
#
# You must also disable "Code Sign on Copy" option which Xcode defaults to having 'on' when copying Sparkle.framework into your application.
# We use this script instead because Apple's code sign on copy functionality does not work well for frameworks that include other bundles.
# Note this script is safe to run even if no code signing identity is being used (nothing would happen in this case)

import os, sys, subprocess

def code_sign(identity, path):
    process = subprocess.Popen(["codesign", "-fs", identity, path], stdout=subprocess.PIPE)
    process.communicate()
    assert(process.returncode == 0)

if __name__ == "__main__":
    sparkle_path = os.path.join(os.path.join(os.environ["TARGET_BUILD_DIR"], os.environ["FRAMEWORKS_FOLDER_PATH"]), "Sparkle.framework")

    # It's ok if no code signing identity exists, that just means we won't have to do anything
    try:
        signing_identity = os.environ["CODE_SIGN_IDENTITY"]
    except KeyError:
        sys.exit(0)

    if len(signing_identity) == 0:
        sys.exit(0)

    #Sign any services inside of our framework
    services_directory = os.path.join(sparkle_path, "XPCServices")
    for filename in os.listdir(services_directory):
        if filename.endswith(".xpc"):
            full_path = os.path.join(services_directory, filename)
            code_sign(signing_identity, full_path)

    #Finally sign our framework
    code_sign(signing_identity, sparkle_path)
