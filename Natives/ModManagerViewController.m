#import "ModManagerViewController.h"

#import "ModernUITheme.h"
#import "CurseForgeSecrets.local.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "UnzipKit.h"
#include <CommonCrypto/CommonDigest.h>

typedef NS_ENUM(NSInteger, PocketJModPage) {
    PocketJModPageInstalled,
    PocketJModPageBrowse,
};

typedef NS_ENUM(NSInteger, PocketJModSource) {
    PocketJModSourceModrinth,
    PocketJModSourceCurseForge,
};

@interface PocketJModVersionPickerViewController : UITableViewController
@property(nonatomic, copy) NSString *projectTitle;
@property(nonatomic, strong) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) void (^selectionHandler)(NSDictionary *item);
@end

@implementation PocketJModVersionPickerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.projectTitle;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
        target:self action:@selector(closePicker)];
}
- (void)closePicker {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Version"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"Version"];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 2;
    }
    NSDictionary *item = self.items[indexPath.row];
    BOOL compatible = [item[@"compatible"] boolValue];
    cell.textLabel.text = compatible ? item[@"title"] :
        [NSString stringWithFormat:@"%@ (%@)", item[@"title"],
            localize(@"不可用", nil)];
    cell.detailTextLabel.text = item[@"subtitle"];
    cell.imageView.image = [UIImage systemImageNamed:
        compatible ? @"checkmark.circle.fill" : @"exclamationmark.circle"];
    cell.imageView.tintColor = compatible ? UIColor.systemGreenColor
                                          : UIColor.systemOrangeColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        if (self.selectionHandler) self.selectionHandler(item);
    }];
}
@end

@interface ModManagerViewController () <UISearchResultsUpdating>
@property(nonatomic, copy) NSString *instanceName;
@property(nonatomic, copy) NSString *instancePath;
@property(nonatomic, copy) NSString *minecraftVersion;
@property(nonatomic, copy) NSString *loader;
@property(nonatomic) PocketJModPage page;
@property(nonatomic, strong) UISegmentedControl *pageControl;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, strong) NSArray<NSDictionary *> *installedMods;
@property(nonatomic, strong) NSArray<NSDictionary *> *catalogResults;
@property(nonatomic, strong) NSURLSessionDataTask *searchTask;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL compatibleOnly;
@property(nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *updatesByFile;
@property(nonatomic) PocketJModSource source;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *modIconCache;
@property(nonatomic, strong) NSMutableSet<NSString *> *iconsLoading;
@property(nonatomic, strong) NSMutableSet<NSString *> *modsWithoutIcons;
@end

@implementation ModManagerViewController

- (void)loadCatalogIconURL:(NSString *)URLString atIndexPath:(NSIndexPath *)indexPath {
    if (!URLString.length || [self.modIconCache objectForKey:URLString] ||
        [self.iconsLoading containsObject:URLString]) return;
    NSURL *URL = [NSURL URLWithString:URLString];
    if (!URL) return;
    [self.iconsLoading addObject:URLString];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:URL
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            UIImage *image = data ? [UIImage imageWithData:data] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.iconsLoading removeObject:URLString];
                UIImage *normalized = [weakSelf normalizedModIcon:image];
                if (normalized) [weakSelf.modIconCache setObject:normalized forKey:URLString];
                if (weakSelf.page != PocketJModPageBrowse) return;
                if (indexPath.row >= weakSelf.catalogResults.count) return;
                NSDictionary *current = weakSelf.catalogResults[indexPath.row];
                if (![current[@"iconURL"] isEqualToString:URLString]) return;
                UITableViewCell *cell = [weakSelf.tableView cellForRowAtIndexPath:indexPath];
                if (normalized) {
                    cell.imageView.image = normalized;
                    [cell setNeedsLayout];
                }
            });
        }] resume];
}

- (instancetype)initWithInstanceName:(NSString *)instanceName
                        instancePath:(NSString *)instancePath {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _instanceName = instanceName.copy;
        _instancePath = instancePath.copy;
        _compatibleOnly = YES;
        _modIconCache = [NSCache new];
        _iconsLoading = [NSMutableSet set];
        _modsWithoutIcons = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"管理模组", nil);
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;

    self.pageControl = [[UISegmentedControl alloc] initWithItems:@[
        localize(@"已安装", nil), localize(@"浏览", nil)
    ]];
    self.pageControl.selectedSegmentIndex = 0;
    [self.pageControl addTarget:self action:@selector(pageChanged:)
               forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.pageControl;

    self.searchController = [[UISearchController alloc]
        initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = localize(@"搜索模组", nil);
    self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
        menu:[self filterMenu]];
    [self readInstanceMetadata];
    [self reloadInstalledMods];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.page == PocketJModPageInstalled) [self reloadInstalledMods];
}

- (NSString *)modsPath {
    return [self.instancePath stringByAppendingPathComponent:@"mods"];
}

