#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"

static PLProfiles* current;

@interface PLProfiles()
@end

@implementation PLProfiles

+ (id)defaultProfiles {
    return @{
        @"profiles": @{
            @"(Default)": @{
                @"name": @"(Default)",
                @"lastVersionId": @"latest-release"
            }
        },
        @"selectedProfile": @"(Default)"
    }.mutableCopy;
}

+ (PLProfiles *)current {
    if (!current) {
        [self updateCurrent];
    }
    return current;
}

+ (void)updateCurrent {
    current = [[PLProfiles alloc] initWithCurrentInstance];
}

+ (id)profile:(NSMutableDictionary *)profile resolveKey:(id)key {
    NSString *value = profile[key];
    if (value.length > 0) {
        //NSDebugLog(@"[PLProfiles] Applying %@: \"%@\"", key, value);
        return value;
    }

    NSDictionary *valueDefaults = @{
        @"javaVersion": @"0",
        @"gameDir": @"."
    };
    if (valueDefaults[key]) {
        return valueDefaults[key];
    }

    NSDictionary *prefDefaults = @{
        @"defaultTouchCtrl": @"control.default_ctrl",
        @"defaultGamepadCtrl": @"control.default_gamepad_ctrl",
        @"javaArgs": @"java.java_args",
        @"renderer": @"video.renderer"
    };
    return getPrefObject(prefDefaults[key]);
}

+ (id)resolveKeyForCurrentProfile:(id)key {
    return [self profile:self.current.selectedProfile resolveKey:key];
}

- (id)initWithCurrentInstance {
    self = [super init];
    self.profilePath = [@(getenv("POJAV_GAME_DIR")) stringByAppendingPathComponent:@"launcher_profiles.json"];
    self.profileDict = parseJSONFromFile(self.profilePath);
    if (![self.profileDict isKindOfClass:NSDictionary.class] ||
        self.profileDict[@"NSErrorObject"]) {
        self.profileDict = PLProfiles.defaultProfiles;
        // Save bootstrap profiles only inside a real instance. When every
        // instance has been deleted, POJAV_GAME_DIR intentionally points to
        // no directory and must not recreate a placeholder.
        BOOL isDirectory = NO;
        NSString *parent = self.profilePath.stringByDeletingLastPathComponent;
        if ([NSFileManager.defaultManager fileExistsAtPath:parent
                                               isDirectory:&isDirectory] &&
            isDirectory) {
            [self save];
        }
    }

    return self;
}

- (id)profiles {
    id profiles = self.profileDict[@"profiles"];
    return [profiles isKindOfClass:NSDictionary.class] ? profiles : @{};
}

- (id)selectedProfile {
    NSString *name = self.selectedProfileName;
    if (name.length == 0) return nil;
    id profile = self.profiles[name];
    return [profile isKindOfClass:NSDictionary.class] ? profile : nil;
}

- (NSString *)selectedProfileName {
    id name = self.profileDict[@"selectedProfile"];
    return [name isKindOfClass:NSString.class] ? name : nil;
}

- (void)setSelectedProfileName:(NSString *)name {
    self.profileDict[@"selectedProfile"] = (id)name;
    [self save];
}

- (void)save {
    saveJSONToFile(self.profileDict, self.profilePath);
}

@end
