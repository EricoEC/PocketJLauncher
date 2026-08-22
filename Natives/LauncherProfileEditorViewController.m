#import "LauncherNavigationController.h"
#import "JavaLauncher.h"
#import "installer/FabricUtils.h"
#import "LauncherPreferences.h"
#import "LauncherProfileEditorViewController.h"
#import "MinecraftResourceUtils.h"
#import "PickTextField.h"
#import "PLProfiles.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface LauncherProfileEditorViewController()<UIPickerViewDataSource, UIPickerViewDelegate>
@property(nonatomic) NSString* oldName;
@property(nonatomic, copy) NSString *originalInstanceName;

@property(nonatomic) NSArray<NSDictionary *> *versionList;
@property(nonatomic) PickTextField* versionTextField;
@property(nonatomic) UISegmentedControl* versionTypeControl;
@property(nonatomic) UIPickerView* versionPickerView;
@property(nonatomic) UIToolbar* versionPickerToolbar;
@property(nonatomic) int versionSelectedAt;
@property(nonatomic, copy) NSString *originalLoader;
@property(nonatomic, copy) NSString *originalVersion;
@property(nonatomic, copy) NSString *originalMinecraftVersion;
@property(nonatomic, copy) NSString *originalLoaderVersion;
@property(nonatomic, strong) NSMutableArray<NSString *> *loaderVersionList;
@property(nonatomic) BOOL loaderVersionsLoading;
@property(nonatomic, strong) NSDictionary *loaderVersionItem;
@property(nonatomic, strong) NSMutableArray<NSString *> *javaVersionKeys;
@property(nonatomic, strong) NSMutableArray<NSString *> *javaVersionNames;
@end

@implementation LauncherProfileEditorViewController

- (NSString *)pocketjEffectiveDefaultRendererNameForMinecraftVersion:(NSString *)minecraftVersion {
    NSArray<NSString *> *keys = getRendererKeys(NO);
    NSArray<NSString *> *names = getRendererNames(NO);
    NSString *globalRenderer = getPrefObject(@"video.renderer") ?: @"auto";

    if (![globalRenderer isEqualToString:@"auto"]) {
        NSUInteger index = [keys indexOfObject:globalRenderer];
        if (index != NSNotFound && index < names.count) return names[index];
    }

    int requiredJava = PocketJRequiredJavaVersionForMinecraft(minecraftVersion ?: @"");
    if (requiredJava >= 25) {
        NSUInteger index = [keys indexOfObject:@ RENDERER_NAME_MTL_ANGLE];
        return index != NSNotFound && index < names.count ? names[index] : @"ANGLE";
    }
    if (requiredJava >= 17) {
        NSUInteger index = [keys indexOfObject:@ RENDERER_NAME_MOBILEGLUES];
        return index != NSNotFound && index < names.count ? names[index] : @"MobileGlues";
    }
    NSUInteger index = [keys indexOfObject:@ RENDERER_NAME_GL4ES];
    return index != NSNotFound && index < names.count ? names[index] : @"gl4es 1.1.4";
}

