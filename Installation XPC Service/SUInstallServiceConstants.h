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
    SUInstallServiceTaskCopyPath        = 1LL,
    SUInstallServiceTaskAuthCopyPath    = 2LL,
    SUInstallServiceTaskLaunchTask      = 3LL
} SUInstallServiceTask;

const char * SUInstallServiceTaskTypeKey = "task_type"; // int64_t

// SUInstallServiceTaskCopyPath & SUInstallServiceTaskAuthCopyPath keys
const char * SUInstallServiceSourcePathKey = "source_path"; // c-string
const char * SUInstallServiceDestinationPathKey = "destination_path"; // c-string
const char * SUInstallServiceTempNameKey = "tmp_name"; // c-string

// SUInstallServiceTaskLaunchTask keys
const char * SUInstallServiceLaunchTaksPathKey = "launch_task_path";
const char * SUInstallServiceLaunchTaskArgumentsKey = "launch_task_arguments"; // xpc_array of c-strings
const char * SUInstallServiceLaunchTaskEnvironmentKey = "launch_task_environment"; // xpc_dictionary with keys and values of c-strings
const char * SUInstallServiceLaunchTaskCurrentDirKey = "launch_task_cur_dir"; // c-string
const char * SUInstallServiceLaunchTaskInputDataKey = "launch_task_input_data"; // xpc_data
const char * SUInstallServiceLaunchTaskReplyImmediatelyKey = "launch_task_reply_immediately"; // bool

// Reply keys
const char * SUInstallServiceErrorCodeKey = "error_code"; // int64_t
const char * SUInstallServiceErrorLocalizedDescriptionKey = "error_localized_description"; // c-string
const char * SUInstallServiceLaunchTaskOutputDataKey = "launch_task_output_data"; // xpc_data

#endif
