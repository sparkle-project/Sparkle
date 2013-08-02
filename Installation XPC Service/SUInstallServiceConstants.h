//
//  SUInstallServiceConstants.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 8/2/13.
//
//

#ifndef Sparkle_SUInstallServiceConstants_h
#define Sparkle_SUInstallServiceConstants_h

typedef enum _SUInstallSerciveTask
{
    SUInstallServiceTaskCopyPath    = 1LL,
    SUInstallServiceTaskLaunchTask  = 2LL
} SUInstallServiceTask;

const char * SUInstallServiceTaskTypeKey = "task_type"; // int64_t

// SUInstallServiceTaskCopyPath keys
const char * SUInstallServiceSourcePathKey = "source_path"; // c-string
const char * SUInstallServiceDestinationPathKey = "destination_path"; // c-string
const char * SUInstallServiceTempNameKey = "tmp_name"; // c-string

// SUInstallServiceTaskLaunchTask keys
const char * SUInstallServiceLaunchTaksPathKey = "launch_task_path";
const char * SUInstallServiceLaunchTaskArgumentsKey = "launch_task_arguments"; // xpc_array of c-strings

// Reply keys
const char * SUInstallServiceErrorCodeKey = "error_code"; // int64_t
const char * SUInstallServiceErrorLocalizedDescriptionKey = "error_localized_description"; // c-string

#endif