- (void)viewDidLoad {
    // Setup navigation bar & appearance
    self.title = localize(@"Edit profile", nil);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(actionDone)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = YES;
    self.prefSectionsVisible = YES;
    self.originalInstanceName = self.instanceName.copy;
    self.originalVersion = [self.profile[@"lastVersionId"] copy] ?: @"";
    NSString *versionLower = [self.profile[@"lastVersionId"] lowercaseString] ?: @"";
    self.originalLoader = [versionLower containsString:@"neoforge"] ? @"neoforge" :
        ([versionLower containsString:@"fabric"] ? @"fabric" :
        ([versionLower containsString:@"quilt"] ? @"quilt" :
        ([versionLower containsString:@"forge"] ? @"forge" : @"vanilla")));
    NSString *versionJSONPath = [NSString stringWithFormat:
        @"%s/versions/%@/%@.json", getenv("POJAV_GAME_DIR"),
        self.originalVersion, self.originalVersion];
    NSDictionary *versionJSON = parseJSONFromFile(versionJSONPath);
    NSString *baseVersion = self.profile[@"pocketjMinecraftVersion"];
    if (!baseVersion.length) baseVersion = versionJSON[@"inheritsFrom"];
    if (!baseVersion.length) baseVersion = self.originalVersion;
    self.profile[@"pocketjMinecraftVersion"] = baseVersion ?: @"";
    self.originalMinecraftVersion = baseVersion ?: @"";
    NSString *declaredLoader = self.profile[@"pocketjLoader"];
    if (![self.originalLoader isEqualToString:@"vanilla"]) {
        declaredLoader = self.originalLoader;
    }
    self.profile[@"pocketjLoader"] = declaredLoader.length
        ? declaredLoader : @"vanilla";
    if (![self.profile[@"pocketjLoaderVersion"] isKindOfClass:NSString.class]) {
        self.profile[@"pocketjLoaderVersion"] = @"";
    }
    NSString *storedLoaderVersion = self.profile[@"pocketjLoaderVersion"];
    if (!storedLoaderVersion.length) {
        NSString *installed = self.originalVersion.lowercaseString;
        NSRange marker = NSMakeRange(NSNotFound, 0);
        if ([self.originalLoader isEqualToString:@"forge"]) marker = [installed rangeOfString:@"-forge-"];
        else if ([self.originalLoader isEqualToString:@"neoforge"]) marker = [installed rangeOfString:@"neoforge-"];
        else if ([self.originalLoader isEqualToString:@"fabric"]) marker = [installed rangeOfString:@"fabric-loader-"];
        else if ([self.originalLoader isEqualToString:@"quilt"]) marker = [installed rangeOfString:@"quilt-loader-"];
        if (marker.location != NSNotFound) {
            NSString *tail = [self.originalVersion substringFromIndex:NSMaxRange(marker)];
            if ([self.originalLoader isEqualToString:@"fabric"] ||
                [self.originalLoader isEqualToString:@"quilt"]) {
                NSString *suffix = [@"-" stringByAppendingString:baseVersion ?: @""];
                if ([tail hasSuffix:suffix]) tail = [tail substringToIndex:tail.length - suffix.length];
            }
            self.profile[@"pocketjLoaderVersion"] = tail ?: @"";
        }
    }
    self.originalLoaderVersion = self.profile[@"pocketjLoaderVersion"] ?: @"";
    self.loaderVersionList = [NSMutableArray array];
    // Setup preference getter and setter
    __weak LauncherProfileEditorViewController *weakSelf = self;
    self.getPreference = ^id(NSString *section, NSString *key){
        if ([key isEqualToString:@"instanceDisplayName"]) {
            return weakSelf.instanceName ?: @"default";
        }
        NSString *value = weakSelf.profile[key];
        if ([key isEqualToString:@"javaVersion"] && !value.length) {
            return [NSString stringWithFormat:@"%d", [weakSelf recommendedJavaVersion]];
        }
        if ([key isEqualToString:@"pocketjLoaderVersion"] && !value.length) {
            return weakSelf.loaderVersionsLoading
                ? localize(@"正在获取版本…", nil)
                : localize(@"没有兼容的加载器版本", nil);
        }
        if (value.length > 0 || ![weakSelf isPickFieldAtSection:section key:key]) {
            return value;
        } else {
            return @"(default)";
        }
    };
    self.setPreference = ^(NSString *section, NSString *key, NSString *value){
        NSString *previousValue = weakSelf.profile[key];
        if ([key isEqualToString:@"instanceDisplayName"]) {
            weakSelf.instanceName = value;
            return;
        }
        if ([value isEqualToString:@"(default)"] && [weakSelf isPickFieldAtSection:section key:key]) {
            [weakSelf.profile removeObjectForKey:key];
        } else if (value) {
            weakSelf.profile[key] = value;
        }
        if ([key isEqualToString:@"pocketjLoader"]) {
            if (![previousValue isEqualToString:value]) {
                weakSelf.profile[@"pocketjLoaderVersion"] = @"";
            }
            weakSelf.profile[@"pocketjLoaderInstallPending"] =
                @(![value isEqualToString:@"vanilla"]);
            [weakSelf fetchLoaderVersions];
        } else if ([key isEqualToString:@"pocketjMinecraftVersion"]) {
            if (![previousValue isEqualToString:value]) {
                weakSelf.profile[@"pocketjLoaderVersion"] = @"";
            }
            [weakSelf refreshJavaDefaultLabels];
            [weakSelf fetchLoaderVersions];
        }
    };

    // Obtain all the lists
    self.oldName = self.getPreference(nil, @"name");
    if ([self.oldName length] == 0) {
        self.setPreference(nil, @"name", localize(@"新实例", nil));
    }
    NSArray *rendererKeys = getRendererKeys(YES);
    NSMutableArray *rendererList = [getRendererNames(YES) mutableCopy];
    NSString *minecraftVersion = self.profile[@"pocketjMinecraftVersion"] ?: self.profile[@"lastVersionId"];
    NSString *effectiveRenderer = [self pocketjEffectiveDefaultRendererNameForMinecraftVersion:minecraftVersion];
    rendererList[0] = [NSString stringWithFormat:localize(@"%@（默认）", nil), effectiveRenderer];
    NSArray *touchControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")]];
    NSArray *gamepadControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap/gamepads", getenv("POJAV_HOME")]];
    NSMutableArray *touchControlNames = touchControlList.mutableCopy;
    NSMutableArray *gamepadControlNames = gamepadControlList.mutableCopy;
    if (touchControlNames.count > 0) touchControlNames[0] = localize(@"默认", nil);
    if (gamepadControlNames.count > 0) gamepadControlNames[0] = localize(@"默认", nil);
    self.javaVersionKeys = [NSMutableArray array];
    for (NSString *key in [getPrefObject(@"java.java_homes") allKeys]) {
        if (key.intValue > 0) [self.javaVersionKeys addObject:key];
    }
    [self.javaVersionKeys sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        return [@(left.intValue) compare:@(right.intValue)];
    }];
    self.javaVersionNames = [NSMutableArray array];
    [self refreshJavaDefaultLabels];

    // Minecraft versions use the original wheel picker, hosted in an adaptive
    // sheet so its geometry remains centered on every iPhone size.
    id typeVersionPicker = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item){
        self.typeTextField(cell, section, key, item);
        PickTextField *textField = (id)cell.accessoryView;
        weakSelf.versionTextField = textField;
        if (!weakSelf.versionPickerView) [weakSelf setupVersionPicker];
        textField.inputView = weakSelf.versionPickerView;
        textField.inputAccessoryView = weakSelf.versionPickerToolbar;
        textField.prefersMediumSheet = YES;
        [weakSelf changeVersionType:nil];
    };

    NSMutableArray *generalItems = [NSMutableArray arrayWithArray:@[
            // General settings
            @{@"key": @"instanceDisplayName",
              @"icon": @"tag",
              @"title": @"preference.profile.title.name",
              @"type": self.typeTextField,
              @"placeholder": self.instanceName ?: @"default"
            }
    ]];
    if (!self.hidesMinecraftVersion) {
        [generalItems addObject:@{@"key": @"pocketjMinecraftVersion",
              @"icon": @"archivebox",
              @"title": @"preference.profile.title.version",
              @"type": typeVersionPicker,
              // Imported instances are allowed to start without a detected
              // version, but NSDictionary literals may never contain nil.
              @"placeholder":
                  self.getPreference(nil, @"pocketjMinecraftVersion") ?: @"",
              @"customClass": PickTextField.class
        }];
    }
    NSMutableArray *loaderItems = [NSMutableArray arrayWithArray:@[
        @{@"key": @"loader_header"},
        @{
        @"key": @"pocketjLoader",
        @"icon": @"shippingbox",
        @"title": @"模组加载器",
        @"type": self.typePickField,
        @"pickKeys": @[@"vanilla", @"fabric", @"forge", @"neoforge", @"quilt"],
        @"pickList": @[
            localize(@"Vanilla（无模组加载器）", nil),
            @"Fabric", @"Forge", @"NeoForge", @"Quilt"
        ],
        },
        (self.loaderVersionItem = @{
            @"key": @"pocketjLoaderVersion",
            @"icon": @"number.square",
            @"title": @"加载器版本",
            @"type": self.typePickField,
            @"pickKeys": self.loaderVersionList,
            @"pickList": self.loaderVersionList,
            @"enableCondition": ^BOOL{
                return !weakSelf.loaderVersionsLoading &&
                    ![weakSelf.profile[@"pocketjLoader"] isEqualToString:@"vanilla"] &&
                    weakSelf.loaderVersionList.count > 0;
            }
        })
    ]];
    NSMutableArray *advancedItems = [NSMutableArray arrayWithArray:@[
            // Video and renderer settings
            @{@"key": @"renderer",
              @"icon": @"cpu",
              @"type": self.typePickField,
              @"pickKeys": rendererKeys,
              @"pickList": rendererList
            },
            // Control settings
            @{@"key": @"defaultTouchCtrl",
              @"icon": @"hand.tap",
              @"title": @"preference.profile.title.default_touch_control",
              @"type": self.typePickField,
              @"pickKeys": touchControlList,
              @"pickList": touchControlNames
            },
            @{@"key": @"defaultGamepadCtrl",
              @"icon": @"gamecontroller",
              @"title": @"preference.profile.title.default_gamepad_control",
              @"type": self.typePickField,
              @"pickKeys": gamepadControlList,
              @"pickList": gamepadControlNames
            },
            // Java tweaks
            @{@"key": @"javaVersion",
              @"icon": @"cube",
              @"title": @"preference.manage_runtime.header.default",
              @"type": self.typePickField,
              @"pickKeys": self.javaVersionKeys,
              @"pickList": self.javaVersionNames
            },
            @{@"key": @"javaArgs",
              @"icon": @"slider.vertical.3",
              @"title": @"preference.title.java_args",
              @"type": self.typeTextField,
              @"placeholder": localize(@"默认", nil)
            }
    ]];
    [generalItems insertObject:@{@"key": @"instance_general_header"}
                       atIndex:0];
    [advancedItems insertObject:@{@"key": @"advanced_header"} atIndex:0];
    self.prefSections = @[@"instance_general", @"loader", @"advanced"];
    self.prefContents = @[generalItems, loaderItems, advancedItems];

    [super viewDidLoad];
    self.prefSectionsVisibility = [@[@YES, @YES, @NO] mutableCopy];
    [self.tableView reloadData];
    [self fetchLoaderVersions];
}