- (void)readInstanceMetadata {
    NSDictionary *root = parseJSONFromFile([self.instancePath
        stringByAppendingPathComponent:@"launcher_profiles.json"]);
    NSString *selected = root[@"selectedProfile"];
    NSDictionary *profile = root[@"profiles"][selected];
    NSString *versionID = profile[@"lastVersionId"] ?: @"";
    NSString *lower = versionID.lowercaseString;
    NSString *explicitLoader = [profile[@"pocketjLoader"] lowercaseString];
    NSSet *validLoaders = [NSSet setWithArray:@[@"vanilla", @"fabric", @"forge", @"neoforge", @"quilt"]];
    self.loader = [validLoaders containsObject:explicitLoader] ? explicitLoader :
        ([lower containsString:@"neoforge"] ? @"neoforge" :
        ([lower containsString:@"fabric"] ? @"fabric" :
        ([lower containsString:@"quilt"] ? @"quilt" :
        ([lower containsString:@"forge"] ? @"forge" : @"vanilla"))));

    NSDictionary *versionJSON = parseJSONFromFile([[[self.instancePath
        stringByAppendingPathComponent:@"versions"]
        stringByAppendingPathComponent:versionID]
        stringByAppendingPathComponent:[versionID stringByAppendingPathExtension:@"json"]]);
    self.minecraftVersion = profile[@"pocketjMinecraftVersion"];
    if (!self.minecraftVersion.length) self.minecraftVersion = versionJSON[@"inheritsFrom"];
    if (!self.minecraftVersion.length) {
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:@"[0-9]+\\.[0-9]+(?:\\.[0-9]+)?"
                                  options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:versionID
            options:0 range:NSMakeRange(0, versionID.length)];
        self.minecraftVersion = match ? [versionID substringWithRange:match.range] : versionID;
    }
}

- (void)reloadInstalledMods {
    [NSFileManager.defaultManager createDirectoryAtPath:self.modsPath
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray<NSString *> *files = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:self.modsPath error:nil] ?: @[];
    NSMutableArray *mods = [NSMutableArray array];
    for (NSString *file in files) {
        NSString *lower = file.lowercaseString;
        if (![lower hasSuffix:@".jar"] && ![lower hasSuffix:@".jar.disabled"] &&
            ![lower hasSuffix:@".disabled"]) continue;
        NSString *base = [file hasSuffix:@".disabled"]
            ? [file stringByDeletingPathExtension] : file;
        [mods addObject:@{
            @"fileName": file,
            @"title": base.stringByDeletingPathExtension,
            @"enabled": @(![file hasSuffix:@".disabled"]),
        }];
    }
    [mods sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"title"] localizedStandardCompare:b[@"title"]];
    }];
    self.installedMods = mods;
    [self.tableView reloadData];
    [self loadIconsForInstalledMods:mods];
}

- (UIImage *)normalizedModIcon:(UIImage *)image {
    if (!image) return nil;
    CGSize size = CGSizeMake(38, 38);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:
            CGRectMake(0, 0, size.width, size.height) cornerRadius:8];
        [clip addClip];
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

- (NSString *)firstStringValueInObject:(id)object {
    if ([object isKindOfClass:NSString.class]) return object;
    if ([object isKindOfClass:NSDictionary.class]) {
        for (id value in [(NSDictionary *)object allValues]) {
            NSString *result = [self firstStringValueInObject:value];
            if (result.length) return result;
        }
    }
    return nil;
}

- (NSString *)forgeIconPathFromData:(NSData *)data {
    NSString *toml = [[NSString alloc] initWithData:data
        encoding:NSUTF8StringEncoding];
    if (!toml.length) return nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"(?im)^\\s*logoFile\\s*=\\s*[\"']([^\"']+)[\"']"
        options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:toml options:0
        range:NSMakeRange(0, toml.length)];
    return match.numberOfRanges > 1
        ? [toml substringWithRange:[match rangeAtIndex:1]] : nil;
}

- (UIImage *)iconFromModJarAtPath:(NSString *)path {
    NSError *error = nil;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&error];
    if (!archive) return nil;
    NSArray<NSString *> *names = [archive listFilenames:&error] ?: @[];
    NSSet *nameSet = [NSSet setWithArray:names];
    NSString *iconPath = nil;

    NSData *fabricData = [archive extractDataFromFile:@"fabric.mod.json" error:nil];
    if (fabricData) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:fabricData
            options:0 error:nil];
        iconPath = [self firstStringValueInObject:json[@"icon"]];
    }
    if (!iconPath.length) {
        NSData *quiltData = [archive extractDataFromFile:@"quilt.mod.json" error:nil];
        NSDictionary *json = quiltData ? [NSJSONSerialization
            JSONObjectWithData:quiltData options:0 error:nil] : nil;
        iconPath = [self firstStringValueInObject:
            json[@"quilt_loader"][@"metadata"][@"icon"]];
    }
    if (!iconPath.length) {
        for (NSString *metadata in @[@"META-INF/mods.toml",
                                     @"META-INF/neoforge.mods.toml"]) {
            NSData *data = [archive extractDataFromFile:metadata error:nil];
            iconPath = [self forgeIconPathFromData:data];
            if (iconPath.length) break;
        }
    }
    if (iconPath.length && ![nameSet containsObject:iconPath]) iconPath = nil;
    if (!iconPath.length) {
        for (NSString *candidate in names) {
            NSString *leaf = candidate.lastPathComponent.lowercaseString;
            if ([leaf isEqualToString:@"icon.png"] ||
                [leaf isEqualToString:@"logo.png"] ||
                [leaf isEqualToString:@"mod_icon.png"]) {
                iconPath = candidate;
                break;
            }
        }
    }
    NSData *imageData = iconPath.length
        ? [archive extractDataFromFile:iconPath error:nil] : nil;
    return [self normalizedModIcon:[UIImage imageWithData:imageData]];
}

