//
//  SUTestWebServer.m
//  Sparkle
//
//  Created by Kevin Wojniak on 10/8/15.
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

#import "SUTestWebServer.h"
#import <sys/socket.h>
#import <netinet/in.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

@class SUTestWebServerConnection;

@protocol SUTestWebServerConnectionDelegate <NSObject>
@required
- (void)connectionDidClose:(SUTestWebServerConnection*)sender;
@end

@interface SUTestWebServerConnection : NSObject <NSStreamDelegate>

@end

@implementation SUTestWebServerConnection {
    NSString *_workingDirectory;
    id<SUTestWebServerConnectionDelegate> _delegate;
    NSInputStream *_inputStream;
    NSOutputStream *_outputStream;
    NSData *_dataToWrite;
    NSInteger _numBytesToWrite;
}

- (instancetype)initWithNativeHandle:(CFSocketNativeHandle)handle workingDirectory:(NSString*)workingDirectory delegate:(id<SUTestWebServerConnectionDelegate>)delegate {
    self = [super init];
    assert(self != nil);
    
    _workingDirectory = workingDirectory;
    _delegate = delegate;
    
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(NULL, handle, &readStream, &writeStream);
    assert(readStream != NULL);
    assert(writeStream != NULL);
    
    _inputStream = (__bridge NSInputStream*)readStream;
    assert(_inputStream != nil);
    _inputStream.delegate = self;
    
    _outputStream = (__bridge NSOutputStream*)writeStream;
    assert(_outputStream != nil);
    _outputStream.delegate = self;
    
    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_inputStream open];
    [_outputStream open];
    
    return self;
}