- (int)recommendedJavaVersion {
    NSString *minecraftVersion = self.profile[@"pocketjMinecraftVersion"] ?: @"";
    if ([minecraftVersion isEqualToString:@"latest-release"]) {
        minecraftVersion = getPrefObject(@"internal.latest_version.release") ?: minecraftVersion;
    } else if ([minecraftVersion isEqualToString:@"latest-snapshot"]) {
        minecraftVersion = getPrefObject(@"internal.latest_version.snapshot") ?: minecraftVersion;
    }
    int required = PocketJRequiredJavaVersionForMinecraft(minecraftVersion);
    for (NSString *candidate in self.javaVersionKeys) {
        if (candidate.intValue >= required) return candidate.intValue;
    }
    return self.javaVersionKeys.lastObject.intValue ?: required;
}

- (void)refreshJavaDefaultLabels {
    if (!self.javaVersionKeys) return;
    int recommended = [self recommendedJavaVersion];
    [self.javaVersionNames removeAllObjects];
    for (NSString *version in self.javaVersionKeys) {
        NSString *name = [NSString stringWithFormat:@"Java %@", version];
        if (version.intValue == recommended) {
            name = [name stringByAppendingFormat:@"（%@）", localize(@"默认", nil)];
        }
        [self.javaVersionNames addObject:name];
    }
}