- (void)loadIconsForInstalledMods:(NSArray<NSDictionary *> *)mods {
    for (NSDictionary *mod in mods) {
        NSString *path = [self.modsPath
            stringByAppendingPathComponent:mod[@"fileName"]];
        if ([self.modIconCache objectForKey:path] ||
            [self.iconsLoading containsObject:path] ||
            [self.modsWithoutIcons containsObject:path]) continue;
        [self.iconsLoading addObject:path];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            UIImage *icon = [self iconFromModJarAtPath:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.iconsLoading removeObject:path];
                if (icon) [self.modIconCache setObject:icon forKey:path];
                else [self.modsWithoutIcons addObject:path];
                if (self.page == PocketJModPageInstalled) {
                    [self.tableView reloadData];
                }
            });
        });
    }
}

- (UIMenu *)filterMenu {
    __weak typeof(self) weakSelf = self;
    if (self.page == PocketJModPageInstalled) {
        UIAction *updates = [UIAction
            actionWithTitle:localize(@"检查更新", nil)
            image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
            identifier:nil handler:^(UIAction *action) {
                [weakSelf checkForUpdates];
            }];
        return [UIMenu menuWithTitle:@"" children:@[updates]];
    }
    UIAction *compatible = [UIAction
        actionWithTitle:localize(@"仅显示兼容版本", nil)
        image:[UIImage systemImageNamed:@"checkmark.shield"]
        identifier:nil handler:^(UIAction *action) {
            weakSelf.compatibleOnly = !weakSelf.compatibleOnly;
            weakSelf.navigationItem.rightBarButtonItem.menu = [weakSelf filterMenu];
            [weakSelf searchCatalog:weakSelf.searchController.searchBar.text ?: @""];
        }];
    compatible.state = self.compatibleOnly
        ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *modrinth = [UIAction actionWithTitle:@"Modrinth"
        image:[UIImage systemImageNamed:@"shippingbox"] identifier:nil
        handler:^(UIAction *action) {
            weakSelf.source = PocketJModSourceModrinth;
            weakSelf.catalogResults = @[];
            weakSelf.navigationItem.rightBarButtonItem.menu = [weakSelf filterMenu];
            [weakSelf searchCatalog:weakSelf.searchController.searchBar.text ?: @""];
        }];
    UIAction *curseForge = [UIAction actionWithTitle:@"CurseForge"
        image:[UIImage systemImageNamed:@"flame"] identifier:nil
        handler:^(UIAction *action) {
            weakSelf.source = PocketJModSourceCurseForge;
            weakSelf.catalogResults = @[];
            weakSelf.navigationItem.rightBarButtonItem.menu = [weakSelf filterMenu];
            [weakSelf searchCatalog:weakSelf.searchController.searchBar.text ?: @""];
        }];
    modrinth.state = self.source == PocketJModSourceModrinth
        ? UIMenuElementStateOn : UIMenuElementStateOff;
    curseForge.state = self.source == PocketJModSourceCurseForge
        ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIMenu *source = [UIMenu menuWithTitle:localize(@"来源", nil)
        image:[UIImage systemImageNamed:@"square.stack.3d.up"]
        identifier:nil options:0 children:@[modrinth, curseForge]];
    return [UIMenu menuWithTitle:localize(@"筛选", nil)
        children:@[source, compatible]];
}

- (void)pageChanged:(UISegmentedControl *)sender {
    self.page = sender.selectedSegmentIndex;
    self.navigationItem.rightBarButtonItem.menu = [self filterMenu];
    self.navigationItem.searchController =
        self.page == PocketJModPageBrowse ? self.searchController : nil;
    if (self.page == PocketJModPageBrowse && self.catalogResults.count == 0) {
        [self searchCatalog:@""];
    } else {
        [self.tableView reloadData];
    }
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(runDeferredSearch) object:nil];
    [self performSelector:@selector(runDeferredSearch)
               withObject:nil afterDelay:0.35];
}

- (void)runDeferredSearch {
    [self searchCatalog:self.searchController.searchBar.text ?: @""];
}

