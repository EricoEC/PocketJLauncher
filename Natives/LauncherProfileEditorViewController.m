#import "LauncherNavigationController.h"
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
@end

@implementation LauncherProfileEditorViewController

- (void)viewDidLoad {
    // Setup navigation bar & appearance
    self.title = localize(@"Edit profile", nil);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(actionDone)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.navigationController.modalInPresentation = YES;
    self.prefSectionsVisible = YES;
    self.originalInstanceName = self.instanceName.copy;
    // Setup preference getter and setter
    __weak LauncherProfileEditorViewController *weakSelf = self;
    self.getPreference = ^id(NSString *section, NSString *key){
        if ([key isEqualToString:@"instanceDisplayName"]) {
            return weakSelf.instanceName ?: @"default";
        }
        NSString *value = weakSelf.profile[key];
        if (value.length > 0 || ![weakSelf isPickFieldAtSection:section key:key]) {
            return value;
        } else {
            return @"(default)";
        }
    };
    self.setPreference = ^(NSString *section, NSString *key, NSString *value){
        if ([key isEqualToString:@"instanceDisplayName"]) {
            weakSelf.instanceName = value;
            return;
        }
        if ([value isEqualToString:@"(default)"] && [weakSelf isPickFieldAtSection:section key:key]) {
            [weakSelf.profile removeObjectForKey:key];
        } else if (value) {
            weakSelf.profile[key] = value;
        }
    };

    // Obtain all the lists
    self.oldName = self.getPreference(nil, @"name");
    if ([self.oldName length] == 0) {
        self.setPreference(nil, @"name", localize(@"新实例", nil));
    }
    NSArray *rendererKeys = getRendererKeys(YES);
    NSArray *rendererList = getRendererNames(YES);
    NSArray *touchControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")]];
    NSArray *gamepadControlList = [self listFilesAtPath:[NSString stringWithFormat:@"%s/controlmap/gamepads", getenv("POJAV_HOME")]];
    NSMutableArray *touchControlNames = touchControlList.mutableCopy;
    NSMutableArray *gamepadControlNames = gamepadControlList.mutableCopy;
    if (touchControlNames.count > 0) touchControlNames[0] = localize(@"默认", nil);
    if (gamepadControlNames.count > 0) gamepadControlNames[0] = localize(@"默认", nil);
    NSMutableArray *javaList = [getPrefObject(@"java.java_homes") allKeys].mutableCopy;
    if (!javaList) javaList = [NSMutableArray array];
    [javaList sortUsingSelector:@selector(compare:)];
    if (javaList.count == 0) [javaList addObject:@"(default)"];
    else javaList[0] = @"(default)";
    NSMutableArray *javaNames = javaList.mutableCopy;
    javaNames[0] = localize(@"默认", nil);

    // Setup version picker
    [self setupVersionPicker];
    id typeVersionPicker = ^void(UITableViewCell *cell, NSString *section, NSString *key, NSDictionary *item){
        self.typeTextField(cell, section, key, item);
        PickTextField *textField = (id)cell.accessoryView;
        weakSelf.versionTextField = textField;
        textField.prefersMediumSheet = YES;
        textField.inputAccessoryView = weakSelf.versionPickerToolbar;
        textField.inputView = weakSelf.versionPickerView;
        // Auto pick version type
        if (self.versionList) return;
        if ([MinecraftResourceUtils findVersion:textField.text inList:localVersionList]) {
            self.versionTypeControl.selectedSegmentIndex = 0;
        } else {
            NSDictionary *selected = (id)[MinecraftResourceUtils findVersion:textField.text inList:remoteVersionList];
            if (selected) {
                NSArray *types = @[@"installed", @"release", @"snapshot", @"old_beta", @"old_alpha"];
                NSString *type = selected[@"type"];
                self.versionTypeControl.selectedSegmentIndex = [types indexOfObject:type];
            } else {
                // Version not found
                self.versionTypeControl.selectedSegmentIndex = 0;
            }
        }
        self.versionSelectedAt = -1;
        [self changeVersionType:nil];
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
        [generalItems addObject:@{@"key": @"lastVersionId",
              @"icon": @"archivebox",
              @"title": @"preference.profile.title.version",
              @"type": typeVersionPicker,
              // Imported instances are allowed to start without a detected
              // version, but NSDictionary literals may never contain nil.
              @"placeholder":
                  self.getPreference(nil, @"lastVersionId") ?: @"",
              @"customClass": PickTextField.class
        }];
    }
    [generalItems addObjectsFromArray:@[
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
              @"pickKeys": javaList,
              @"pickList": javaNames
            },
            @{@"key": @"javaArgs",
              @"icon": @"slider.vertical.3",
              @"title": @"preference.title.java_args",
              @"type": self.typeTextField,
              @"placeholder": localize(@"默认", nil)
            }
    ]];
    self.prefContents = @[generalItems];

    [super viewDidLoad];
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)actionDone {
    // We might be saving without ending editing, so make sure textFieldDidEndEditing is always called
    UITextField *currentTextField = [self performSelector:@selector(_firstResponder)];
    if ([currentTextField isKindOfClass:UITextField.class] && [currentTextField isDescendantOfView:self.tableView]) {
        [self textFieldDidEndEditing:currentTextField];
    }

    NSString *selectedVersion = [self.profile[@"lastVersionId"]
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
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
                errorMessage = localize(@"已经存在同名实例。", nil);
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
                errorMessage ?: localize(@"实例名称已存在。", nil));
            return;
        }
        self.instanceName = newInstanceName;
        self.originalInstanceName = newInstanceName;
    }

    if ([self.profile[@"name"] length] == 0 && self.oldName.length > 0) {
        // Return to its old name
        self.profile[@"name"] = self.oldName;
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
    [self actionClose];

    // Dismissing naturally calls the presenting instance list's
    // viewWillAppear. Do not assume a split-view hierarchy here: the modern
    // tab shell presents this editor from a regular navigation controller.
}

