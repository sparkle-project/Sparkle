//
//  SUInstallServiceConstants.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 8/2/13.
//
//

#ifndef Sparkle_SUInstallServiceConstants_h
#define Sparkle_SUInstallServiceConstants_h

typedef NS_ENUM(UInt64, SUInstallServiceTask)
{
    SUInstallServiceTaskUnknown         = 0,
    SUInstallServiceTaskCopyPath        = 1LL,
    SUInstallServiceTaskAuthCopyPath    = 2LL,
    SUInstallServiceTaskLaunchTask      = 3LL
};

static const char * SUInstallServiceTaskTypeKey = "task_type"; // int64_t

// SUInstallServiceTaskCopyPath & SUInstallServiceTaskAuthCopyPath keys
static const char * SUInstallServiceSourcePathKey = "source_path"; // c-string
static const char * SUInstallServiceDestinationPathKey = "destination_path"; // c-string
static const char * SUInstallServiceTempNameKey = "tmp_name"; // c-string

// SUInstallServiceTaskLaunchTask keys
static const char * SUInstallServiceLaunchTaksPathKey = "launch_task_path";
static const char * SUInstallServiceLaunchTaskArgumentsKey = "launch_task_arguments"; // xpc_array of c-strings
static const char * SUInstallServiceLaunchTaskEnvironmentKey = "launch_task_environment"; // xpc_dictionary with keys and values of c-strings
static const char * SUInstallServiceLaunchTaskCurrentDirKey = "launch_task_cur_dir"; // c-string
static const char * SUInstallServiceLaunchTaskInputDataKey = "launch_task_input_data"; // xpc_data
static const char * SUInstallServiceLaunchTaskReplyImmediatelyKey = "launch_task_reply_immediately"; // bool

// Reply keys
static const char * SUInstallServiceErrorCodeKey = "error_code"; // int64_t
static const char * SUInstallServiceErrorLocalizedDescriptionKey = "error_localized_description"; // c-string
static const char * SUInstallServiceLaunchTaskOutputDataKey = "launch_task_output_data"; // xpc_data

#endif