- (void)searchCatalog:(NSString *)query {
    if (self.source == PocketJModSourceCurseForge) {
        [self searchCurseForge:query];
        return;
    }
    [self.searchTask cancel];
    NSURLComponents *components = [NSURLComponents
        componentsWithString:@"https://api.modrinth.com/v2/search"];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"query" value:query],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"50"],
        [NSURLQueryItem queryItemWithName:@"index" value:@"relevance"],
    ]];
    NSMutableArray *facets = [NSMutableArray arrayWithObject:@[@"project_type:mod"]];
    if (self.compatibleOnly && self.minecraftVersion.length) {
        [facets addObject:@[[NSString stringWithFormat:@"versions:%@", self.minecraftVersion]]];
    }
    if (self.compatibleOnly && ![self.loader isEqualToString:@"vanilla"]) {
        [facets addObject:@[[NSString stringWithFormat:@"categories:%@", self.loader]]];
    }
    NSData *facetData = [NSJSONSerialization dataWithJSONObject:facets options:0 error:nil];
    [items addObject:[NSURLQueryItem queryItemWithName:@"facets"
        value:[[NSString alloc] initWithData:facetData encoding:NSUTF8StringEncoding]]];
    components.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:@"PocketJLauncher/1.1 (Mod browser)"
        forHTTPHeaderField:@"User-Agent"];
    self.loading = YES;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    self.searchTask = [NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSDictionary *json = data ? [NSJSONSerialization
                JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray *hits = [json[@"hits"] isKindOfClass:NSArray.class]
                ? json[@"hits"] : @[];
            NSMutableArray *mapped = [NSMutableArray array];
            for (NSDictionary *hit in hits) {
                NSArray *versions = hit[@"versions"] ?: @[];
                NSArray *categories = hit[@"categories"] ?: @[];
                BOOL versionOK = !weakSelf.minecraftVersion.length ||
                    [versions containsObject:weakSelf.minecraftVersion];
                BOOL loaderOK = [weakSelf.loader isEqualToString:@"vanilla"] ||
                    [categories containsObject:weakSelf.loader];
                [mapped addObject:@{
                    @"id": hit[@"project_id"] ?: @"",
                    @"title": hit[@"title"] ?: localize(@"未命名模组", nil),
                    @"description": hit[@"description"] ?: @"",
                    @"compatible": @(versionOK && loaderOK),
                    @"source": @"Modrinth",
                    @"iconURL": hit[@"icon_url"] ?: @"",
                }];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.loading = NO;
                if (!error) weakSelf.catalogResults = mapped;
                [weakSelf.tableView reloadData];
            });
        }];
    [self.searchTask resume];
}

- (NSNumber *)curseForgeLoaderType {
    NSDictionary *types = @{
        @"forge": @1, @"fabric": @4, @"quilt": @5, @"neoforge": @6
    };
    return types[self.loader] ?: @0;
}

- (NSMutableURLRequest *)curseForgeRequestWithURL:(NSURL *)URL {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:POCKETJ_CURSEFORGE_API_KEY forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"PocketJLauncher/1.1 (CurseForge mod browser)"
        forHTTPHeaderField:@"User-Agent"];
    return request;
}

- (void)searchCurseForge:(NSString *)query {
    [self.searchTask cancel];
    if (POCKETJ_CURSEFORGE_API_KEY.length == 0) {
        self.loading = NO;
        self.catalogResults = @[];
        [self.tableView reloadData];
        showDialog(localize(@"CurseForge 未配置", nil),
            localize(@"请先配置 CurseForge API Key。", nil));
        return;
    }
    NSURLComponents *components = [NSURLComponents
        componentsWithString:@"https://api.curseforge.com/v1/mods/search"];
    NSMutableArray *items = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"gameId" value:@"432"],
        [NSURLQueryItem queryItemWithName:@"classId" value:@"6"],
        [NSURLQueryItem queryItemWithName:@"pageSize" value:@"50"],
        [NSURLQueryItem queryItemWithName:@"sortField" value:@"2"],
        [NSURLQueryItem queryItemWithName:@"sortOrder" value:@"desc"],
    ]];
    if (query.length) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"searchFilter"
                                                    value:query]];
    }
    if (self.compatibleOnly && self.minecraftVersion.length) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"gameVersion"
                                                    value:self.minecraftVersion]];
        NSNumber *loaderType = [self curseForgeLoaderType];
        if (loaderType.integerValue > 0) {
            [items addObject:[NSURLQueryItem queryItemWithName:@"modLoaderType"
                value:loaderType.stringValue]];
        }
    }
    components.queryItems = items;
    self.loading = YES;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    self.searchTask = [NSURLSession.sharedSession
        dataTaskWithRequest:[self curseForgeRequestWithURL:components.URL]
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (id)response;
            NSDictionary *json = data ? [NSJSONSerialization
                JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray *results = [json[@"data"] isKindOfClass:NSArray.class]
                ? json[@"data"] : @[];
            NSMutableArray *mapped = [NSMutableArray array];
            for (NSDictionary *mod in results) {
                BOOL compatible = weakSelf.compatibleOnly;
                if (!weakSelf.compatibleOnly) {
                    compatible = NO;
                    for (NSDictionary *index in mod[@"latestFilesIndexes"]) {
                        BOOL versionOK = [index[@"gameVersion"]
                            isEqualToString:weakSelf.minecraftVersion];
                        NSInteger type = [index[@"modLoader"] integerValue];
                        BOOL loaderOK = [weakSelf.loader isEqualToString:@"vanilla"] ||
                            type == weakSelf.curseForgeLoaderType.integerValue;
                        if (versionOK && loaderOK) { compatible = YES; break; }
                    }
                }
                [mapped addObject:@{
                    @"id": [mod[@"id"] stringValue] ?: @"",
                    @"title": mod[@"name"] ?: localize(@"未命名模组", nil),
                    @"description": mod[@"summary"] ?: @"",
                    @"compatible": @(compatible),
                    @"source": @"CurseForge",
                    @"iconURL": mod[@"logo"][@"thumbnailUrl"] ?:
                        mod[@"logo"][@"url"] ?: @"",
                }];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.loading = NO;
                if (!error && http.statusCode >= 200 && http.statusCode < 300) {
                    weakSelf.catalogResults = mapped;
                } else {
                    NSString *message = json[@"message"] ?:
                        error.localizedDescription ?: localize(@"请检查 API Key 或网络连接。", nil);
                    showDialog(localize(@"CurseForge 加载失败", nil), message);
                }
                [weakSelf.tableView reloadData];
            });
        }];
    [self.searchTask resume];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    if (self.loading) return 1;
    return self.page == PocketJModPageInstalled
        ? self.installedMods.count : self.catalogResults.count;
}

