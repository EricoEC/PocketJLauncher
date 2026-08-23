#import "StikDebugEngine.h"

#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

#import "idevice.h"

static NSString *const StikDebugErrorDomain = @"PocketJ.StikDebug";

@implementation StikDebugEngine

+ (instancetype)sharedEngine {
    static StikDebugEngine *engine;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ engine = [StikDebugEngine new]; });
    return engine;
}

- (NSString *)pairingFilePath {
    NSURL *support = [NSFileManager.defaultManager
        URLForDirectory:NSApplicationSupportDirectory
               inDomain:NSUserDomainMask
      appropriateForURL:nil
                 create:YES
                  error:nil];
    NSURL *directory = [support URLByAppendingPathComponent:@"Pairing"
                                                isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    return [[directory URLByAppendingPathComponent:@"pairingFile.plist"] path];
}

- (NSString *)documentsPairingFilePath {
    NSURL *documents = [NSFileManager.defaultManager
        URLForDirectory:NSDocumentDirectory
               inDomain:NSUserDomainMask
      appropriateForURL:nil
                 create:YES
                  error:nil];
    return [[documents URLByAppendingPathComponent:@"pairingFile.plist"] path];
}

- (BOOL)validatePairingData:(NSData *)data error:(NSError **)error {
    if (!data.length) {
        if (error) *error = [NSError errorWithDomain:StikDebugErrorDomain code:-30
            userInfo:@{NSLocalizedDescriptionKey: @"配对文件为空。"}];
        return NO;
    }
    NSError *plistError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:nil error:&plistError];
    if (![plist isKindOfClass:NSDictionary.class]) {
        if (error) *error = plistError ?: [NSError errorWithDomain:StikDebugErrorDomain code:-31
            userInfo:@{NSLocalizedDescriptionKey: @"所选文件不是有效的配对 plist。"}];
        return NO;
    }
    return YES;
}

- (BOOL)writePairingData:(NSData *)data error:(NSError **)error {
    if (![self validatePairingData:data error:error]) return NO;
    if (![data writeToFile:self.pairingFilePath options:NSDataWritingAtomic error:error]) return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                   ofItemAtPath:self.pairingFilePath error:nil];
    return YES;
}

- (BOOL)synchronizePairingFileFromDocuments:(NSError **)error {
    NSString *source = self.documentsPairingFilePath;
    if (![NSFileManager.defaultManager fileExistsAtPath:source]) return self.hasPairingFile;
    NSData *data = [NSData dataWithContentsOfFile:source options:0 error:error];
    if (![self validatePairingData:data error:error]) return NO;
    NSData *current = [NSData dataWithContentsOfFile:self.pairingFilePath];
    if ([current isEqualToData:data]) return YES;
    return [self writePairingData:data error:error];
}

- (BOOL)hasPairingFile {
    return [NSFileManager.defaultManager fileExistsAtPath:self.pairingFilePath];
}

- (BOOL)importPairingFileAtURL:(NSURL *)URL error:(NSError **)error {
    BOOL accessing = [URL startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:URL options:0 error:error];
    if (accessing) [URL stopAccessingSecurityScopedResource];
    if (![self writePairingData:data error:error]) return NO;
    if (![data writeToFile:self.documentsPairingFilePath
                   options:NSDataWritingAtomic error:error]) return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                   ofItemAtPath:self.documentsPairingFilePath error:nil];
    return YES;
}

- (BOOL)deletePairingFile:(NSError **)error {
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *path in @[self.pairingFilePath, self.documentsPairingFilePath]) {
        if ([manager fileExistsAtPath:path] && ![manager removeItemAtPath:path error:error]) return NO;
    }
    return YES;
}

- (NSURL *)exportablePairingFileURL:(NSError **)error {
    if (![self synchronizePairingFileFromDocuments:error] && !self.hasPairingFile) return nil;
    NSData *data = [NSData dataWithContentsOfFile:self.pairingFilePath options:0 error:error];
    if (![self validatePairingData:data error:error]) return nil;
    if (![data writeToFile:self.documentsPairingFilePath
                   options:NSDataWritingAtomic error:error]) return nil;
    return [NSURL fileURLWithPath:self.documentsPairingFilePath];
}

- (void)checkLocalDevVPNWithCompletion:(void (^)(BOOL connected))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int descriptor = socket(AF_INET, SOCK_STREAM, 0);
        BOOL connected = NO;
        if (descriptor >= 0) {
            struct timeval timeout = {.tv_sec = 0, .tv_usec = 600000};
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
            struct sockaddr_in address = {0};
            address.sin_family = AF_INET;
            address.sin_port = htons(49152);
            if (inet_pton(AF_INET, "10.7.0.1", &address.sin_addr) == 1) {
                connected = connect(descriptor, (const struct sockaddr *)&address,
                                    sizeof(address)) == 0;
            }
            close(descriptor);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(connected);
        });
    });
}