- (void)actionClose {
    if (self.creatingNewInstance && self.cancelCreation) {
        self.cancelCreation();
    }
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)reloadLoaderSection {
    if (self.prefContents.count == 3) {
        NSArray *current = self.prefContents[1];
        NSArray *base = current.count >= 2 ? [current subarrayWithRange:NSMakeRange(0, 2)] : current;
        BOOL vanilla = [self.profile[@"pocketjLoader"] isEqualToString:@"vanilla"];
        NSArray *loaderSection = vanilla ? base : [base arrayByAddingObject:self.loaderVersionItem];
        self.prefContents = @[self.prefContents[0], loaderSection, self.prefContents[2]];
    }
    if (self.tableView && self.prefSections.count > 1) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                      withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (NSArray<NSString *> *)versionsFromMavenMetadata:(NSData *)data
                                             loader:(NSString *)loader
                                   minecraftVersion:(NSString *)minecraftVersion {
    NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<version>([^<]+)</version>" options:0 error:nil];
    NSMutableArray *result = [NSMutableArray array];
    for (NSTextCheckingResult *match in [regex matchesInString:xml options:0 range:NSMakeRange(0, xml.length)]) {
        NSString *value = [xml substringWithRange:[match rangeAtIndex:1]];
        NSString *lower = value.lowercaseString;
        if ([lower containsString:@"mdk"] || [lower containsString:@"javadoc"] ||
            [lower containsString:@"sources"] || [lower containsString:@"installer"]) continue;
        if ([loader isEqualToString:@"forge"]) {
            NSString *prefix = [minecraftVersion stringByAppendingString:@"-"];
            if (![value hasPrefix:prefix]) continue;
            value = [value substringFromIndex:prefix.length];
        } else {
            NSArray *parts = [minecraftVersion componentsSeparatedByString:@"."];
            if (parts.count < 2) continue;
            NSString *prefix = [NSString stringWithFormat:@"%@.%@.", parts[1], parts.count > 2 ? parts[2] : @"0"];
            if (![value hasPrefix:prefix]) continue;
        }
        if (value.length && ![result containsObject:value]) [result addObject:value];
    }
    return result;
}

- (void)fetchLoaderVersions {
    NSString *loader = self.profile[@"pocketjLoader"] ?: @"vanilla";
    NSString *minecraftVersion = self.profile[@"pocketjMinecraftVersion"] ?: @"";
    NSString *configuredMinecraftVersion = minecraftVersion;
    if ([minecraftVersion isEqualToString:@"latest-release"]) {
        minecraftVersion = getPrefObject(@"internal.latest_version.release") ?: minecraftVersion;
    } else if ([minecraftVersion isEqualToString:@"latest-snapshot"]) {
        minecraftVersion = getPrefObject(@"internal.latest_version.snapshot") ?: minecraftVersion;
    }
    if ([loader isEqualToString:@"vanilla"] || !minecraftVersion.length) {
        self.loaderVersionsLoading = NO;
        [self.loaderVersionList removeAllObjects];
        self.profile[@"pocketjLoaderVersion"] = @"";
        [self reloadLoaderSection];
        return;
    }
    self.loaderVersionsLoading = YES;
    [self reloadLoaderSection];
    NSString *urlString = nil;
    BOOL maven = NO;
    if ([loader isEqualToString:@"fabric"]) urlString = [NSString stringWithFormat:@"https://meta.fabricmc.net/v2/versions/loader/%@", minecraftVersion];
    else if ([loader isEqualToString:@"quilt"]) urlString = [NSString stringWithFormat:@"https://meta.quiltmc.org/v3/versions/loader/%@", minecraftVersion];
    else if ([loader isEqualToString:@"forge"]) {
        urlString = @"https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"; maven = YES;
    } else if ([loader isEqualToString:@"neoforge"]) {
        urlString = @"https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml"; maven = YES;
    }
    if (!urlString) return;
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlString]
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSMutableArray<NSString *> *versions = [NSMutableArray array];
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class]
            ? (NSHTTPURLResponse *)response : nil;
        if (data.length && !error && (!http || http.statusCode == 200)) {
            if (maven) {
                [versions addObjectsFromArray:[weakSelf versionsFromMavenMetadata:data loader:loader minecraftVersion:minecraftVersion]];
                // Maven metadata is oldest-first. The picker should offer the
                // current supported loader before historical builds.
                versions = [NSMutableArray arrayWithArray:versions.reverseObjectEnumerator.allObjects];
            } else {
                NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                for (NSDictionary *entry in [json isKindOfClass:NSArray.class] ? json : @[]) {
                    NSString *value = entry[@"version"];
                    NSDictionary *loaderInfo = [entry[@"loader"] isKindOfClass:NSDictionary.class]
                        ? entry[@"loader"] : nil;
                    if (loaderInfo) {
                        // Fabric/Quilt return loader+game combinations here.
                        // Exclude preview loader builds from the normal picker.
                        if (loaderInfo[@"stable"] && ![loaderInfo[@"stable"] boolValue]) continue;
                        value = loaderInfo[@"version"];
                    }
                    if (value.length && ![versions containsObject:value]) [versions addObject:value];
                }
            }
            if (versions.count > 30) {
                [versions removeObjectsInRange:NSMakeRange(30, versions.count - 30)];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakSelf.profile[@"pocketjLoader"] isEqualToString:loader] ||
                ![weakSelf.profile[@"pocketjMinecraftVersion"] isEqualToString:configuredMinecraftVersion]) return;
            weakSelf.loaderVersionsLoading = NO;
            [weakSelf.loaderVersionList removeAllObjects];
            [weakSelf.loaderVersionList addObjectsFromArray:versions];
            NSString *current = weakSelf.profile[@"pocketjLoaderVersion"];
            if (![versions containsObject:current]) weakSelf.profile[@"pocketjLoaderVersion"] = versions.firstObject ?: @"";
            [weakSelf reloadLoaderSection];
        });
    }] resume];
}

