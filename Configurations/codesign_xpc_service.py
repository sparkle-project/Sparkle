#!/usr/bin/env python3

import os, sys, subprocess, tempfile, pathlib

PRODUCT_BUNDLE_ID_MACRO = "$(PRODUCT_BUNDLE_IDENTIFIER)"

def log_message(message):
    sys.stderr.write(message + "\n")

#Surround a token with double quotes if it has a space in it
def sanitize(argument):
    return ('"' + argument + '"' if ' ' in argument else argument)

def _codesign_service(identity, path, entitlements_path=None):
    command = ["codesign", "-o", "runtime", "-fs", identity, path] + ([] if entitlements_path is None else ["--entitlements", entitlements_path])
    log_message(" ".join(map(sanitize, command)))

    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    process.communicate()
    if process.returncode != 0:
        log_message("Error: Failed to codesign %s" % (path))
        sys.exit(1)

def codesign_service(service_name, identity, path, entitlements_path=None):
    #Sign the auxiliary executables (if any)
    executables_path = os.path.join(path, "Contents/MacOS/")
    if os.path.exists(executables_path):
        for executable in os.listdir(executables_path):
            if executable != service_name:
                _codesign_service(identity, os.path.join(executables_path, executable), entitlements_path)

    #Sign the service bundle
    _codesign_service(identity, path, entitlements_path)

# Returns entitlements back with a bundle id applied if needed
def applied_entitlements_path(entitlements_path, bundle_id, temp_dir):
    entitlements_str = pathlib.Path(entitlements_path).read_text()
    if PRODUCT_BUNDLE_ID_MACRO in entitlements_str:
        if bundle_id is None:
            return None
        else:
            new_entitlements_str = entitlements_str.replace(PRODUCT_BUNDLE_ID_MACRO, bundle_id)
            new_entitlements_path = os.path.join(temp_dir, os.path.basename(entitlements_path))
            pathlib.Path(new_entitlements_path).write_text(new_entitlements_str)
            return new_entitlements_path
    else:
        return entitlements_path

def print_usage():
    log_message("Usage:\n\t%s code-signing-identity [-b app-bundle-id] service1 service2 ..." % (sys.argv[0]))
    log_message("Example:\n\t%s \"Developer ID Application\" ./XPCServices/org.sparkle-project.InstallerLauncher.xpc" % (sys.argv[0]))
    log_message("")
    log_message("Use this script to sign XPC Services to include in your Sandboxed application.")
    log_message("")
    log_message("bundle-id is optional and only needs to be provided when signing InstallerConnection and InstallerStatus services. Most applications do not need to use these services and can provide additional entitlements to their application instead.")
    log_message("")
    log_message("This script may not be needed for common development workflows. Please visit https://sparkle-project.org/documentation/sandboxing/ for more details and instructions.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print_usage()
        sys.exit(1)

    signing_identity = sys.argv[1]
    remaining_args = sys.argv[2:]
    bundle_id = None
    if remaining_args[0] == '-b':
        if len(remaining_args) < 3:
            # We need the bundle-id and at least one XPC Service to sign
            print_usage()
            sys.exit(1)
        else:
            bundle_id = remaining_args[1]
            services = remaining_args[2:]
    else:
        services = remaining_args

    with tempfile.TemporaryDirectory() as temp_dir:
        for service in services:
            parent, child = os.path.split(service)
            service_name = os.path.splitext(child)[0]
            entitlements_path = os.path.join(parent, service_name + ".entitlements")
            if os.path.exists(entitlements_path):
                service_entitlements_path = applied_entitlements_path(entitlements_path, bundle_id, temp_dir)
                if service_entitlements_path is None:
                    print_usage()
                    log_message("")
                    log_message("Error: Bundle ID must be specified for signing %s. As noted in the usage above, you probably don't need to embed this service." % (service_name))
                    sys.exit(1)
            else:
                service_entitlements_path = None
            
            codesign_service(service_name, signing_identity, service, service_entitlements_path)
