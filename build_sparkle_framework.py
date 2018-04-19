# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at http://mozilla.org/MPL/2.0/.

import os
import os.path
import shutil
import subprocess
import sys


def Main(args):
  out_dir = os.getcwd()
  sparkle_dir = os.path.dirname(os.path.realpath(__file__))
  os.chdir(sparkle_dir)

  FNULL = open(os.devnull, 'w')
  out_dir_config = 'CONFIGURATION_BUILD_DIR=' + out_dir
  command = ['xcodebuild', '-target', 'Sparkle', '-configuration', 'Release', out_dir_config, 'build']
  subprocess.check_call(command, stdout=FNULL)

  return 0


if __name__ == '__main__':
  sys.exit(Main(sys.argv))