- (BOOL)isPickFieldAtSection:(NSString *)section key:(NSString *)key {
    NSDictionary *pref = [self.prefContents[0] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"(key == %@)", key]].firstObject;
    return pref[@"type"] == self.typePickField;
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

- (void)setupVersionPicker {
    self.versionPickerView = [[UIPickerView alloc] init];
    self.versionPickerView.delegate = self;
    self.versionPickerView.dataSource = self;
    self.versionPickerToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 390, 44.0)];
    self.versionTypeControl = [[UISegmentedControl alloc] initWithItems:@[
        localize(@"Installed", nil),
        localize(@"Releases", nil),
        localize(@"Snapshot", nil),
        localize(@"Old-beta", nil),
        localize(@"Old-alpha", nil)
    ]];
    self.versionTypeControl.frame = CGRectMake(0, 0, 285, 34.0);
    self.versionTypeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.versionTypeControl addTarget:self action:@selector(changeVersionType:) forControlEvents:UIControlEventValueChanged];
    // here we go some random private apis I found
    [[self.versionTypeControl _uiktest_labelsWithState:0] makeObjectsPerformSelector:@selector(setNumberOfLines:) withObject:nil];
    UIBarButtonItem *versionTypes =
        [[UIBarButtonItem alloc] initWithCustomView:self.versionTypeControl];
    UIBarButtonItem *space = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
        target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(versionClosePicker)];
    done.tintColor = UIColor.systemBlueColor;
    self.versionPickerToolbar.items = @[versionTypes, space, done];
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
    [self.versionTextField endEditing:YES];
}

- (void)changeVersionType:(UISegmentedControl *)sender {
    NSArray *newVersionList = self.versionList;
    if (sender || !self.versionList) {
        if (self.versionTypeControl.selectedSegmentIndex == 0) {
            // installed
            newVersionList = localVersionList ?: @[];
        } else {
            NSString *type = @[@"installed", @"release", @"snapshot", @"old_beta", @"old_alpha"][self.versionTypeControl.selectedSegmentIndex];
            newVersionList = [(remoteVersionList ?: @[])
                filteredArrayUsingPredicate:
                    [NSPredicate predicateWithFormat:@"(type == %@)", type]];
        }
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
            NSObject *nearest = [MinecraftResourceUtils findNearestVersion:lastSelected expectedType:self.versionTypeControl.selectedSegmentIndex];
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
