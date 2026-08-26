#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPrefGameDirViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "LauncherProfileEditorViewController.h"
#import "LauncherProfilesViewController.h"
#import "ModernUITheme.h"
#import "ModManagerViewController.h"
#import "PocketJResourceLibraryViewController.h"
//#import "NSFileManager+NRFileManager.h"
#import "PLProfiles.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#import "UIKit+AFNetworking.h"
#pragma clang diagnostic pop
#import "UIKit+hook.h"
#import "installer/FabricInstallViewController.h"
#import "installer/ForgeInstallViewController.h"
#import "installer/ModpackInstallViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "UnzipKit.h"

NSNotificationName const LauncherOpenModManagerNotification =
    @"LauncherOpenModManagerNotification";

@interface LauncherProfilesViewController () <UIDocumentPickerDelegate>

@property(nonatomic) UIBarButtonItem *createButtonItem;
@property(nonatomic) NSArray<NSString *> *instanceNames;
@property(nonatomic, copy) NSString *pendingNewInstanceName;
@property(nonatomic, copy) NSString *previousInstanceName;
@end

@implementation LauncherProfilesViewController

- (id)init {
    self = [super init];
    self.title = localize(@"游戏", nil);
    return self;
}

- (NSString *)imageName {
    return @"MenuProfiles";
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.createButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
        target:nil action:nil];
    UIMenu *createMenu = [UIMenu menuWithTitle:@""
        children:@[
            [UIAction actionWithTitle:localize(@"新建实例", nil)
                image:[UIImage systemImageNamed:@"plus.rectangle.on.folder"]
                identifier:nil handler:^(UIAction *action) {
                    [self actionCreateUnifiedInstance];
                }],
            [UIAction actionWithTitle:localize(@"导入压缩包", nil)
                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                identifier:nil handler:^(UIAction *action) {
                    [self actionImportInstanceArchive];
                }],
            [UIAction actionWithTitle:localize(@"在线整合包", nil)
                image:[UIImage systemImageNamed:@"shippingbox"]
                identifier:nil handler:^(UIAction *action) {
                    [self actionCreateModpackProfile];
                }]
        ]];
    self.createButtonItem.menu = createMenu;
    if(@available(iOS 19.0, *)) {
        self.createButtonItem.sharesBackground = NO;
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:@selector(savedProfileDidChange:)
               name:@"LauncherProfilesDidChangeNotification"
             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (LauncherNavigationController *)launcherNavigationController {
    if ([self.navigationController
            isKindOfClass:LauncherNavigationController.class]) {
        return (LauncherNavigationController *)self.navigationController;
    }
    for (UIViewController *controller in
            self.tabBarController.viewControllers) {
        if ([controller
                isKindOfClass:LauncherNavigationController.class]) {
            return (LauncherNavigationController *)controller;
        }
    }
    return nil;
}

- (void)savedProfileDidChange:(NSNotification *)notification {
    [self reloadInstanceNames];
    [PLProfiles updateCurrent];
    [self.tableView reloadData];
    [[self launcherNavigationController] reloadProfileList];
}

- (NSString *)availableInstanceNameFromPreferredName:(NSString *)preferredName {
    NSString *base = [preferredName
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (base.length == 0 || [base isEqualToString:@"."] ||
        [base isEqualToString:@".."]) {
        base = localize(@"导入的实例", nil);
    }
    base = [base stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *candidate = base;
    NSInteger suffix = 2;
    while ([NSFileManager.defaultManager
        fileExistsAtPath:[self.instancesRoot
            stringByAppendingPathComponent:candidate]]) {
        candidate = [NSString stringWithFormat:@"%@ %ld", base, (long)suffix++];
    }
    return candidate;
}

- (NSString *)installedVersionForImportedInstanceAtPath:(NSString *)path {
    NSMutableArray<NSString *> *versionRoots = [NSMutableArray array];
    NSDirectoryEnumerator *rootEnumerator =
        [NSFileManager.defaultManager enumeratorAtPath:path];
    for (NSString *relative in rootEnumerator) {
        if ([relative.lastPathComponent isEqualToString:@"versions"]) {
            BOOL isDirectory = NO;
            NSString *candidate = [path stringByAppendingPathComponent:relative];
            if ([NSFileManager.defaultManager fileExistsAtPath:candidate
                                                   isDirectory:&isDirectory] &&
                isDirectory) {
                [versionRoots addObject:candidate];
                [rootEnumerator skipDescendants];
            }
        }
    }
    NSString *bestVersion = nil;
    NSInteger bestScore = NSIntegerMin;
    for (NSString *versionsPath in versionRoots) {
        NSArray<NSString *> *entries =
            [NSFileManager.defaultManager
                contentsOfDirectoryAtPath:versionsPath error:nil];
        for (NSString *versionId in entries) {
            NSString *directory =
                [versionsPath stringByAppendingPathComponent:versionId];
            BOOL isDirectory = NO;
            if (![NSFileManager.defaultManager fileExistsAtPath:directory
                                                    isDirectory:&isDirectory] ||
                !isDirectory) continue;
            NSString *jsonPath = [directory stringByAppendingPathComponent:
                [versionId stringByAppendingPathExtension:@"json"]];
            NSDictionary *metadata = parseJSONFromFile(jsonPath);
            NSInteger score = 1; // A real versions/<id> directory is useful.
            if ([metadata isKindOfClass:NSDictionary.class] &&
                !metadata[@"NSErrorObject"]) {
                if ([metadata[@"id"] isEqualToString:versionId]) score += 10;
                if ([metadata[@"inheritsFrom"] length] > 0) score += 100;
            }
            NSString *lower = versionId.lowercaseString;
            if ([lower containsString:@"fabric"] ||
                [lower containsString:@"quilt"] ||
                [lower containsString:@"forge"]) score += 50;
            NSString *jarPath = [directory stringByAppendingPathComponent:
                [versionId stringByAppendingPathExtension:@"jar"]];
            if ([NSFileManager.defaultManager fileExistsAtPath:jarPath])
                score += 20;
            if (!bestVersion || score > bestScore) {
                bestVersion = versionId;
                bestScore = score;
            }
        }
    }
    if (bestVersion.length > 0) return bestVersion;

    // Modpack formats often omit a versions directory and declare Minecraft
    // in their manifest instead.
    NSDirectoryEnumerator *manifestEnumerator =
        [NSFileManager.defaultManager enumeratorAtPath:path];
    for (NSString *relative in manifestEnumerator) {
        NSString *file = relative.lastPathComponent.lowercaseString;
        if (![file isEqualToString:@"modrinth.index.json"] &&
            ![file isEqualToString:@"manifest.json"]) continue;
        NSDictionary *json =
            parseJSONFromFile([path stringByAppendingPathComponent:relative]);
        NSString *declared = [file isEqualToString:@"modrinth.index.json"]
            ? json[@"dependencies"][@"minecraft"]
            : json[@"minecraft"][@"version"];
        if (declared.length > 0) return declared;
    }

    // Last safe fallback: infer a semantic Minecraft version from the
    // imported instance/zip name (for example "MyPack 1.21.1").
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"(?<![0-9])1\\.[0-9]+(?:\\.[0-9]+)?(?![0-9])"
        options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:path.lastPathComponent
        options:0 range:NSMakeRange(0, path.lastPathComponent.length)];
    if (match) return [path.lastPathComponent substringWithRange:match.range];
    return bestVersion;
}

- (void)repairImportedProfileAtPath:(NSString *)path
                       instanceName:(NSString *)instanceName {
    NSString *profilesPath =
        [path stringByAppendingPathComponent:@"launcher_profiles.json"];
    NSDictionary *existing = parseJSONFromFile(profilesPath);
    if (![existing isKindOfClass:NSDictionary.class] ||
        existing[@"NSErrorObject"]) {
        existing = @{};
    }
    NSString *selected =
        [existing[@"selectedProfile"] isKindOfClass:NSString.class]
            ? existing[@"selectedProfile"] : nil;
    NSDictionary *existingProfiles =
        [existing[@"profiles"] isKindOfClass:NSDictionary.class]
            ? existing[@"profiles"] : nil;
    NSDictionary *selectedProfile =
        [existingProfiles[selected] isKindOfClass:NSDictionary.class]
            ? existingProfiles[selected] : nil;
    NSString *selectedVersion =
        [selectedProfile[@"lastVersionId"] isKindOfClass:NSString.class]
            ? selectedProfile[@"lastVersionId"] : nil;
    NSString *selectedVersionPath = selectedVersion.length
        ? [[path stringByAppendingPathComponent:@"versions"]
            stringByAppendingPathComponent:selectedVersion]
        : nil;
    BOOL selectedIsInstalled = selectedVersionPath.length > 0 &&
        [NSFileManager.defaultManager
            fileExistsAtPath:selectedVersionPath];
    if (selectedIsInstalled) return;

    NSString *detectedVersion =
        [self installedVersionForImportedInstanceAtPath:path];
    // Keep a valid version declared by the imported launcher profile even if
    // its files still need downloading. Only synthesize a version when one
    // can actually be detected.
    if (detectedVersion.length == 0 && selectedVersion.length > 0) return;

    NSString *profileKey = selected.length ? selected : instanceName;
    NSMutableDictionary *profiles =
        existingProfiles.mutableCopy ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *profile =
        [profiles[profileKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    profile[@"name"] = [profile[@"name"] length]
        ? profile[@"name"] : instanceName;
    if (detectedVersion.length > 0) {
        profile[@"lastVersionId"] = detectedVersion;
    } else {
        [profile removeObjectForKey:@"lastVersionId"];
    }
    profiles[profileKey] = profile;
    NSMutableDictionary *repaired =
        [existing isKindOfClass:NSDictionary.class] &&
        !existing[@"NSErrorObject"]
            ? existing.mutableCopy
            : [NSMutableDictionary dictionary];
    repaired[@"profiles"] = profiles;
    repaired[@"selectedProfile"] = profileKey;
    saveJSONToFile(repaired, profilesPath);
}

- (BOOL)mergeImportedDirectory:(NSString *)source
                 intoDirectory:(NSString *)destination
                          error:(NSError **)error {
    NSArray<NSString *> *items =
        [NSFileManager.defaultManager contentsOfDirectoryAtPath:source
                                                           error:error];
    if (!items) return NO;
    for (NSString *item in items) {
        NSString *from = [source stringByAppendingPathComponent:item];
        NSString *to = [destination stringByAppendingPathComponent:item];
        BOOL fromIsDirectory = NO;
        [NSFileManager.defaultManager fileExistsAtPath:from
                                           isDirectory:&fromIsDirectory];
        BOOL toIsDirectory = NO;
        BOOL toExists = [NSFileManager.defaultManager fileExistsAtPath:to
                                                           isDirectory:&toIsDirectory];
        if (fromIsDirectory && toExists && toIsDirectory) {
            if (![self mergeImportedDirectory:from
                                intoDirectory:to error:error]) return NO;
            [NSFileManager.defaultManager removeItemAtPath:from error:nil];
        } else {
            if (toExists) {
                [NSFileManager.defaultManager removeItemAtPath:to error:nil];
            }
            if (![NSFileManager.defaultManager moveItemAtPath:from
                                                       toPath:to
                                                        error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

- (BOOL)normalizeImportedInstanceAtPath:(NSString *)destination
                                  error:(NSError **)error {
    NSString *rootVersions =
        [destination stringByAppendingPathComponent:@"versions"];
    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:rootVersions
                                           isDirectory:&isDirectory] &&
        isDirectory) {
        return YES;
    }

    // Archives copied from another launcher commonly contain
    // default/.minecraft/... or Library/Application Support/minecraft/....
    // Find the actual game root by its versions directory and merge that
    // root into this instance, so the original kernel sees its normal layout.
    NSDirectoryEnumerator *enumerator =
        [NSFileManager.defaultManager enumeratorAtPath:destination];
    NSString *actualRoot = nil;
    for (NSString *relative in enumerator) {
        if (![relative.lastPathComponent isEqualToString:@"versions"]) continue;
        NSString *candidate =
            [destination stringByAppendingPathComponent:relative];
        BOOL candidateIsDirectory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate
                                               isDirectory:&candidateIsDirectory] &&
            candidateIsDirectory) {
            actualRoot = candidate.stringByDeletingLastPathComponent;
            break;
        }
    }
    if (!actualRoot ||
        [actualRoot isEqualToString:destination]) return YES;
    BOOL merged = [self mergeImportedDirectory:actualRoot
                                  intoDirectory:destination error:error];
    if (merged) {
        [NSFileManager.defaultManager removeItemAtPath:actualRoot error:nil];
    }
    return merged;
}

- (void)actionImportInstanceArchive {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeZIP]
            asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:localize(@"正在导入实例", nil)
        message:localize(@"正在读取并解压 ZIP，请稍候…\n\n", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [loading.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor
            constraintEqualToAnchor:loading.view.centerXAnchor],
        [spinner.bottomAnchor
            constraintEqualToAnchor:loading.view.bottomAnchor constant:-20]
    ]];
    [spinner startAnimating];

    [self presentViewController:loading animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{
            BOOL securityScoped =
                [url startAccessingSecurityScopedResource];
            __block NSError *error = nil;
            UZKArchive *archive =
                [[UZKArchive alloc] initWithURL:url error:&error];
            NSArray<UZKFileInfo *> *files =
                [archive listFileInfo:&error];
            NSString *commonRoot = nil;
            BOOL hasSingleRoot = YES;
            for (UZKFileInfo *info in files) {
                NSString *first = info.filename.pathComponents.firstObject;
                if (first.length == 0 ||
                    [first isEqualToString:@"/"]) continue;
                if (!commonRoot) commonRoot = first;
                else if (![commonRoot isEqualToString:first]) {
                    hasSingleRoot = NO;
                    break;
                }
            }
            if (!hasSingleRoot) commonRoot = nil;

            NSString *preferredName = commonRoot.length
                ? commonRoot
                : url.lastPathComponent.stringByDeletingPathExtension;
            NSString *instanceName = archive && files.count > 0 && !error
                ? [self availableInstanceNameFromPreferredName:preferredName]
                : nil;
            NSString *destination = instanceName.length
                ? [self.instancesRoot
                    stringByAppendingPathComponent:instanceName] : nil;
            if (!archive || files.count == 0 || error) {
                if (!error) {
                    error = [NSError errorWithDomain:@"InstanceImport"
                        code:1 userInfo:@{NSLocalizedDescriptionKey:
                            localize(@"压缩包为空或格式无效。", nil)}];
                }
            } else {
                [NSFileManager.defaultManager
                    createDirectoryAtPath:destination
              withIntermediateDirectories:YES attributes:nil error:&error];
            }

            if (!error) {
                [archive performOnFilesInArchive:
                    ^(UZKFileInfo *info, BOOL *stop) {
                    NSString *relative = info.filename;
                    NSString *prefix =
                        [commonRoot stringByAppendingString:@"/"];
                    if (commonRoot.length > 0) {
                        if ([relative isEqualToString:commonRoot] ||
                            [relative isEqualToString:prefix]) return;
                        if ([relative hasPrefix:prefix]) {
                            relative =
                                [relative substringFromIndex:prefix.length];
                        }
                    }
                    NSString *standardized =
                        relative.stringByStandardizingPath;
                    if (standardized.length == 0 ||
                        standardized.isAbsolutePath ||
                        [standardized isEqualToString:@".."] ||
                        [standardized hasPrefix:@"../"]) return;
                    NSString *target = [destination
                        stringByAppendingPathComponent:standardized];
                    NSString *targetDirectory = info.isDirectory
                        ? target : target.stringByDeletingLastPathComponent;
                    if (![NSFileManager.defaultManager
                            createDirectoryAtPath:targetDirectory
                      withIntermediateDirectories:YES attributes:nil
                                           error:&error]) {
                        *stop = YES;
                        return;
                    }
                    if (info.isDirectory) return;
                    NSData *data =
                        [archive extractData:info error:&error];
                    if (!data || ![data writeToFile:target
                        options:NSDataWritingAtomic error:&error]) {
                        *stop = YES;
                    }
                } error:&error];
            }
            if (securityScoped) {
                [url stopAccessingSecurityScopedResource];
            }
            if (error && destination.length > 0) {
                [NSFileManager.defaultManager
                    removeItemAtPath:destination error:nil];
            } else if (!error) {
                if ([self normalizeImportedInstanceAtPath:destination
                                                    error:&error]) {
                    [self repairImportedProfileAtPath:destination
                                         instanceName:instanceName];
                } else {
                    [NSFileManager.defaultManager
                        removeItemAtPath:destination error:nil];
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [loading dismissViewControllerAnimated:YES completion:^{
                    if (error) {
                        showDialog(localize(@"无法导入实例", nil),
                            error.localizedDescription);
                        return;
                    }
                    [self activateInstanceNamed:instanceName];
                    [self reloadInstanceNames];
                    [self.tableView reloadData];
                    showDialog(localize(@"实例已导入", nil), [NSString stringWithFormat:
                        localize(@"已添加实例“%@”。", nil), instanceName]);
                }];
            });
        });
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // The modern shell has a dedicated Accounts tab. Never reach back into
    // the removed split-view sidebar from here.
    self.navigationItem.rightBarButtonItem = self.createButtonItem;

    [self reloadInstanceNames];
    [PLProfiles updateCurrent];
    [self reconcilePendingLoaderInstallation];
    [self.tableView reloadData];
    [[self launcherNavigationController] reloadProfileList];
}

- (void)reconcilePendingLoaderInstallation {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *instance = [defaults stringForKey:@"PocketJPendingLoaderInstance"];
    NSString *profileName = [defaults stringForKey:@"PocketJPendingLoaderProfile"];
    NSString *loader = [defaults stringForKey:@"PocketJPendingLoaderKind"];
    NSString *minecraftVersion =
        [defaults stringForKey:@"PocketJPendingLoaderMinecraftVersion"];
    NSString *loaderVersion =
        [defaults stringForKey:@"PocketJPendingLoaderVersion"];
    if (!instance.length || !profileName.length || !loader.length) return;

    NSString *versionsPath = [[self.instancesRoot
        stringByAppendingPathComponent:instance]
        stringByAppendingPathComponent:@"versions"];
    NSArray<NSString *> *before = [defaults arrayForKey:
        @"PocketJPendingLoaderBeforeVersions"] ?: @[];
    NSSet *beforeSet = [NSSet setWithArray:before];
    NSArray<NSString *> *versions = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:versionsPath error:nil] ?: @[];
    NSString *installedVersion = nil;
    NSDate *latestDate = NSDate.distantPast;
    for (NSString *candidate in versions) {
        NSString *lower = candidate.lowercaseString;
        if (![lower containsString:loader]) continue;
        NSString *jsonPath = [[versionsPath stringByAppendingPathComponent:candidate]
            stringByAppendingPathComponent:[candidate stringByAppendingPathExtension:@"json"]];
        NSDictionary *metadata = parseJSONFromFile(jsonPath);
        NSString *base = metadata[@"inheritsFrom"];
        BOOL versionMatches = !minecraftVersion.length ||
            [base isEqualToString:minecraftVersion] ||
            [candidate containsString:minecraftVersion];
        if (!versionMatches) continue;
        NSDictionary *attributes = [NSFileManager.defaultManager
            attributesOfItemAtPath:jsonPath error:nil];
        NSDate *date = attributes[NSFileModificationDate] ?: NSDate.distantPast;
        if (![beforeSet containsObject:candidate] ||
            [date compare:latestDate] == NSOrderedDescending) {
            installedVersion = candidate;
            latestDate = date;
        }
    }
    if (!installedVersion.length) return;

    [self activateInstanceNamed:instance];
    [PLProfiles updateCurrent];
    NSMutableDictionary *profile = PLProfiles.current.profiles[profileName];
    if ([profile isKindOfClass:NSMutableDictionary.class]) {
        profile[@"lastVersionId"] = installedVersion;
        profile[@"pocketjLoader"] = loader;
        profile[@"pocketjMinecraftVersion"] = minecraftVersion ?: @"";
        profile[@"pocketjLoaderVersion"] = loaderVersion ?: @"";
        profile[@"pocketjLoaderInstallPending"] = @NO;
        profile[@"pocketjResourcesVerified"] = @NO;
        PLProfiles.current.profileDict[@"selectedProfile"] = profileName;
        [PLProfiles.current save];
    }
    for (NSString *key in @[@"PocketJPendingLoaderInstance",
                            @"PocketJPendingLoaderProfile",
                            @"PocketJPendingLoaderKind",
                            @"PocketJPendingLoaderMinecraftVersion",
                            @"PocketJPendingLoaderVersion",
                            @"PocketJPendingLoaderBeforeVersions"]) {
        [defaults removeObjectForKey:key];
    }
    showDialog(localize(@"加载器安装完成", nil),
        [NSString stringWithFormat:localize(@"已为实例写入 %@。", nil),
            installedVersion]);
}

- (NSString *)instancesRoot {
    return [NSString stringWithFormat:@"%s/instances", getenv("POJAV_HOME")];
}

- (void)reloadInstanceNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSArray<NSString *> *files =
        [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.instancesRoot
                                                           error:nil];
    for (NSString *file in files) {
        BOOL isDirectory = NO;
        NSString *path = [self.instancesRoot stringByAppendingPathComponent:file];
        if ([NSFileManager.defaultManager fileExistsAtPath:path
                                               isDirectory:&isDirectory] &&
            isDirectory) {
            [names addObject:file];
        }
    }
    [names sortUsingSelector:@selector(localizedStandardCompare:)];
    if ([names containsObject:@"default"]) {
        [names removeObject:@"default"];
        [names insertObject:@"default" atIndex:0];
    }
    self.instanceNames = names;
}

- (void)activateInstanceNamed:(NSString *)name {
    LauncherNavigationController *launcher =
        [self launcherNavigationController];
    if (launcher.hasActiveLaunchTask) {
        [launcher cancelCurrentLaunchTask];
    }
    setPrefObject(@"general.game_directory", name);
    NSString *instancePath =
        [self.instancesRoot stringByAppendingPathComponent:name];
    NSError *normalizationError = nil;
    if ([self normalizeImportedInstanceAtPath:instancePath
                                        error:&normalizationError]) {
        [self repairImportedProfileAtPath:instancePath
                             instanceName:name];
    } else {
        NSLog(@"[InstanceImport] Unable to normalize %@: %@",
              name, normalizationError.localizedDescription);
    }
    NSString *gamePath = @(getenv("POJAV_GAME_DIR"));
    [NSFileManager.defaultManager removeItemAtPath:gamePath error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:gamePath
                                      withDestinationPath:instancePath
                                                    error:nil];
    [NSFileManager.defaultManager changeCurrentDirectoryPath:gamePath];
    toggleIsolatedPref(NO);
    [PLProfiles updateCurrent];
    [launcher reloadProfileList];
}

- (void)chooseDirectoryForNewInstance:(NSString *)suggestedName
                           completion:(dispatch_block_t)completion {
    UIAlertController *choice = [UIAlertController
        alertControllerWithTitle:localize(@"选择游戏目录", nil)
        message:localize(@"新建独立目录可以避免存档、模组、资源包和配置互相混用。", nil)
        preferredStyle:UIAlertControllerStyleActionSheet];
    choice.popoverPresentationController.barButtonItem = self.createButtonItem;

    [choice addAction:[UIAlertAction actionWithTitle:localize(@"创建新的独立目录", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIAlertController *prompt = [UIAlertController
                alertControllerWithTitle:localize(@"新建实例", nil)
                message:localize(@"请输入实例文件夹名称", nil)
                preferredStyle:UIAlertControllerStyleAlert];
            [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
                field.text = suggestedName;
                field.placeholder = localize(@"实例名称", nil);
                field.clearButtonMode = UITextFieldViewModeWhileEditing;
            }];
            [prompt addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
                style:UIAlertActionStyleCancel handler:nil]];
            [prompt addAction:[UIAlertAction actionWithTitle:localize(@"创建", nil)
                style:UIAlertActionStyleDefault handler:^(UIAlertAction *create) {
                    NSString *name =
                        [prompt.textFields.firstObject.text
                            stringByTrimmingCharactersInSet:
                                NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (name.length == 0 ||
                        [name isEqualToString:@"."] ||
                        [name isEqualToString:@".."] ||
                        [name containsString:@"/"]) {
                        showDialog(localize(@"实例名称无效", nil),
                            localize(@"实例名称不能为空，也不能包含斜杠。", nil));
                        return;
                    }
                    NSString *path =
                        [self.instancesRoot stringByAppendingPathComponent:name];
                    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
                        showDialog(localize(@"实例已存在", nil),
                            localize(@"请选择“使用已有目录”，或者输入其他名称。", nil));
                        return;
                    }
                    NSError *error = nil;
                    [NSFileManager.defaultManager createDirectoryAtPath:path
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error];
                    if (error) {
                        showDialog(localize(@"无法创建实例", nil), error.localizedDescription);
                        return;
                    }
                    [self activateInstanceNamed:name];
                    [self reloadInstanceNames];
                    [self.tableView reloadData];
                    completion();
                }]];
            [self presentViewController:prompt animated:YES completion:nil];
        }]];

    [choice addAction:[UIAlertAction actionWithTitle:localize(@"使用已有目录", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self reloadInstanceNames];
            UIAlertController *existing = [UIAlertController
                alertControllerWithTitle:localize(@"选择已有游戏目录", nil)
                message:nil
                preferredStyle:UIAlertControllerStyleActionSheet];
            existing.popoverPresentationController.barButtonItem =
                self.createButtonItem;
            for (NSString *name in self.instanceNames) {
                [existing addAction:[UIAlertAction actionWithTitle:name
                    style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *select) {
                        [self activateInstanceNamed:name];
                        completion();
                    }]];
            }
            [existing addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
                style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:existing animated:YES completion:nil];
        }]];
    [choice addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:choice animated:YES completion:nil];
}

