#import <Security/Security.h>
#import "BaseAuthenticator.h"
#import "../LauncherPreferences.h"
#import "../ios_uikit_bridge.h"
#import "../utils.h"

@implementation BaseAuthenticator

static BaseAuthenticator *current = nil;

+ (id)current {
    if (current == nil) {
        [self loadSavedName:getPrefObject(@"internal.selected_account")];
    }
    return current;
}

+ (void)setCurrent:(BaseAuthenticator *)auth {
    current = auth;
}

+ (NSString *)storageKeyForAuthData:(NSDictionary *)authData {
    BOOL isMicrosoft =
        [authData[@"expiresAt"] longLongValue] > 0 ||
        [authData[@"xuid"] length] > 0 ||
        [authData[@"xboxGamertag"] length] > 0;
    NSString *type = isMicrosoft ? @"microsoft" : @"local";
    NSString *identity = isMicrosoft
        ? (authData[@"xuid"] ?: authData[@"profileId"] ?: authData[@"username"])
        : authData[@"username"];
    if (identity.length == 0) {
        identity = NSUUID.UUID.UUIDString;
    }
    NSCharacterSet *unsafe =
        [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSString *safeIdentity =
        [[identity componentsSeparatedByCharactersInSet:unsafe]
            componentsJoinedByString:@"-"];
    return [NSString stringWithFormat:@"%@__%@", type, safeIdentity];
}

+ (id)loadSavedName:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    NSString *path = [NSString
        stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), name];
    NSMutableDictionary *authData = parseJSONFromFile(path);
    if (authData[@"NSErrorObject"] != nil) {
        NSError *error = ((NSError *)authData[@"NSErrorObject"]);
        if (error.code != NSFileReadNoSuchFileError) {
            showDialog(localize(@"Error", nil), error.localizedDescription);
        }
        return nil;
    }

    NSString *storageKey = [self storageKeyForAuthData:authData];
    BOOL isMicrosoft = [storageKey hasPrefix:@"microsoft__"];
    authData[@"accountType"] = isMicrosoft ? @"microsoft" : @"local";
    authData[@"storageKey"] = storageKey;

    // Migrate legacy username-based files to the stable identity key. Once the
    // new file is safely written, remove the stale username copy so refreshing
    // a Microsoft account cannot make it appear twice.
    if (![name isEqualToString:storageKey]) {
        NSString *migratedPath = [NSString
            stringWithFormat:@"%s/accounts/%@.json",
            getenv("POJAV_HOME"), storageKey];
        NSError *migrationError = nil;
        if (![NSFileManager.defaultManager fileExistsAtPath:migratedPath]) {
            migrationError = saveJSONToFile(authData, migratedPath);
        }
        if (migrationError == nil) {
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        }
        if ([name isEqualToString:getPrefObject(@"internal.selected_account")]) {
            setPrefObject(@"internal.selected_account", storageKey);
        }
    }

    return isMicrosoft
        ? [[MicrosoftAuthenticator alloc] initWithData:authData]
        : [[LocalAuthenticator alloc] initWithData:authData];
}

- (id)initWithData:(NSMutableDictionary *)data {
    current = self = [self init];
    self.authData = data;
    return self;
}

- (id)initWithInput:(NSString *)string {
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    data[@"input"] = string;
    return [self initWithData:data];
}

- (void)loginWithCallback:(Callback)callback {
}

- (void)refreshTokenWithCallback:(Callback)callback {
}

- (BOOL)saveChanges {
    NSError *error;

    [self.authData removeObjectForKey:@"input"];

    NSString *storageKey =
        [BaseAuthenticator storageKeyForAuthData:self.authData];
    BOOL isMicrosoft = [storageKey hasPrefix:@"microsoft__"];
    self.authData[@"accountType"] =
        isMicrosoft ? @"microsoft" : @"local";
    self.authData[@"storageKey"] = storageKey;
    NSString *newPath = [NSString
        stringWithFormat:@"%s/accounts/%@.json",
        getenv("POJAV_HOME"), storageKey];
    NSString *oldUsername = self.authData[@"oldusername"];
    NSMutableDictionary *persistedAuthData = self.authData.mutableCopy;
    [persistedAuthData removeObjectForKey:@"oldusername"];

    error = saveJSONToFile(persistedAuthData, newPath);

    if (error != nil) {
        showDialog(localize(@"localization.error.save_file", nil), error.localizedDescription);
    } else if (isMicrosoft) {
        // A refreshed Microsoft login may have previously been stored under its
        // username. Keep only the canonical xuid/profileId-backed JSON record.
        // Local accounts must never enter this cleanup path: a local account is
        // allowed to have the same username as a Microsoft Minecraft profile.
        NSString *accountsPath = [newPath stringByDeletingLastPathComponent];
        for (NSString *file in [NSFileManager.defaultManager
                contentsOfDirectoryAtPath:accountsPath error:nil]) {
            if (![file hasSuffix:@".json"] ||
                [file isEqualToString:newPath.lastPathComponent]) {
                continue;
            }
            NSString *candidatePath =
                [accountsPath stringByAppendingPathComponent:file];
            NSDictionary *candidate = parseJSONFromFile(candidatePath);
            BOOL candidateIsMicrosoft =
                [candidate[@"accountType"] isEqualToString:@"microsoft"] ||
                [candidate[@"expiresAt"] longLongValue] > 0 ||
                [candidate[@"xuid"] length] > 0 ||
                [candidate[@"xboxGamertag"] length] > 0;
            BOOL sameIdentity =
                [[BaseAuthenticator storageKeyForAuthData:candidate]
                    isEqualToString:storageKey] ||
                ([self.authData[@"xuid"] length] > 0 &&
                    [candidate[@"xuid"] isEqual:self.authData[@"xuid"]]) ||
                ([self.authData[@"profileId"] length] > 0 &&
                    [candidate[@"profileId"] isEqual:self.authData[@"profileId"]]) ||
                (oldUsername.length > 0 &&
                    [candidate[@"username"] isEqualToString:oldUsername]);
            if (candidate[@"NSErrorObject"] == nil &&
                candidateIsMicrosoft && sameIdentity) {
                [NSFileManager.defaultManager
                    removeItemAtPath:candidatePath error:nil];
                NSDebugLog(@"[Account] Removed stale duplicate %@", file);
            }
        }
    }
    [self.authData removeObjectForKey:@"oldusername"];
    return error == nil;
}

@end