- (void)actionDone {
    // We might be saving without ending editing, so make sure textFieldDidEndEditing is always called
    UITextField *currentTextField = [self performSelector:@selector(_firstResponder)];
    if ([currentTextField isKindOfClass:UITextField.class] && [currentTextField isDescendantOfView:self.tableView]) {
        [self textFieldDidEndEditing:currentTextField];
    }

    NSString *selectedVersion = [self.profile[@"pocketjMinecraftVersion"]
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // latest-* is only a picker alias. Persist the concrete Mojang version so
    // runtime selection, loader compatibility and subsequent downloads all
    // operate on the same immutable version identifier.
    NSString *resolvedVersion = nil;
    if ([selectedVersion isEqualToString:@"latest-release"]) {
        resolvedVersion = getPrefObject(@"internal.latest_version.release");
    } else if ([selectedVersion isEqualToString:@"latest-snapshot"]) {
        resolvedVersion = getPrefObject(@"internal.latest_version.snapshot");
    }
    if (resolvedVersion.length) {
        selectedVersion = resolvedVersion;
        self.profile[@"pocketjMinecraftVersion"] = resolvedVersion;
        self.versionTextField.text = resolvedVersion;
    }
    if (!self.hidesMinecraftVersion && selectedVersion.length == 0) {
        showDialog(localize(@"尚未配置 Minecraft 版本", nil),
            localize(@"请选择一个 Minecraft 版本后再保存。", nil));
        return;
    }

    NSString *newInstanceName = [self.instanceName
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (newInstanceName.length == 0 ||
        [newInstanceName isEqualToString:@"."] ||
        [newInstanceName isEqualToString:@".."] ||
        [newInstanceName containsString:@"/"]) {
        showDialog(localize(@"实例名称无效", nil),
            localize(@"实例名称不能为空，也不能包含斜杠。", nil));
        return;
    }
    if (![newInstanceName isEqualToString:self.originalInstanceName]) {
        NSString *errorMessage = nil;
        BOOL renamed = NO;
        if (self.renameInstance) {
            renamed = self.renameInstance(self.originalInstanceName,
                                          newInstanceName, &errorMessage);
        } else {
            NSString *root = [NSString stringWithFormat:
                @"%s/instances", getenv("POJAV_HOME")];
            NSString *oldPath =
                [root stringByAppendingPathComponent:self.originalInstanceName];
            NSString *newPath =
                [root stringByAppendingPathComponent:newInstanceName];
            if ([NSFileManager.defaultManager fileExistsAtPath:newPath]) {
                errorMessage = localize(@"已重名，请换个名字。", nil);
            } else {
                NSError *moveError = nil;
                renamed = [NSFileManager.defaultManager
                    moveItemAtPath:oldPath toPath:newPath error:&moveError];
                errorMessage = moveError.localizedDescription;
                if (renamed) {
                    setPrefObject(@"general.game_directory", newInstanceName);
                    NSString *gamePath = @(getenv("POJAV_GAME_DIR"));
                    [NSFileManager.defaultManager
                        removeItemAtPath:gamePath error:nil];
                    [NSFileManager.defaultManager
                        createSymbolicLinkAtPath:gamePath
                        withDestinationPath:newPath error:nil];
                    [NSFileManager.defaultManager
                        changeCurrentDirectoryPath:gamePath];
                    toggleIsolatedPref(NO);
                    [PLProfiles updateCurrent];
                }
            }
        }
        if (!renamed) {
            showDialog(localize(@"无法重命名实例", nil),
                errorMessage ?: localize(@"已重名，请换个名字。", nil));
            return;
        }
        self.instanceName = newInstanceName;
        self.originalInstanceName = newInstanceName;
    }

    if ([self.profile[@"name"] length] == 0 && self.oldName.length > 0) {
        // Return to its old name
        self.profile[@"name"] = self.oldName;
    }

    NSString *selectedLoader = self.profile[@"pocketjLoader"] ?: @"vanilla";
    NSString *loaderVersion = self.profile[@"pocketjLoaderVersion"] ?: @"";
    if (![selectedLoader isEqualToString:@"vanilla"] && loaderVersion.length == 0) {
        showDialog(localize(@"尚未选择加载器版本", nil),
            localize(@"请选择一个加载器版本后再保存。", nil));
        return;
    }
    BOOL unchangedInstalledLoader =
        ![selectedLoader isEqualToString:@"vanilla"] &&
        [selectedLoader isEqualToString:self.originalLoader] &&
        [selectedVersion isEqualToString:self.originalMinecraftVersion] &&
        [loaderVersion isEqualToString:self.originalLoaderVersion];
    self.profile[@"lastVersionId"] = unchangedInstalledLoader
        ? self.originalVersion : selectedVersion;
    self.profile[@"pocketjLoaderInstallPending"] =
        @(![selectedLoader isEqualToString:@"vanilla"] && !unchangedInstalledLoader);
    if ([selectedLoader isEqualToString:@"vanilla"]) {
        self.profile[@"pocketjLoaderVersion"] = @"";
        self.profile[@"pocketjLoaderInstallPending"] = @NO;
    }

    // A freshly-created instance comes from PLProfiles.defaultProfiles, whose
    // nested profiles dictionary is immutable. Keep the core model untouched
    // and give this UI save operation a mutable working container.
    if (![PLProfiles.current.profiles isKindOfClass:
            NSMutableDictionary.class]) {
        PLProfiles.current.profileDict[@"profiles"] =
            PLProfiles.current.profiles.mutableCopy;
    }

    if ([self.oldName isEqualToString:self.profile[@"name"]]) {
        // Not a rename, directly create/replace
        PLProfiles.current.profiles[self.oldName] = self.profile;
    } else if (!PLProfiles.current.profiles[self.profile[@"name"]]) {
        // A rename, remove then re-add to update its key name
        if (self.oldName.length > 0) {
            [PLProfiles.current.profiles removeObjectForKey:self.oldName];
        }
        PLProfiles.current.profiles[self.profile[@"name"]] = self.profile;
        // Update selected name
        if ([PLProfiles.current.selectedProfileName isEqualToString:self.oldName]) {
            PLProfiles.current.selectedProfileName = self.profile[@"name"];
        }
    } else {
        // Cancel rename since a profile with the same name already exists
        showDialog(localize(@"Error", nil), localize(@"profile.error.name_exists", nil));
        // Skip dismissing this view controller
        return;
    }

    // The newly-created Fabric/Vanilla profile must become the selected
    // profile immediately. Otherwise the UI keeps reading the bootstrap
    // `(Default)` profile, whose version is `latest-release`.
    NSString *savedProfileName = self.profile[@"name"];
    if (savedProfileName.length > 0) {
        NSMutableDictionary *profileRoot =
            (NSMutableDictionary *)PLProfiles.current.profileDict;
        profileRoot[@"selectedProfile"] = savedProfileName;
    }
    [PLProfiles.current save];
    [NSNotificationCenter.defaultCenter
        postNotificationName:@"LauncherProfilesDidChangeNotification"
                      object:nil];
    self.creatingNewInstance = NO;
    if (self.creationDidFinish) self.creationDidFinish();
    [self actionClose];
    // The launch page owns loader installation. Saving never opens another UI.

    // Dismissing naturally calls the presenting instance list's
    // viewWillAppear. Do not assume a split-view hierarchy here: the modern
    // tab shell presents this editor from a regular navigation controller.
}

- (BOOL)isPickFieldAtSection:(NSString *)section key:(NSString *)key {
    for (NSArray<NSDictionary *> *items in self.prefContents) {
        NSDictionary *pref = [items filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"(key == %@)", key]].firstObject;
        if (pref) return pref[@"type"] == self.typePickField;
    }
    return NO;
}

- (NSArray *)listFilesAtPath:(NSString *)path {
    NSMutableArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil].mutableCopy;
    for (int i = 0; i < files.count;) {
        if ([files[i] hasSuffix:@".json"]) {
            i++;
        } else {
            [files removeObjectAtIndex:i];
        }
    }
    [files insertObject:@"(default)" atIndex:0];
    return files;
}