- (void)close {
    if (!_inputStream) {
        assert(_outputStream == nil);
        return;
    }
    [_inputStream close];
    [_outputStream close];
    [_inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    _inputStream = nil;
    _outputStream = nil;
    [_delegate connectionDidClose:self];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (eventCode == NSStreamEventEndEncountered) {
        [self close];
        return;
    }
    if (aStream == _inputStream && eventCode == NSStreamEventHasBytesAvailable) {
        uint8_t buffer[8096];
        const NSInteger numBytes = [_inputStream read:buffer maxLength:sizeof(buffer)];
        if (numBytes > 0) {
            NSString *request = [[NSString alloc] initWithBytes:buffer length:(NSUInteger)numBytes encoding:NSUTF8StringEncoding];
            NSArray *lines = [request componentsSeparatedByString:@"\r\n"];
            NSString *requestLine = lines.count >= 3 ? lines[0] : nil;
            NSArray *parts = requestLine ? [requestLine componentsSeparatedByString:@" "] : nil;
            // Only process GET requests for existing files
            if ([parts[0] isEqualToString:@"GET"]) {
                // Use NSURL to strip out query parameters
                NSString *path = [NSURL URLWithString:parts[1] relativeToURL:nil].path;
                NSString *filePath = [_workingDirectory stringByAppendingString:path];
                BOOL isDir = NO;
                if (![[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir] || isDir) {
                    NSLog(@"%@ - 404", requestLine);
                    [self write404];
                } else {
                    NSLog(@"%@ - 200", requestLine);
                    [self write:[NSData dataWithContentsOfFile:filePath] status:YES];
                }
            } else {
                NSLog(@"%@ - 404", requestLine);
                [self write404];
            }
        }
    } else if (aStream == _outputStream && eventCode == NSStreamEventHasSpaceAvailable && _dataToWrite) {
        [self checkIfCanWriteNow];
    }
}

- (void)write404 {
    NSString *body = @"<html><head><title>404 Not Found</title></head><body><h1>Not Found</h1></body></html>";
    [self write:[body dataUsingEncoding:NSUTF8StringEncoding] status:NO];
}

- (void)write:(NSData*)body status:(BOOL)status {
    NSString *state = status ? @"200 OK" : @"404 Not Found";
    NSString *header = [NSString stringWithFormat:@"HTTP/1.0 %@\r\nContent-Length: %lu\r\n\r\n", state, body.length];
    NSMutableData *response = [[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [response appendData:body];
    [self queueWrite:response];
}

- (void)queueWrite:(NSData*)data {
    assert(_dataToWrite == nil);
    assert(data != nil);
    assert(data.length > 0);
    _dataToWrite = data;
    _numBytesToWrite = (NSInteger)data.length;
    [self checkIfCanWriteNow];
}

- (void)checkIfCanWriteNow {
    assert(_dataToWrite != nil);
    if (_numBytesToWrite == 0) {
        // nothing more to write, we're done.
        _dataToWrite = 0;
        _numBytesToWrite = -1;
    } else if (_outputStream.hasSpaceAvailable) {
        [self writeNow];
    }
    // otherwise wait for space available event
}

- (void)writeNow {
    assert(_outputStream != nil);
    assert(_outputStream.hasSpaceAvailable);
    assert(_dataToWrite != nil);
    const uint8_t *bytesOffset = (const uint8_t*)_dataToWrite.bytes + ((NSInteger)_dataToWrite.length - _numBytesToWrite);
    const NSInteger bytesWritten = [_outputStream write:bytesOffset maxLength:(NSUInteger)_numBytesToWrite];
    if (bytesWritten > 0) {
        _numBytesToWrite -= bytesWritten;
        assert(_numBytesToWrite >= 0);
        // wait for next space available event to write more
    } else {
        NSLog(@"Error: bytes written = %ld (%@)", bytesWritten, [NSString stringWithUTF8String:strerror(errno)]);
    }
}

@end

@interface SUTestWebServer () <SUTestWebServerConnectionDelegate> {
    NSMutableArray *_connections;
    NSString* _workingDirectory;
    CFSocketRef _socket;
}

- (void)accept:(CFSocketNativeHandle)address;

@end

static void connectCallback(CFSocketRef __unused s, CFSocketCallBackType type, CFDataRef __unused address, const void *data, void *info) {
    if (type == kCFSocketAcceptCallBack) {
        SUTestWebServer *server = (__bridge SUTestWebServer*)info;
        [server accept:*(const CFSocketNativeHandle*)data];
    }
}

@implementation SUTestWebServer

- (instancetype)initWithPort:(int)port workingDirectory:(NSString*)workingDirectory {
    self = [super init];
    assert(self != nil);
    
    CFSocketContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.info = (__bridge void*)self;
    _socket = CFSocketCreate(NULL, 0, 0, 0, kCFSocketAcceptCallBack, connectCallback, &ctx);
    assert(_socket != NULL);
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = INADDR_ANY;
    
    // will fail if port is in use.
    CFSocketError socketErr = CFSocketSetAddress(_socket, (CFDataRef)[NSData dataWithBytes:&address length:sizeof(address)]);
    if (socketErr != kCFSocketSuccess) {
        NSLog(@"Socket error: %@", [NSString stringWithUTF8String:strerror(errno)]);
        return nil;
    }
    
    _connections = [[NSMutableArray alloc] init];
    _workingDirectory = workingDirectory;

    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, _socket, 0);
    assert(source != NULL);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(source);
    
    return self;
}

- (void)connectionDidClose:(SUTestWebServerConnection *)sender {
    assert(_connections != nil);
    assert([_connections containsObject:sender]);
    [_connections removeObject:sender];
}

- (void)accept:(CFSocketNativeHandle)address {
    SUTestWebServerConnection *conn = [[SUTestWebServerConnection alloc] initWithNativeHandle:address workingDirectory:_workingDirectory delegate:self];
    assert(conn != nil);
    if (conn) {
        [_connections addObject:conn];
    }
}

- (void)close {
    for (SUTestWebServerConnection *conn in _connections) {
        [conn close];
    }
    if (_socket) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
}

@end

#pragma clang diagnostic pop