- (void)actionCreateUnifiedInstance {
    NSString *name = [self availableInstanceNameFromPreferredName:
        localize(@"新实例", nil)];
    NSString *path = [self.instancesRoot stringByAppendingPathComponent:name];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:path
        withIntermediateDirectories:YES attributes:nil error:&error]) {
        showDialog(localize(@"无法创建实例", nil), error.localizedDescription);
        return;
    }
    self.previousInstanceName = getPrefObject(@"general.game_directory");
    self.pendingNewInstanceName = name;
    [self activateInstanceNamed:name];
    [self reloadInstanceNames];
    [self.tableView reloadData];
    [self actionEditProfile:@{
        @"name": name,
        @"lastVersionId": @"latest-release",
        @"pocketjLoader": @"vanilla",
    }];
}

- (void)actionCreateFabricProfile {
    FabricInstallViewController *vc = [FabricInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateForgeProfile {
    ForgeInstallViewController *vc = [ForgeInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateModpackProfile {
    ModpackInstallViewController *vc = [ModpackInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionEditProfile:(NSDictionary *)profile {
    LauncherProfileEditorViewController *vc = [LauncherProfileEditorViewController new];
    vc.instanceName = getPrefObject(@"general.game_directory") ?: @"default";
    NSMutableDictionary *editableProfile =
        [profile isKindOfClass:NSDictionary.class]
            ? profile.mutableCopy : [NSMutableDictionary dictionary];
    if (![editableProfile[@"name"] isKindOfClass:NSString.class] ||
        [editableProfile[@"name"] length] == 0) {
        editableProfile[@"name"] = vc.instanceName;
    }
    vc.profile = editableProfile;
    BOOL creating = [vc.instanceName isEqualToString:self.pendingNewInstanceName];
    vc.creatingNewInstance = creating;
    __weak typeof(self) weakSelf = self;
    if (creating) {
        vc.cancelCreation = ^{
            NSString *temporaryName = weakSelf.pendingNewInstanceName;
            if (temporaryName.length) {
                [NSFileManager.defaultManager removeItemAtPath:
                    [weakSelf.instancesRoot stringByAppendingPathComponent:temporaryName]
                    error:nil];
            }
            NSString *previous = weakSelf.previousInstanceName;
            weakSelf.pendingNewInstanceName = nil;
            weakSelf.previousInstanceName = nil;
            [weakSelf reloadInstanceNames];
            if (previous.length &&
                [NSFileManager.defaultManager fileExistsAtPath:
                    [weakSelf.instancesRoot stringByAppendingPathComponent:previous]]) {
                [weakSelf activateInstanceNamed:previous];
            } else {
                // Cancelling the very first instance must not leave the
                // launcher pointing at the temporary directory we removed.
                setPrefObject(@"general.game_directory", @"");
                NSString *gamePath = @(getenv("POJAV_GAME_DIR"));
                [NSFileManager.defaultManager removeItemAtPath:gamePath error:nil];
            }
            [weakSelf.tableView reloadData];
        };
        vc.creationDidFinish = ^{
            weakSelf.pendingNewInstanceName = nil;
            weakSelf.previousInstanceName = nil;
            [weakSelf reloadInstanceNames];
            [weakSelf.tableView reloadData];
        };
    }
    vc.renameInstance = ^BOOL(NSString *oldName, NSString *newName,
                              NSString **errorMessage) {
        NSString *oldPath =
            [weakSelf.instancesRoot stringByAppendingPathComponent:oldName];
        NSString *newPath =
            [weakSelf.instancesRoot stringByAppendingPathComponent:newName];
        if ([NSFileManager.defaultManager fileExistsAtPath:newPath]) {
            if (errorMessage) *errorMessage = localize(@"已重名，请换个名字。", nil);
            return NO;
        }
        NSError *error = nil;
        if (![NSFileManager.defaultManager moveItemAtPath:oldPath
                                                   toPath:newPath
                                                    error:&error]) {
            if (errorMessage) *errorMessage = error.localizedDescription;
            return NO;
        }
        [weakSelf activateInstanceNamed:newName];
        [weakSelf reloadInstanceNames];
        [weakSelf.tableView reloadData];
        return YES;
    };
    [self presentNavigatedViewController:vc];
}

- (void)presentNavigatedViewController:(UIViewController *)vc {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    //nav.navigationBar.prefersLargeTitles = YES;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return localize(@"实例", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.instanceNames.count;
}

- (NSString *)loaderNameForVersion:(NSString *)version {
    NSString *lower = version.lowercaseString ?: @"";
    if ([lower containsString:@"neoforge"]) return @"NeoForge";
    if ([lower containsString:@"fabric"]) return @"Fabric";
    if ([lower containsString:@"quilt"]) return @"Quilt";
    if ([lower containsString:@"forge"]) return @"Forge";
    return @"Vanilla";
}

- (NSString *)loaderNameForProfile:(NSDictionary *)profile {
    NSString *loader = [profile[@"pocketjLoader"] lowercaseString];
    NSDictionary *names = @{@"vanilla": @"Vanilla", @"fabric": @"Fabric",
        @"forge": @"Forge", @"neoforge": @"NeoForge", @"quilt": @"Quilt"};
    return names[loader] ?: [self loaderNameForVersion:profile[@"lastVersionId"]];
}

- (void)setupInstanceCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    cell.userInteractionEnabled = !getenv("DEMO_LOCK");
    NSString *name = self.instanceNames[row];
    NSString *profilesPath = [[self.instancesRoot
        stringByAppendingPathComponent:name]
        stringByAppendingPathComponent:@"launcher_profiles.json"];
    NSDictionary *profiles = parseJSONFromFile(profilesPath);
    if (![profiles isKindOfClass:NSDictionary.class]) profiles = nil;
    NSString *selectedName =
        [profiles[@"selectedProfile"] isKindOfClass:NSString.class]
            ? profiles[@"selectedProfile"] : nil;
    NSDictionary *profile =
        [profiles[@"profiles"] isKindOfClass:NSDictionary.class]
            ? profiles[@"profiles"][selectedName] : nil;
    if (![profile isKindOfClass:NSDictionary.class]) profile = nil;
    NSString *version = profile[@"pocketjMinecraftVersion"] ?: profile[@"lastVersionId"];
    BOOL current =
        [name isEqualToString:getPrefObject(@"general.game_directory")];

    cell.imageView.image = [UIImage systemImageNamed:
        current ? @"folder.fill" : @"folder"];
    cell.textLabel.text = name;
    cell.detailTextLabel.text = version.length
        ? [NSString stringWithFormat:@"%@ · %@",
            [self loaderNameForProfile:profile], version]
        : localize(@"尚未配置 Minecraft 版本", nil);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *cellID = @"InstanceCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    } else {
        cell.imageView.image = nil;
        cell.userInteractionEnabled = YES;
        cell.accessoryView = nil;
    }

    [self setupInstanceCell:cell atRow:indexPath.row];

    cell.textLabel.enabled = cell.detailTextLabel.enabled = cell.userInteractionEnabled;
    [ModernUITheme styleCell:cell destructive:NO];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (indexPath.section != 0 ||
        indexPath.row < 0 ||
        indexPath.row >= self.instanceNames.count) {
        return;
    }
    NSString *name = self.instanceNames[indexPath.row];
    [self activateInstanceNamed:name];
    NSDictionary *profile = PLProfiles.current.selectedProfile;
    UIAlertController *actions = [UIAlertController
        alertControllerWithTitle:name message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];
    [actions addAction:[UIAlertAction actionWithTitle:localize(@"管理模组", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self presentModManagerForInstanceNamed:name];
        }]];
    [actions addAction:[UIAlertAction actionWithTitle:localize(@"光影、材质包与数据包", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *path = [self.instancesRoot stringByAppendingPathComponent:name];
            PocketJResourceLibraryViewController *resources =
                [[PocketJResourceLibraryViewController alloc] initWithInstanceName:name instancePath:path];
            [self.navigationController pushViewController:resources animated:YES];
        }]];
    [actions addAction:[UIAlertAction actionWithTitle:localize(@"编辑实例", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self actionEditProfile:profile ?: @{@"name": name}];
        }]];
    [actions addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    actions.popoverPresentationController.sourceView = cell;
    actions.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:actions animated:YES completion:nil];
}

#pragma mark Context Menu configuration

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.section != 0 ||
        indexPath.row < 0 ||
        indexPath.row >= self.instanceNames.count) {
        return;
    }

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSString *instanceName = self.instanceNames[indexPath.row];
    NSString *message = [NSString stringWithFormat:
        localize(@"将永久删除实例“%@”及其中的存档、模组、资源包和游戏配置。此操作无法撤销。", nil),
        instanceName];
    UIAlertController *confirmAlert = [UIAlertController
        alertControllerWithTitle:localize(@"确认删除实例？", nil)
        message:message
        preferredStyle:UIAlertControllerStyleActionSheet];
    confirmAlert.popoverPresentationController.sourceView = cell;
    confirmAlert.popoverPresentationController.sourceRect = cell.bounds;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"删除实例", nil)
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
        BOOL deletingCurrent = [instanceName isEqualToString:
            getPrefObject(@"general.game_directory")];
        NSString *fallback = nil;
        if (deletingCurrent) {
            for (NSString *candidate in self.instanceNames) {
                if (![candidate isEqualToString:instanceName]) {
                    fallback = candidate;
                    break;
                }
            }
            if (fallback) [self activateInstanceNamed:fallback];
        }
        NSString *path =
            [self.instancesRoot stringByAppendingPathComponent:instanceName];
        NSError *error = nil;
        if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
            showDialog(localize(@"无法删除实例", nil), error.localizedDescription);
            return;
        }
        if (deletingCurrent && fallback.length == 0) {
            // No placeholder instance: an empty list is a valid state.
            setPrefObject(@"general.game_directory", @"");
            NSString *gamePath = @(getenv("POJAV_GAME_DIR"));
            [NSFileManager.defaultManager removeItemAtPath:gamePath error:nil];
        }
        [self reloadInstanceNames];
        [tableView reloadData];
        [NSNotificationCenter.defaultCenter
            postNotificationName:@"LauncherProfilesDidChangeNotification"
                          object:nil];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil];
    [confirmAlert addAction:cancel];
    [confirmAlert addAction:ok];
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= self.instanceNames.count) {
        return UITableViewCellEditingStyleNone;
    }
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView
canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 &&
        indexPath.row < self.instanceNames.count;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 ||
        indexPath.row >= self.instanceNames.count) {
        return nil;
    }
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
        title:localize(@"删除", nil)
        handler:^(UIContextualAction *action, UIView *sourceView,
                  void (^completionHandler)(BOOL)) {
            [weakSelf tableView:tableView
                commitEditingStyle:UITableViewCellEditingStyleDelete
                 forRowAtIndexPath:indexPath];
            completionHandler(YES);
        }];
    deleteAction.image = [UIImage systemImageNamed:@"trash"];
    UISwipeActionsConfiguration *configuration =
        [UISwipeActionsConfiguration
            configurationWithActions:@[deleteAction]];
    // Short swipe keeps the red Delete button; swiping all the way invokes
    // the same action immediately and presents the confirmation sheet.
    configuration.performsFirstActionWithFullSwipe = YES;
    return configuration;
}

- (void)presentModManagerForInstanceNamed:(NSString *)instanceName {
    if (instanceName.length == 0) {
        return;
    }
    NSString *path = [self.instancesRoot
        stringByAppendingPathComponent:instanceName];
    ModManagerViewController *controller = [[ModManagerViewController alloc]
        initWithInstanceName:instanceName instancePath:path];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