#pragma mark Version picker

- (void)applyMinecraftVersion:(NSString *)versionId {
    if (!versionId.length) return;
    void (^apply)(void) = ^{
        self.versionTextField.text = versionId;
        self.profile[@"pocketjMinecraftVersion"] = versionId;
        self.profile[@"pocketjLoaderVersion"] = @"";
        [self refreshJavaDefaultLabels];
        [self fetchLoaderVersions];
        [self.tableView reloadData];
    };
    if (self.creatingNewInstance || !self.originalMinecraftVersion.length ||
        [versionId isEqualToString:self.originalMinecraftVersion]) {
        apply();
        return;
    }
    UIAlertController *warning = [UIAlertController
        alertControllerWithTitle:localize(@"修改 Minecraft 版本", nil)
        message:localize(@"更改 Minecraft 版本可能导致模组、存档或加载器不兼容。", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [warning addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    [warning addAction:[UIAlertAction actionWithTitle:localize(@"继续修改", nil)
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { apply(); }]];
    [self presentViewController:warning animated:YES completion:nil];
}

- (void)setupVersionPicker {
    self.versionPickerView = [[UIPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;
    self.versionPickerToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 390, 44.0)];
    self.versionTypeControl = [[UISegmentedControl alloc] initWithItems:@[
        localize(@"正式版", nil),
        localize(@"快照", nil),
        localize(@"远古 Beta", nil),
        localize(@"远古 Alpha", nil)
    ]];
    self.versionTypeControl.selectedSegmentIndex = 0;
    self.versionTypeControl.frame = CGRectMake(0, 0, 270, 34.0);
    self.versionTypeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.versionTypeControl addTarget:self action:@selector(changeVersionType:) forControlEvents:UIControlEventValueChanged];
    // here we go some random private apis I found
    [[self.versionTypeControl _uiktest_labelsWithState:0] makeObjectsPerformSelector:@selector(setNumberOfLines:) withObject:nil];
    UIBarButtonItem *versionTypes =
        [[UIBarButtonItem alloc] initWithCustomView:self.versionTypeControl];
    UIBarButtonItem *space = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
        target:nil action:nil];
    UIBarButtonItem *leadingBalance = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
        target:nil action:nil];
    leadingBalance.width = 44.0;
    UIBarButtonItem *done = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(versionClosePicker)];
    done.tintColor = UIColor.systemBlueColor;
    UIBarButtonItem *spaceAfter = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
        target:nil action:nil];
    // Balance the trailing Done item so the category control is visually
    // centered rather than drifting to the leading edge on narrow iPhones.
    self.versionPickerToolbar.items = @[
        leadingBalance, space, versionTypes, spaceAfter, done
    ];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    if (self.versionList.count == 0) {
        self.versionTextField.text = @"";
        return;
    }
    self.versionSelectedAt = row;
    self.versionTextField.text = [self pickerView:pickerView titleForRow:row forComponent:component];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)thePickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return self.versionList.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    if (self.versionList.count <= row) return nil;
    NSObject *object = self.versionList[row];
    if ([object isKindOfClass:[NSString class]]) {
        return (NSString*) object;
    } else {
        return [object valueForKey:@"id"];
    }
}