- (NSString *)tableView:(UITableView *)tableView
 titleForHeaderInSection:(NSInteger)section {
    if (self.page == PocketJModPageInstalled) {
        return [NSString stringWithFormat:@"%@ · %@ · %@",
            self.instanceName, self.minecraftVersion ?: @"?",
            self.loader.capitalizedString];
    }
    return self.source == PocketJModSourceCurseForge
        ? @"CurseForge" : @"Modrinth";
}

- (NSString *)tableView:(UITableView *)tableView
 titleForFooterInSection:(NSInteger)section {
    if (self.page == PocketJModPageInstalled && self.installedMods.count == 0) {
        return localize(@"这个实例还没有安装模组。", nil);
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.loading) {
        UITableViewCell *cell = [[UITableViewCell alloc]
            initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        cell.textLabel.text = localize(@"正在加载模组…", nil);
        cell.accessoryView = spinner;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [ModernUITheme styleCell:cell destructive:NO];
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                     reuseIdentifier:@"ModCell"];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 2;
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = [UIImage systemImageNamed:@"shippingbox.fill"];
    NSDictionary *item = self.page == PocketJModPageInstalled
        ? self.installedMods[indexPath.row] : self.catalogResults[indexPath.row];
    if (self.page == PocketJModPageInstalled) {
        NSString *path = [self.modsPath
            stringByAppendingPathComponent:item[@"fileName"]];
        UIImage *modIcon = [self.modIconCache objectForKey:path];
        if (modIcon) cell.imageView.image = modIcon;
        NSDictionary *update = self.updatesByFile[item[@"fileName"]];
        cell.textLabel.text = update
            ? [NSString stringWithFormat:@"%@ · %@", item[@"title"],
               localize(@"有可用更新", nil)]
            : item[@"title"];
        cell.detailTextLabel.text = item[@"fileName"];
        UISwitch *toggle = [UISwitch new];
        toggle.on = [item[@"enabled"] boolValue];
        toggle.tag = indexPath.row;
        [toggle addTarget:self action:@selector(modSwitchChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = update ? UITableViewCellSelectionStyleDefault
                                     : UITableViewCellSelectionStyleNone;
    } else {
        BOOL compatible = [item[@"compatible"] boolValue];
        cell.textLabel.text = compatible ? item[@"title"] :
            [NSString stringWithFormat:@"%@ (%@)", item[@"title"],
             localize(@"不可用", nil)];
        cell.detailTextLabel.text = item[@"description"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        NSString *iconURL = item[@"iconURL"];
        UIImage *catalogIcon = iconURL.length
            ? [self.modIconCache objectForKey:iconURL] : nil;
        if (catalogIcon) {
            cell.imageView.image = catalogIcon;
        } else if (iconURL.length) {
            [self loadCatalogIconURL:iconURL atIndexPath:indexPath];
        }
    }
    [ModernUITheme styleCell:cell destructive:NO];
    return cell;
}

- (void)modSwitchChanged:(UISwitch *)sender {
    if (sender.tag >= self.installedMods.count) return;
    NSDictionary *item = self.installedMods[sender.tag];
    NSString *oldName = item[@"fileName"];
    NSString *newName = oldName;
    if (sender.isOn && [oldName hasSuffix:@".disabled"]) {
        newName = [oldName stringByDeletingPathExtension];
    } else if (!sender.isOn && ![oldName hasSuffix:@".disabled"]) {
        newName = [oldName stringByAppendingPathExtension:@"disabled"];
    }
    NSError *error = nil;
    BOOL moved = [NSFileManager.defaultManager moveItemAtPath:
        [self.modsPath stringByAppendingPathComponent:oldName]
        toPath:[self.modsPath stringByAppendingPathComponent:newName]
        error:&error];
    if (!moved) {
        showDialog(localize(@"无法更改模组状态", nil),
                   error.localizedDescription);
    }
    [self reloadInstalledMods];
}

- (void)tableView:(UITableView *)tableView
 didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.page == PocketJModPageInstalled && !self.loading &&
        indexPath.row < self.installedMods.count) {
        NSDictionary *item = self.installedMods[indexPath.row];
        NSDictionary *update = self.updatesByFile[item[@"fileName"]];
        if (update) [self presentUpdate:update forInstalledMod:item];
        return;
    }
    if (self.page != PocketJModPageBrowse || self.loading ||
        indexPath.row >= self.catalogResults.count) return;
    NSDictionary *item = self.catalogResults[indexPath.row];
    [self showProject:item
           sourceView:[tableView cellForRowAtIndexPath:indexPath]];
}

- (NSString *)sha1ForFileAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path
        options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *result = [NSMutableString
        stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (NSInteger i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x", digest[i]];
    }
    return result;
}

- (void)checkForUpdates {
    if (self.installedMods.count == 0 || !self.minecraftVersion.length) return;
    self.loading = YES;
    [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *hashes = [NSMutableArray array];
        NSMutableDictionary *fileByHash = [NSMutableDictionary dictionary];
        for (NSDictionary *mod in self.installedMods) {
            NSString *fileName = mod[@"fileName"];
            NSString *hash = [self sha1ForFileAtPath:
                [self.modsPath stringByAppendingPathComponent:fileName]];
            if (!hash.length) continue;
            [hashes addObject:hash];
            fileByHash[hash] = fileName;
        }
        if (hashes.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.loading = NO;
                [self.tableView reloadData];
            });
            return;
        }
        NSDictionary *body = @{
            @"hashes": hashes,
            @"algorithm": @"sha1",
            @"loaders": @[[self.loader isEqualToString:@"vanilla"]
                ? @"minecraft" : self.loader],
            @"game_versions": @[self.minecraftVersion],
            @"version_types": @[@"release", @"beta", @"alpha"],
        };
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
            [NSURL URLWithString:@"https://api.modrinth.com/v2/version_files/update"]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body
            options:0 error:nil];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"PocketJLauncher/1.1 (Mod updater)"
            forHTTPHeaderField:@"User-Agent"];
        [[[NSURLSession sharedSession] dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSDictionary *versions = data ? [NSJSONSerialization
                    JSONObjectWithData:data options:0 error:nil] : nil;
                NSMutableDictionary *updates = [NSMutableDictionary dictionary];
                if ([versions isKindOfClass:NSDictionary.class]) {
                    [versions enumerateKeysAndObjectsUsingBlock:
                        ^(NSString *hash, NSDictionary *version, BOOL *stop) {
                        NSString *fileName = fileByHash[hash];
                        NSDictionary *primary = nil;
                        for (NSDictionary *file in version[@"files"]) {
                            if ([file[@"primary"] boolValue]) { primary = file; break; }
                        }
                        if (!primary) primary = [version[@"files"] firstObject];
                        NSString *newHash = primary[@"hashes"][@"sha1"];
                        if (fileName.length && primary[@"url"] &&
                            newHash.length && ![newHash isEqualToString:hash]) {
                            NSMutableDictionary *entry = version.mutableCopy;
                            entry[@"selectedFile"] = primary;
                            updates[fileName] = entry;
                        }
                    }];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.loading = NO;
                    if (error) {
                        showDialog(localize(@"检查更新失败", nil),
                                   error.localizedDescription);
                    } else {
                        self.updatesByFile = updates;
                        if (updates.count == 0) {
                            showDialog(localize(@"已是最新版本", nil),
                                localize(@"已安装的 Modrinth 模组暂无更新。", nil));
                        }
                    }
                    [self.tableView reloadData];
                });
            }] resume];
    });
}

