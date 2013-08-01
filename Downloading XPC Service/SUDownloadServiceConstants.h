//
//  SUDownloadServiceConstants.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 7/29/13.
//
//

#ifndef Sparkle_SUDownloadServiceConstants_h
#define Sparkle_SUDownloadServiceConstants_h

const char * SUDownloadServiceURLRequestDataKey = "request_data"; // data of archived NSURLRequest
const char * SUDownloadServiceDelegateConnectionKey = "connection"; // xpc_connection_t
const char * SUDownloadServiceFilePathKey = "file_path"; // c-string

const char * SUDownloadServiceReceivedDataLengthKey = "received_data_length"; // int64_t
const char * SUDownloadServiceReceivedResponseDataKey = "received_response_data"; // data of archived NSURLResponse
const char * SUDownloadServiceCreatedDestinationPathKey = "created_destination_path"; // c-string
const char * SUDownloadServiceDidBeginDownloadingKey = "did_begin_downloading"; // bool 1
const char * SUDownloadServiceDidFinishDownloadingKey = "did_finish_downloading"; // bool 1
const char * SUDownloadServiceReceivedFailErrorKey = "received_fail_error"; // data of archived NSError

const char * SUDownloadServiceErrorCodeKey = "errcode"; // int64_t
const char * SUDownloadServiceErrorMessageKey = "errmsg"; // c-string

#endif