- (void)versionClosePicker {
    if (self.versionList.count > 0) {
        [self pickerView:self.versionPickerView
            didSelectRow:[self.versionPickerView selectedRowInComponent:0]
             inComponent:0];
    }
    NSString *selected = self.versionTextField.text ?: @"";
    [self.versionTextField endEditing:YES];
    if (!self.creatingNewInstance &&
        self.originalVersion.length &&
        ![selected isEqualToString:self.originalMinecraftVersion]) {
        UIAlertController *warning = [UIAlertController
            alertControllerWithTitle:localize(@"修改 Minecraft 版本", nil)
            message:localize(@"更改 Minecraft 版本可能导致模组、存档或加载器不兼容。", nil)
            preferredStyle:UIAlertControllerStyleAlert];
        [warning addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
            style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                self.versionTextField.text = self.originalMinecraftVersion;
                self.profile[@"pocketjMinecraftVersion"] = self.originalMinecraftVersion;
                [self.tableView reloadData];
            }]];
        [warning addAction:[UIAlertAction actionWithTitle:localize(@"继续修改", nil)
            style:UIAlertActionStyleDestructive handler:nil]];
        [self presentViewController:warning animated:YES completion:nil];
    }
}

- (void)changeVersionType:(UISegmentedControl *)sender {
    NSArray *newVersionList = self.versionList;
    if (sender || !self.versionList) {
        NSArray *types = @[@"release", @"snapshot", @"old_beta", @"old_alpha"];
        NSInteger index = MAX(0, MIN(self.versionTypeControl.selectedSegmentIndex, 3));
        NSString *type = types[index];
        newVersionList = [(remoteVersionList ?: @[])
            filteredArrayUsingPredicate:
                [NSPredicate predicateWithFormat:@"(type == %@)", type]];
    }

    if (newVersionList.count == 0) {
        self.versionList = @[];
        self.versionSelectedAt = -1;
        [self.versionPickerView reloadAllComponents];
        return;
    }

    if (self.versionSelectedAt == -1) {
        NSDictionary *selected = (id)[MinecraftResourceUtils findVersion:self.versionTextField.text inList:newVersionList];
        NSUInteger selectedIndex = selected
            ? [newVersionList indexOfObject:selected] : NSNotFound;
        self.versionSelectedAt =
            selectedIndex == NSNotFound ? 0 : (int)selectedIndex;
    } else {
        // Find the most matching version for this type
        NSObject *lastSelected = nil; 
        if (self.versionList.count > self.versionSelectedAt) {
            lastSelected = self.versionList[self.versionSelectedAt];
        }
        if (lastSelected != nil) {
            // MinecraftResourceUtils uses 0 for installed and 1...4 for the
            // four remote categories. The UI intentionally omits installed.
            NSObject *nearest = [MinecraftResourceUtils findNearestVersion:lastSelected
                expectedType:self.versionTypeControl.selectedSegmentIndex + 1];
            if (nearest != nil) {
                self.versionSelectedAt = [newVersionList indexOfObject:(id)nearest];
            }
        }
        lastSelected = nil;
        // Get back the currently selected in case none matching version found
        self.versionSelectedAt = MIN(abs(self.versionSelectedAt),
            (int)newVersionList.count - 1);
    }

    self.versionList = newVersionList;
    [self.versionPickerView reloadAllComponents];
    if (self.versionSelectedAt != -1) {
        [self.versionPickerView selectRow:self.versionSelectedAt inComponent:0 animated:NO];
        [self pickerView:self.versionPickerView didSelectRow:self.versionSelectedAt inComponent:0];
    }
}

@end