- (void)presentUpdate:(NSDictionary *)update
       forInstalledMod:(NSDictionary *)installed {
    NSString *version = update[@"version_number"] ?: update[@"name"] ?: @"";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"更新模组", nil)
        message:[NSString stringWithFormat:localize(@"可更新到 %@。", nil), version]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"更新", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self downloadModFile:update[@"selectedFile"]
                replacingFile:installed[@"fileName"]];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showProject:(NSDictionary *)item sourceView:(UIView *)sourceView {
    BOOL compatible = [item[@"compatible"] boolValue];
    NSString *message = compatible ? item[@"description"] :
        localize(@"该模组与当前 Minecraft 版本或加载器不匹配，仍可继续查看并安装。", nil);
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:item[@"title"] message:message
        preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction
        actionWithTitle:localize(@"选择版本并安装", nil)
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self loadVersionsForProject:item];
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sourceView;
    sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)loadVersionsForProject:(NSDictionary *)project {
    if ([project[@"source"] isEqualToString:@"CurseForge"]) {
        [self loadCurseForgeFilesForProject:project];
        return;
    }
    NSString *endpoint = [NSString stringWithFormat:
        @"https://api.modrinth.com/v2/project/%@/version", project[@"id"]];
    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:endpoint]];
    [request setValue:@"PocketJLauncher/1.1 (Mod installer)"
        forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSArray *versions = data ? [NSJSONSerialization
                JSONObjectWithData:data options:0 error:nil] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![versions isKindOfClass:NSArray.class]) {
                    showDialog(localize(@"加载失败", nil),
                        error.localizedDescription ?:
                        localize(@"无法获取模组版本。", nil));
                    return;
                }
                [weakSelf presentVersionPicker:versions project:project];
            });
        }] resume];
}

