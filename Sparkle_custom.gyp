# Copyright (c) 2011 House of Life Property ltd.
# Copyright (c) 2011 Crystalnix <vgachkaylo@crystalnix.com>

{
  'conditions': [
    ['OS=="mac"', {
      'targets': [
        {
          'target_name': 'Sparkle',
          'type': 'shared_library',
          'product_name': 'Sparkle',
          'actions': [
            {
              'action_name': 'sparkle_make_release',
              'inputs': [
                'Makefile',
                '<!@(ls -1 Sparkle/*.h)',
                '<!@(ls -1 Sparkle/*.m)',
              ],
              'outputs': [
                'Build/Products/Release/Sparkle.framework'
              ],
              'action': [
                # this is the command that `make release` runs,
                # except this doesn't open a finder window when it is done
                '/usr/bin/env', 'bash', '-c',
                'xcodebuild -scheme Distribution -configuration Release -derivedDataPath "." DYLIB_INSTALL_NAME_BASE=@loader_path/Frameworks'
              ]
            },
            {
              'action_name': 'Copy Sparkle Framework unversioned',
              'inputs': [
                'Build/Products/Release/Sparkle.framework'
              ],
              'outputs': [
                '<(PRODUCT_DIR)/Sparkle.framework'
              ],
              'action': [
                #'echo `pwd` && set &&',
                #'/usr/bin/env', 'bash', '-c',
                '${BUILT_PRODUCTS_DIR}/../../build/mac/copy_framework_unversioned.sh',
                '${SOURCE_ROOT}/Build/Products/Release/Sparkle.framework',
                '${BUILT_PRODUCTS_DIR}',
              ]
            }
          ],
          'copies': [
            {
              'destination': '<(PRODUCT_DIR)/Sparkle_versioned',
              'files': [
                'Build/Products/Release/Sparkle.framework'
              ]
            }
          ],
        },
      ],
    }, ],
  ],
}