- (NSError *)consumeError:(IdeviceFfiError *)ffi fallback:(NSString *)fallback {
    if (!ffi) return nil;
    NSString *message = ffi->message ? [NSString stringWithUTF8String:ffi->message] : fallback;
    NSError *error = [NSError errorWithDomain:StikDebugErrorDomain
        code:ffi->code userInfo:@{NSLocalizedDescriptionKey: message ?: fallback}];
    idevice_error_free(ffi);
    return error;
}

- (NSError *)sendCommand:(const char *)command
                  proxy:(struct DebugProxyHandle *)proxy
                response:(NSString **)responseString {
    struct DebugserverCommandHandle *handle = debugserver_command_new(command, NULL, 0);
    if (!handle) {
        return [NSError errorWithDomain:StikDebugErrorDomain code:-20
            userInfo:@{NSLocalizedDescriptionKey: @"无法创建 debugserver 命令。"}];
    }
    char *response = NULL;
    IdeviceFfiError *ffi = debug_proxy_send_command(proxy, handle, &response);
    debugserver_command_free(handle);
    NSError *error = [self consumeError:ffi fallback:@"debugserver 命令执行失败。"];
    if (response) {
        if (responseString) *responseString = [NSString stringWithUTF8String:response];
        idevice_string_free(response);
    }
    return error;
}

- (void)enableJITForCurrentProcessWithCompletion:
        (void (^)(BOOL success, NSString *message))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *message = nil;
        BOOL success = [self enableJITSynchronously:&message];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(success, message ?: @"");
        });
    });
}

- (BOOL)enableJITSynchronously:(NSString **)message {
    // debugserver suspends a process as soon as vAttach succeeds.  Running the
    // matching detach command from that same process is therefore impossible:
    // the caller is already suspended.  Keep this guard even though the UI now
    // delegates to an independent StikDebug process; it prevents future callers
    // from reintroducing the deterministic self-attach deadlock.
    if (message) {
        *message = @"不能在 PocketJ Launcher 进程内附加它自己。请使用独立 JIT 执行进程。";
    }
    return NO;

#if 0
    if (@available(iOS 17.4, *)) {
    } else {
        if (message) *message = @"内置 StikDebug 仅支持 iOS 17.4 及以上系统。";
        return NO;
    }
    if (!self.hasPairingFile) {
        if (message) *message = @"请先导入本机配对文件。";
        return NO;
    }

    struct RpPairingFileHandle *pairing = NULL;
    struct AdapterHandle *adapter = NULL;
    struct RsdHandshakeHandle *handshake = NULL;
    struct RemoteServerHandle *remote = NULL;
    struct DebugProxyHandle *debugProxy = NULL;
    char attach[64] = {0};
    NSString *attachResponse = nil;
    NSError *error = [self consumeError:
        rp_pairing_file_read(self.pairingFilePath.fileSystemRepresentation, &pairing)
        fallback:@"无法读取配对文件。"];
    if (error) goto cleanup;

    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_port = htons(49152);
    if (inet_pton(AF_INET, "10.7.0.1", &address.sin_addr) != 1) {
        error = [NSError errorWithDomain:StikDebugErrorDomain code:-18
            userInfo:@{NSLocalizedDescriptionKey: @"LocalDevVPN 地址无效。"}];
        goto cleanup;
    }
    error = [self consumeError:tunnel_create_rppairing(
        (const struct sockaddr *)&address, sizeof(address), "PocketJLauncher",
        pairing, NULL, NULL, &adapter, &handshake)
        fallback:@"无法建立调试隧道，请确认 LocalDevVPN 已开启。"];
    if (error) goto cleanup;

    error = [self consumeError:remote_server_connect_rsd(adapter, handshake, &remote)
        fallback:@"无法连接 RemoteServer。"];
    if (error) goto cleanup;
    error = [self consumeError:debug_proxy_connect_rsd(adapter, handshake, &debugProxy)
        fallback:@"无法连接 DebugProxy。"];
    if (error) goto cleanup;

    debug_proxy_send_ack(debugProxy);
    debug_proxy_send_ack(debugProxy);
    error = [self sendCommand:"QStartNoAckMode" proxy:debugProxy response:nil];
    if (error) goto cleanup;
    debug_proxy_set_ack_mode(debugProxy, 0);

    snprintf(attach, sizeof(attach), "vAttach;%x", getpid());
    error = [self sendCommand:attach proxy:debugProxy response:&attachResponse];
    if (error) goto cleanup;
    if (![attachResponse hasPrefix:@"T"] && ![attachResponse hasPrefix:@"OK"]) {
        error = [NSError errorWithDomain:StikDebugErrorDomain code:-21
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"调试器未能附加当前进程：%@",
                    attachResponse ?: @"无响应"]}];
        goto cleanup;
    }
    [self sendCommand:"D" proxy:debugProxy response:nil];

cleanup:
    if (debugProxy) debug_proxy_free(debugProxy);
    if (remote) remote_server_free(remote);
    if (handshake) rsd_handshake_free(handshake);
    if (adapter) adapter_free(adapter);
    if (pairing) rp_pairing_file_free(pairing);
    if (error) {
        if (message) *message = error.localizedDescription;
        return NO;
    }
    if (message) *message = @"JIT 已成功为当前 PocketJ Launcher 进程启用。";
    return YES;
#endif
}

@end