- (void)loadCurseForgeFilesForProject:(NSDictionary *)project {
    NSURLComponents *components = [NSURLComponents componentsWithString:
        [NSString stringWithFormat:@"https://api.curseforge.com/v1/mods/%@/files",
            project[@"id"]]];
    NSMutableArray *items = [NSMutableArray arrayWithObject:
        [NSURLQueryItem queryItemWithName:@"pageSize" value:@"50"]];
    if (self.compatibleOnly && self.minecraftVersion.length) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"gameVersion"
                                                    value:self.minecraftVersion]];
        NSNumber *loaderType = [self curseForgeLoaderType];
        if (loaderType.integerValue > 0) {
            [items addObject:[NSURLQueryItem queryItemWithName:@"modLoaderType"
                value:loaderType.stringValue]];
        }
    }
    components.queryItems = items;
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession]
        dataTaskWithRequest:[self curseForgeRequestWithURL:components.URL]
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (id)response;
            NSDictionary *json = data ? [NSJSONSerialization
                JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray *files = [json[@"data"] isKindOfClass:NSArray.class]
                ? json[@"data"] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!files || error || http.statusCode < 200 || http.statusCode >= 300) {
                    showDialog(localize(@"加载失败", nil),
                        json[@"message"] ?: error.localizedDescription ?:
                        localize(@"无法获取模组版本。", nil));
                    return;
                }
                [weakSelf presentCurseForgeFilePicker:files project:project];
            });
        }] resume];
}

- (BOOL)curseForgeFileIsCompatible:(NSDictionary *)file {
    NSArray *versions = file[@"gameVersions"] ?: @[];
    BOOL versionOK = !self.minecraftVersion.length ||
        [versions containsObject:self.minecraftVersion];
    if ([self.loader isEqualToString:@"vanilla"]) return versionOK;
    NSString *wanted = @{
        @"fabric": @"fabric", @"forge": @"forge", @"quilt": @"quilt",
        @"neoforge": @"neoforge"
    }[self.loader];
    BOOL loaderOK = NO;
    for (NSString *entry in versions) {
        if ([entry.lowercaseString isEqualToString:wanted]) {
            loaderOK = YES;
            break;
        }
    }
    return versionOK && loaderOK;
}

- (void)presentCurseForgeFilePicker:(NSArray<NSDictionary *> *)files
                            project:(NSDictionary *)project {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *file in files) {
        BOOL compatible = [self curseForgeFileIsCompatible:file];
        if (self.compatibleOnly && !compatible) continue;
        NSString *title = file[@"displayName"] ?: file[@"fileName"];
        NSArray *gameVersions = file[@"gameVersions"] ?: @[];
        [items addObject:@{
            @"title": title ?: localize(@"未命名版本", nil),
            @"subtitle": [gameVersions componentsJoinedByString:@" · "],
            @"compatible": @(compatible),
            @"payload": file,
        }];
    }
    [self presentVersionItems:items project:project curseForge:YES];
}

- (void)confirmIncompatibleCurseForgeFile:(NSDictionary *)file {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"兼容性警告", nil)
        message:localize(@"该文件可能无法在当前实例中运行。", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"仍然安装", nil)
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self installCurseForgeFile:file];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)installCurseForgeFile:(NSDictionary *)file {
    NSString *downloadURL = file[@"downloadUrl"];
    if (downloadURL.length) {
        [self downloadModFile:@{
            @"url": downloadURL,
            @"filename": file[@"fileName"] ?: [NSURL URLWithString:downloadURL].lastPathComponent
        }];
        return;
    }
    NSString *endpoint = [NSString stringWithFormat:
        @"https://api.curseforge.com/v1/mods/%@/files/%@/download-url",
        file[@"modId"], file[@"id"]];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession]
        dataTaskWithRequest:[self curseForgeRequestWithURL:[NSURL URLWithString:endpoint]]
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSDictionary *json = data ? [NSJSONSerialization
                JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *URL = json[@"data"];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!URL.length) {
                    showDialog(localize(@"安装失败", nil),
                        error.localizedDescription ?:
                        localize(@"该 CurseForge 文件没有可用的下载地址。", nil));
                    return;
                }
                [weakSelf downloadModFile:@{
                    @"url": URL,
                    @"filename": file[@"fileName"] ?: [NSURL URLWithString:URL].lastPathComponent
                }];
            });
        }] resume];
}

- (void)presentVersionPicker:(NSArray<NSDictionary *> *)versions
                     project:(NSDictionary *)project {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *version in versions) {
        NSArray *gameVersions = version[@"game_versions"] ?: @[];
        NSArray *loaders = version[@"loaders"] ?: @[];
        BOOL compatible = [gameVersions containsObject:self.minecraftVersion] &&
            ([self.loader isEqualToString:@"vanilla"] ||
             [loaders containsObject:self.loader]);
        if (self.compatibleOnly && !compatible) continue;
        NSDictionary *primary = nil;
        for (NSDictionary *file in version[@"files"]) {
            if ([file[@"primary"] boolValue]) { primary = file; break; }
        }
        if (!primary) primary = [version[@"files"] firstObject];
        if (!primary[@"url"]) continue;
        NSString *title = version[@"name"] ?: primary[@"filename"];
        NSString *subtitle = [NSString stringWithFormat:@"%@ · %@",
            [gameVersions componentsJoinedByString:@", "],
            [loaders componentsJoinedByString:@", "]];
        [items addObject:@{
            @"title": title ?: localize(@"未命名版本", nil),
            @"subtitle": subtitle,
            @"compatible": @(compatible),
            @"payload": primary,
        }];
    }
    [self presentVersionItems:items project:project curseForge:NO];
}

- (void)presentVersionItems:(NSArray<NSDictionary *> *)items
                    project:(NSDictionary *)project
                 curseForge:(BOOL)isCurseForge {
    if (items.count == 0) {
        showDialog(localize(@"没有匹配版本", nil),
            localize(@"没有找到匹配文件。可关闭“仅显示兼容版本”后查看其他文件。", nil));
        return;
    }
    PocketJModVersionPickerViewController *picker =
        [PocketJModVersionPickerViewController new];
    picker.projectTitle = project[@"title"];
    picker.items = items;
    __weak typeof(self) weakSelf = self;
    picker.selectionHandler = ^(NSDictionary *item) {
        BOOL compatible = [item[@"compatible"] boolValue];
        NSDictionary *payload = item[@"payload"];
        if (isCurseForge) {
            if (compatible) [weakSelf installCurseForgeFile:payload];
            else [weakSelf confirmIncompatibleCurseForgeFile:payload];
        } else {
            if (compatible) [weakSelf downloadModFile:payload];
            else [weakSelf confirmIncompatibleDownload:payload];
        }
    };
    UINavigationController *navigation = [[UINavigationController alloc]
        initWithRootViewController:picker];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        navigation.sheetPresentationController.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent
        ];
    }
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)confirmIncompatibleDownload:(NSDictionary *)file {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:localize(@"兼容性警告", nil)
        message:localize(@"该文件可能无法在当前实例中运行。", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil)
        style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"仍然安装", nil)
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self downloadModFile:file];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)downloadModFile:(NSDictionary *)file {
    [self downloadModFile:file replacingFile:nil];
}

- (void)downloadModFile:(NSDictionary *)file
          replacingFile:(NSString *)replacedFileName {
    NSURL *URL = [NSURL URLWithString:file[@"url"]];
    NSString *fileName = file[@"filename"] ?: URL.lastPathComponent;
    if (!URL || !fileName.length) return;
    self.loading = YES;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] downloadTaskWithURL:URL
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSError *moveError = error;
            if (location && !error) {
                [NSFileManager.defaultManager createDirectoryAtPath:weakSelf.modsPath
                    withIntermediateDirectories:YES attributes:nil error:nil];
                NSString *destination = [weakSelf.modsPath
                    stringByAppendingPathComponent:fileName];
                [NSFileManager.defaultManager removeItemAtPath:destination error:nil];
                [NSFileManager.defaultManager moveItemAtURL:location
                    toURL:[NSURL fileURLWithPath:destination] error:&moveError];
                if (!moveError && replacedFileName.length &&
                    ![replacedFileName isEqualToString:fileName]) {
                    [NSFileManager.defaultManager removeItemAtPath:
                        [weakSelf.modsPath stringByAppendingPathComponent:
                            replacedFileName] error:nil];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.loading = NO;
                if (moveError) {
                    showDialog(localize(@"安装失败", nil),
                               moveError.localizedDescription);
                } else {
                    showDialog(localize(@"安装完成", nil), fileName);
                }
                weakSelf.updatesByFile = @{};
                [weakSelf reloadInstalledMods];
            });
        }] resume];
}

@end
