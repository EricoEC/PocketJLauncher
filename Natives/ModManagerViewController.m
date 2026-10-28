#import "ModManagerViewController.h"

#import "ModernUITheme.h"
#if __has_include("CurseForgeSecrets.local.h")
#import "CurseForgeSecrets.local.h"
#else
#import "CurseForgeSecrets.sample.h"
#endif
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "UnzipKit.h"
#import "PocketJModStore.h"
#import "PocketJDownloadClient.h"
#import "PocketJAddonService.h"
#import "PocketJAddonVersionPicker.h"
#import "PocketJInstanceContext.h"
#import "PocketJModSearchIndex.h"
#import "SurfaceViewController.h"
#include <CommonCrypto/CommonDigest.h>

typedef NS_ENUM(NSInteger, PocketJModPage) {
    PocketJModPageInstalled,
    PocketJModPageBrowse,
};

typedef NS_ENUM(NSInteger, PocketJModSource) {
    PocketJModSourceModrinth,
    PocketJModSourceCurseForge,
};

@interface PocketJModVersionPickerViewController () <UISearchResultsUpdating>
@property(nonatomic) NSArray<NSDictionary *> *filteredItems;
@end
@implementation PocketJModVersionPickerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.projectTitle;
    self.filteredItems=self.items;
    UISearchController *search=[[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater=self; search.obscuresBackgroundDuringPresentation=NO;
    search.searchBar.placeholder=localize(@"搜索版本",nil);
    self.navigationItem.searchController=search; self.definesPresentationContext=YES;
    [ModernUITheme styleController:self]; [ModernUITheme styleTableView:self.tableView];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
        target:self action:@selector(closePicker)];
}
- (void)closePicker {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    NSString *query=search.searchBar.text ?: @"";
    self.filteredItems=query.length ? [self.items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings) {
        NSString *text=[NSString stringWithFormat:@"%@ %@",item[@"title"] ?: @"",item[@"subtitle"] ?: @""];
        return [text rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound;
    }]]:self.items;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredItems.count;
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
    NSDictionary *item = self.filteredItems[indexPath.row];
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
    NSDictionary *item = self.filteredItems[indexPath.row];
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        if (self.selectionHandler) self.selectionHandler(item);
    }];
}
@end

@interface PocketJDependencyPreview : UITableViewController
@property(nonatomic) NSArray<NSDictionary *> *files;
@property(nonatomic, copy) void (^install)(NSInteger mode);
@end
@implementation PocketJDependencyPreview
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=localize(@"依赖安装计划",nil);
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=65;
    [ModernUITheme styleController:self]; [ModernUITheme styleTableView:self.tableView];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    __weak typeof(self) weakSelf=self;
    NSMutableArray *actions=[NSMutableArray array];
    NSArray *titles=@[@"安装必需项",@"包括可选依赖",@"仅安装所选模组"];
    for (NSUInteger mode=0;mode<titles.count;mode++) {
        [actions addObject:[UIAction actionWithTitle:localize(titles[mode],nil) image:nil identifier:nil handler:^(UIAction *action) {
            [weakSelf.navigationController dismissViewControllerAnimated:YES completion:^{ if (weakSelf.install) weakSelf.install(mode); }];
        }]];
    }
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:localize(@"安装",nil) menu:[UIMenu menuWithTitle:@"" children:actions]];
}
- (void)close { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.files.count; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { return localize(@"默认安装必需依赖；可从右上角选择包括可选依赖或仅安装所选模组。",nil); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSDictionary *file=self.files[index.row];
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=file[@"filename"]; cell.textLabel.numberOfLines=0;
    cell.detailTextLabel.text=localize([file[@"pjOptional"] boolValue] ? @"可选依赖（默认不安装）":@"必需项",nil);
    cell.accessoryType=[file[@"pjOptional"] boolValue] ? UITableViewCellAccessoryNone:UITableViewCellAccessoryCheckmark;
    cell.selectionStyle=UITableViewCellSelectionStyleNone; [ModernUITheme styleCell:cell destructive:NO]; return cell;
}
@end

@interface ModManagerViewController () <UISearchResultsUpdating, UIDocumentPickerDelegate>
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
@property(nonatomic) PocketJModStore *modStore;
@property(nonatomic) NSArray<NSDictionary *> *allInstalledMods;
@property(nonatomic) NSUInteger scanGeneration;
@property(nonatomic) UIBarButtonItem *filterButton;
@property(nonatomic) NSDictionary *versionReplacement;
@property(nonatomic) NSString *downloadTaskID;
@property(nonatomic) UIProgressView *downloadProgress;
@property(nonatomic) PocketJAddonService *addonService;
@property(nonatomic) BOOL importingSearchIndex;
@property(nonatomic) NSOperationQueue *iconQueue;
@property(nonatomic) NSArray<NSDictionary *> *pendingInstallFiles;
@property(nonatomic) NSUInteger pendingInstallIndex;
@property(nonatomic) BOOL downloadPaused;
@property(nonatomic) NSUInteger catalogOffset;
@property(nonatomic) NSUInteger searchGeneration;
@property(nonatomic) BOOL catalogHasMore;
@property(nonatomic) BOOL loadingMore;
@property(nonatomic) NSString *catalogQuery;
@end

@implementation ModManagerViewController

- (void)setLoading:(BOOL)loading {
    _loading=loading; self.pageControl.enabled=!loading;
    self.editButtonItem.enabled=!loading && self.page==PocketJModPageInstalled;
}

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
        _modStore = [[PocketJModStore alloc] initWithInstancePath:instancePath];
        _addonService = [[PocketJAddonService alloc] initWithCurseForgeKey:POCKETJ_CURSEFORGE_API_KEY];
        _iconQueue=[NSOperationQueue new]; _iconQueue.maxConcurrentOperationCount=2;
        _modIconCache.countLimit=256;
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
    self.filterButton = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
        menu:[self filterMenu]];
    self.navigationItem.rightBarButtonItems = @[self.filterButton,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importMods)],
        self.editButtonItem];
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.navigationItem.searchController = self.searchController;
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
    PocketJInstanceContext *context=[[PocketJInstanceContext alloc] initWithInstancePath:self.instancePath];
    self.loader=context.loader; self.minecraftVersion=context.minecraftVersion;
}

- (void)reloadInstalledMods {
    NSUInteger generation = ++self.scanGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSArray *mods = [self.modStore scan:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.scanGeneration) return;
            self.allInstalledMods = mods;
            self.installedMods = [PocketJModStore filterMods:mods query:self.searchController.searchBar.text ?: @""];
            if (error) showDialog(localize(@"读取模组失败", nil), error.localizedDescription);
            if (self.page == PocketJModPageInstalled) [self.tableView reloadData];
            [self loadIconsForInstalledMods:mods];
        });
    });
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
        [self.iconQueue addOperationWithBlock:^{
            UIImage *icon = [self iconFromModJarAtPath:path];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.iconsLoading removeObject:path];
                if (icon) [self.modIconCache setObject:icon forKey:path];
                else [self.modsWithoutIcons addObject:path];
                if (self.page == PocketJModPageInstalled) {
                    for (NSIndexPath *index in self.tableView.indexPathsForVisibleRows) {
                        if (index.row < self.installedMods.count && [self.installedMods[index.row][@"fileName"] isEqual:mod[@"fileName"]]) {
                            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:index];
                            if (icon) cell.imageView.image = icon;
                        }
                    }
                }
            });
        }];
    }
}

- (UIMenu *)filterMenu {
    __weak typeof(self) weakSelf = self;
    if (self.loading && self.downloadTaskID.length) {
        UIAction *pause=[UIAction actionWithTitle:localize(@"暂停下载",nil) image:[UIImage systemImageNamed:@"pause.fill"] identifier:nil handler:^(UIAction *action) { weakSelf.downloadPaused=YES; [PocketJDownloadClient.shared pause:weakSelf.downloadTaskID]; }];
        UIAction *cancel=[UIAction actionWithTitle:localize(@"取消下载",nil) image:[UIImage systemImageNamed:@"xmark"] identifier:nil handler:^(UIAction *action) { weakSelf.pendingInstallFiles=nil; [PocketJDownloadClient.shared cancel:weakSelf.downloadTaskID]; }];
        return [UIMenu menuWithTitle:@"" children:@[pause,cancel]];
    }
    if (self.downloadPaused && self.pendingInstallFiles.count) {
        UIAction *resume=[UIAction actionWithTitle:localize(@"继续下载",nil) image:[UIImage systemImageNamed:@"play.fill"] identifier:nil handler:^(UIAction *action) { weakSelf.downloadPaused=NO; [weakSelf installFiles:weakSelf.pendingInstallFiles index:weakSelf.pendingInstallIndex]; }];
        return [UIMenu menuWithTitle:@"" children:@[resume]];
    }
    if (self.page == PocketJModPageInstalled) {
        UIAction *updates = [UIAction
            actionWithTitle:localize(@"检查更新", nil)
            image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]
            identifier:nil handler:^(UIAction *action) {
                [weakSelf checkForUpdates];
            }];
        UIAction *batch = [UIAction actionWithTitle:localize(@"所选模组操作", nil)
            image:[UIImage systemImageNamed:@"checklist"] identifier:nil handler:^(UIAction *action) { [weakSelf showBatchActions]; }];
        UIAction *index=[UIAction actionWithTitle:localize(@"导入中文搜索索引",nil) image:[UIImage systemImageNamed:@"character.book.closed"] identifier:nil handler:^(UIAction *action) { [weakSelf importSearchIndex]; }];
        return [UIMenu menuWithTitle:@"" children:@[updates, batch, index]];
    }
    UIAction *compatible = [UIAction
        actionWithTitle:localize(@"仅显示兼容版本", nil)
        image:[UIImage systemImageNamed:@"checkmark.shield"]
        identifier:nil handler:^(UIAction *action) {
            weakSelf.compatibleOnly = !weakSelf.compatibleOnly;
            weakSelf.filterButton.menu = [weakSelf filterMenu];
            [weakSelf searchCatalog:weakSelf.searchController.searchBar.text ?: @""];
        }];
    compatible.state = self.compatibleOnly
        ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *modrinth = [UIAction actionWithTitle:@"Modrinth"
        image:[UIImage systemImageNamed:@"shippingbox"] identifier:nil
        handler:^(UIAction *action) {
            weakSelf.source = PocketJModSourceModrinth;
            weakSelf.catalogResults = @[];
            weakSelf.filterButton.menu = [weakSelf filterMenu];
            [weakSelf searchCatalog:weakSelf.searchController.searchBar.text ?: @""];
        }];
    UIAction *curseForge = [UIAction actionWithTitle:@"CurseForge"
        image:[UIImage systemImageNamed:@"flame"] identifier:nil
        handler:^(UIAction *action) {
            weakSelf.source = PocketJModSourceCurseForge;
            weakSelf.catalogResults = @[];
            weakSelf.filterButton.menu = [weakSelf filterMenu];
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
    [self.searchTask cancel]; self.searchGeneration++; self.loadingMore=NO; self.loading=NO;
    self.page = sender.selectedSegmentIndex;
    [self setEditing:NO animated:NO];
    self.editButtonItem.enabled = self.page == PocketJModPageInstalled;
    self.filterButton.menu = [self filterMenu];
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
    if (self.page == PocketJModPageInstalled) {
        self.installedMods = [PocketJModStore filterMods:self.allInstalledMods ?: @[] query:self.searchController.searchBar.text ?: @""];
        [self.tableView reloadData];
        return;
    }
    [self searchCatalog:self.searchController.searchBar.text ?: @""];
}

- (void)searchCatalog:(NSString *)query {
    self.catalogQuery=[PocketJModSearchIndex.shared onlineQuery:query installed:self.allInstalledMods ?: @[]];
    self.catalogOffset=0; self.catalogHasMore=NO;
    [self fetchCatalogAppend:NO];
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)index {
    if (self.page==PocketJModPageBrowse && index.row+1==self.catalogResults.count && self.catalogHasMore && !self.loading && !self.loadingMore) {
        self.catalogOffset+=50; [self fetchCatalogAppend:YES];
    }
}
- (void)fetchCatalogAppend:(BOOL)append {
    [self.searchTask cancel]; NSUInteger generation=++self.searchGeneration, offset=self.catalogOffset;
    BOOL cf=self.source==PocketJModSourceCurseForge;
    if (cf && !POCKETJ_CURSEFORGE_API_KEY.length) { self.loading=NO; self.catalogResults=@[]; [self.tableView reloadData]; showDialog(localize(@"CurseForge 未配置",nil),localize(@"请先配置 CurseForge API Key。",nil)); return; }
    NSURLComponents *parts=[NSURLComponents componentsWithString:cf ? @"https://api.curseforge.com/v1/mods/search":@"https://api.modrinth.com/v2/search"];
    NSMutableArray *query=[NSMutableArray array];
    if (cf) {
        [query addObjectsFromArray:@[[NSURLQueryItem queryItemWithName:@"gameId" value:@"432"],[NSURLQueryItem queryItemWithName:@"classId" value:@"6"],[NSURLQueryItem queryItemWithName:@"pageSize" value:@"50"],[NSURLQueryItem queryItemWithName:@"index" value:[@(offset) stringValue]],[NSURLQueryItem queryItemWithName:@"searchFilter" value:self.catalogQuery ?: @""],[NSURLQueryItem queryItemWithName:@"sortField" value:@"2"],[NSURLQueryItem queryItemWithName:@"sortOrder" value:@"desc"]]];
        if (self.compatibleOnly && self.minecraftVersion.length) [query addObject:[NSURLQueryItem queryItemWithName:@"gameVersion" value:self.minecraftVersion]];
        if (self.compatibleOnly && self.curseForgeLoaderType.integerValue) [query addObject:[NSURLQueryItem queryItemWithName:@"modLoaderType" value:self.curseForgeLoaderType.stringValue]];
    } else {
        NSMutableArray *facets=[NSMutableArray arrayWithObject:@[@"project_type:mod"]];
        if (self.compatibleOnly && self.minecraftVersion.length) [facets addObject:@[[@"versions:" stringByAppendingString:self.minecraftVersion]]];
        if (self.compatibleOnly && ![self.loader isEqual:@"vanilla"]) [facets addObject:@[[@"categories:" stringByAppendingString:self.loader]]];
        NSString *encoded=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:facets options:0 error:nil] encoding:NSUTF8StringEncoding];
        [query addObjectsFromArray:@[[NSURLQueryItem queryItemWithName:@"query" value:self.catalogQuery ?: @""],[NSURLQueryItem queryItemWithName:@"limit" value:@"50"],[NSURLQueryItem queryItemWithName:@"offset" value:[@(offset) stringValue]],[NSURLQueryItem queryItemWithName:@"index" value:@"relevance"],[NSURLQueryItem queryItemWithName:@"facets" value:encoded]]];
    }
    parts.queryItems=query;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:parts.URL]; request.timeoutInterval=25;
    [request setValue:@"PocketJLauncher/1.5 (mod catalog)" forHTTPHeaderField:@"User-Agent"];
    if (cf) [request setValue:POCKETJ_CURSEFORGE_API_KEY forHTTPHeaderField:@"x-api-key"];
    self.loadingMore=append; self.loading=!append;
    if (!append) [self.tableView reloadData];
    self.searchTask=[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        id object=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSDictionary *root=[object isKindOfClass:NSDictionary.class] ? object:@{};
        NSArray *raw=[root[cf ? @"data":@"hits"] isKindOfClass:NSArray.class] ? root[cf ? @"data":@"hits"]:@[];
        NSMutableArray *mapped=[NSMutableArray array];
        for (NSDictionary *item in raw) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSString *identifier=cf ? [item[@"id"] description]:item[@"project_id"];
            if (![identifier isKindOfClass:NSString.class] || !identifier.length) continue;
            BOOL compatible=self.compatibleOnly;
            if (!self.compatibleOnly) {
                if (cf) {
                    for (NSDictionary *index in item[@"latestFilesIndexes"]) if ([index[@"gameVersion"] isEqual:self.minecraftVersion] && ([self.loader isEqual:@"vanilla"] || [index[@"modLoader"] integerValue]==self.curseForgeLoaderType.integerValue)) { compatible=YES; break; }
                } else compatible=[item[@"versions"] containsObject:self.minecraftVersion] && ([self.loader isEqual:@"vanilla"] || [item[@"categories"] containsObject:self.loader]);
            }
            NSDictionary *logo=[item[@"logo"] isKindOfClass:NSDictionary.class] ? item[@"logo"]:@{};
            id icon=cf ? (logo[@"thumbnailUrl"] ?: logo[@"url"]):item[@"icon_url"];
            [mapped addObject:@{@"id":identifier,@"title":item[cf ? @"name":@"title"] ?: @"",@"description":item[cf ? @"summary":@"description"] ?: @"",@"source":cf ? @"CurseForge":@"Modrinth",@"compatible":@(compatible),@"iconURL":[icon isKindOfClass:NSString.class] ? icon:@""}];
        }
        NSInteger status=[(NSHTTPURLResponse *)response statusCode];
        NSUInteger total=cf ? [root[@"pagination"][@"totalCount"] unsignedIntegerValue]:[root[@"total_hits"] unsignedIntegerValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation!=self.searchGeneration || self.page!=PocketJModPageBrowse) return;
            self.loading=NO; self.loadingMore=NO;
            if (error || status<200 || status>=300 || ![object isKindOfClass:NSDictionary.class]) {
                self.catalogHasMore=NO;
                if (error.code!=NSURLErrorCancelled) showDialog(localize(@"加载失败",nil),error.localizedDescription ?: [NSString stringWithFormat:NSLocalizedString(@"Catalog returned HTTP %ld.",nil),(long)status]);
            } else {
                self.catalogResults=append ? [(self.catalogResults ?: @[]) arrayByAddingObjectsFromArray:mapped]:mapped;
                self.catalogHasMore=mapped.count==50 && (!total || offset+mapped.count<total);
            }
            [self.tableView reloadData];
        });
    }]; [self.searchTask resume];
}

- (NSNumber *)curseForgeLoaderType {
    NSDictionary *types = @{
        @"forge": @1, @"fabric": @4, @"quilt": @5, @"neoforge": @6
    };
    return types[self.loader] ?: @0;
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
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@%@", item[@"fileName"],
            [item[@"notes"] length] ? @"\n" : @"", item[@"notes"] ?: @""];
        UISwitch *toggle = [UISwitch new];
        toggle.on = [item[@"enabled"] boolValue];
        toggle.tag = indexPath.row;
        toggle.accessibilityIdentifier = item[@"fileName"];
        toggle.enabled = ![SurfaceViewController isRunning] && !self.loading && !self.editing;
        [toggle addTarget:self action:@selector(modSwitchChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
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
    if (![self allowModMutation]) { sender.on = !sender.on; return; }
    if (!sender.on) {
        NSDictionary *mod=[self.modStore recordForFile:sender.accessibilityIdentifier];
        NSArray *dependents=[self dependentsOfMods:@[mod ?: @{}]];
        if (dependents.count) {
            sender.on=YES;
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:localize(@"依赖提醒",nil) message:[dependents componentsJoinedByString:@"\n"] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消",nil) style:UIAlertActionStyleCancel handler:nil]];
            NSString *file=sender.accessibilityIdentifier;
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"仍然停用",nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { if (![self allowModMutation]) return; NSError *error=nil; [self.modStore setEnabled:NO file:file error:&error]; if (error) showDialog(localize(@"保存失败",nil),error.localizedDescription); [self reloadInstalledMods]; }]];
            [self presentViewController:alert animated:YES completion:nil]; return;
        }
    }
    NSError *error = nil;
    BOOL moved = [self.modStore setEnabled:sender.on file:sender.accessibilityIdentifier error:&error];
    if (!moved) {
        showDialog(localize(@"无法更改模组状态", nil),
                   error.localizedDescription);
    }
    [self reloadInstalledMods];
}

- (void)tableView:(UITableView *)tableView
 didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (tableView.editing) { [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone]; return; }
    if (self.page == PocketJModPageInstalled && !self.loading &&
        indexPath.row < self.installedMods.count) {
        NSDictionary *item = self.installedMods[indexPath.row];
        [self showActionsForMod:item source:[tableView cellForRowAtIndexPath:indexPath]];
        return;
    }
    if (self.page != PocketJModPageBrowse || self.loading ||
        indexPath.row >= self.catalogResults.count) return;
    NSDictionary *item = self.catalogResults[indexPath.row];
    [self showProject:item
           sourceView:[tableView cellForRowAtIndexPath:indexPath]];
}

- (void)checkForUpdates {
    [self checkUpdatesForMods:self.allInstalledMods ?: @[]];
}

- (void)checkUpdatesForMods:(NSArray<NSDictionary *> *)mods {
    if (!mods.count || self.loading) return;
    self.loading = YES; [self.tableView reloadData];
    __block NSUInteger remaining = mods.count, failures = 0;
    NSMutableDictionary *updates = [self.updatesByFile mutableCopy] ?: [NSMutableDictionary dictionary];
    void (^done)(void) = ^{
        if (--remaining) return;
        self.loading = NO; self.updatesByFile = updates;
        [self.tableView reloadData];
        showDialog(localize(@"检查更新", nil), [NSString stringWithFormat:localize(@"发现 %lu 个更新，%lu 个文件无法检查。锁定更新的模组不会被修改。", nil), (unsigned long)updates.count, (unsigned long)failures]);
    };
    for (NSDictionary *mod in mods) {
        if ([mod[@"updateLocked"] boolValue]) { done(); continue; }
        [updates removeObjectForKey:mod[@"fileName"]];
        [self.addonService identifyFile:[self.modsPath stringByAppendingPathComponent:mod[@"fileName"]] record:mod completion:^(NSDictionary *identity, NSError *error) {
            if (!identity || error) { failures++; done(); return; }
            [self.modStore annotateFile:mod[@"fileName"] values:identity error:nil];
            [self.addonService versionsForProvider:identity[@"provider"] project:identity[@"projectID"] minecraft:self.minecraftVersion loader:self.loader compatibleOnly:YES completion:^(NSArray<NSDictionary *> *versions, NSError *error) {
                if (error) failures++;
                else if (versions.count) {
                    NSDictionary *latest = versions.firstObject[@"payload"];
                    NSString *newID = latest[@"pjMetadata"][@"versionID"];
                    NSString *hash = latest[@"hashes"][@"sha1"];
                    BOOL currentListed=NO;
                    for (NSDictionary *version in versions) if ([version[@"payload"][@"pjMetadata"][@"versionID"] isEqual:identity[@"versionID"]]) currentListed=YES;
                    if (currentListed && ![newID isEqual:identity[@"versionID"]] && (!hash.length || ![hash isEqual:mod[@"sha1"]])) {
                        // If current version is newer/incompatible with this instance,
                        // never silently call a downgrade an update.
                        updates[mod[@"fileName"]] = @{@"selectedFile":latest, @"version_number":versions.firstObject[@"title"] ?: newID};
                    }
                }
                done();
            }];
        }];
    }
}

- (void)chooseVersionForInstalledMod:(NSDictionary *)mod reinstall:(BOOL)reinstall {
    if (![self allowModMutation]) return;
    self.loading = YES; [self.tableView reloadData];
    [self.addonService identifyFile:[self.modsPath stringByAppendingPathComponent:mod[@"fileName"]] record:mod completion:^(NSDictionary *identity, NSError *error) {
        if (!identity || error) { self.loading=NO; [self.tableView reloadData]; [self linkProjectForMod:mod error:error]; return; }
        [self.modStore annotateFile:mod[@"fileName"] values:identity error:nil];
        [self.addonService versionsForProvider:identity[@"provider"] project:identity[@"projectID"] minecraft:self.minecraftVersion loader:self.loader compatibleOnly:NO completion:^(NSArray<NSDictionary *> *versions, NSError *error) {
            self.loading=NO; [self.tableView reloadData];
            if (error) { showDialog(localize(@"加载失败", nil), error.localizedDescription); return; }
            if (reinstall) {
                for (NSDictionary *version in versions) if ([version[@"payload"][@"pjMetadata"][@"versionID"] isEqual:identity[@"versionID"]]) {
                    self.versionReplacement=mod; [self installSelectedDescriptor:version[@"payload"] compatible:[version[@"compatible"] boolValue]]; return;
                }
                showDialog(localize(@"无法重新安装", nil), localize(@"原版本已被来源移除，可使用“更改版本”选择其他版本。", nil)); return;
            }
            [self showUnifiedVersionItems:versions title:mod[@"title"] replacing:mod];
        }];
    }];
}

- (void)linkProjectForMod:(NSDictionary *)mod error:(NSError *)error {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:localize(@"关联模组来源", nil) message:error.localizedDescription ?: localize(@"输入 Modrinth 项目 ID/slug 或 CurseForge 数字 ID。", nil) preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *text) { text.placeholder=@"Modrinth ID / CurseForge ID"; text.autocapitalizationType=UITextAutocapitalizationTypeNone; }];
    for (NSString *provider in @[@"Modrinth",@"CurseForge"]) [alert addAction:[UIAlertAction actionWithTitle:provider style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *project=[alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!project.length) return;
        [self.addonService versionsForProvider:provider project:project minecraft:self.minecraftVersion loader:self.loader compatibleOnly:NO completion:^(NSArray *versions, NSError *error) {
            if (error) { showDialog(localize(@"加载失败", nil),error.localizedDescription); return; }
            [self showUnifiedVersionItems:versions title:mod[@"title"] replacing:mod];
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showUnifiedVersionItems:(NSArray<NSDictionary *> *)items title:(NSString *)title replacing:(NSDictionary *)mod {
    if (!items.count) { showDialog(localize(@"没有匹配版本", nil), localize(@"没有找到可下载的文件。", nil)); return; }
    PocketJModVersionPickerViewController *picker=[PocketJModVersionPickerViewController new];
    picker.projectTitle=title; picker.items=items;
    picker.selectionHandler=^(NSDictionary *item) { self.versionReplacement=mod; [self installSelectedDescriptor:item[@"payload"] compatible:[item[@"compatible"] boolValue]]; };
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:picker];
    navigation.modalPresentationStyle=UIModalPresentationPageSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)installSelectedDescriptor:(NSDictionary *)descriptor compatible:(BOOL)compatible {
    if (!compatible) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:localize(@"兼容性警告", nil) message:localize(@"该文件可能无法在当前实例中运行。", nil) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { self.versionReplacement=nil; }]];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"仍然安装", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self installSelectedDescriptor:descriptor compatible:YES]; }]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    if (![self allowModMutation]) return;
    NSDictionary *replacement=self.versionReplacement; self.versionReplacement=nil;
    NSMutableDictionary *root=descriptor.mutableCopy;
    if (replacement) root[@"pjReplacingFile"]=replacement[@"fileName"];
    NSMutableArray *installed=[NSMutableArray array];
    for (NSDictionary *mod in self.allInstalledMods) if (![mod[@"fileName"] isEqual:replacement[@"fileName"]]) [installed addObject:mod];
    self.loading=YES; [self.tableView reloadData];
    [self.addonService dependencyPlanForFile:root installed:installed minecraft:self.minecraftVersion loader:self.loader completion:^(NSArray *plan, NSError *error) {
        self.loading=NO; [self.tableView reloadData];
        if (error) {
            // A failed dependency lookup is never silently treated as a complete
            // plan. Let experienced users explicitly choose root-only instead.
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:localize(@"无法解析依赖",nil) message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消",nil) style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"仅安装所选模组",nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self installFiles:@[root] index:0]; }]];
            [self presentViewController:alert animated:YES completion:nil]; return;
        }
        if (!plan.count) { showDialog(localize(@"安装完成",nil),localize(@"所选模组已安装。",nil)); return; }
        if (plan.count==1) { [self installFiles:plan index:0]; return; }
        PocketJDependencyPreview *preview=[PocketJDependencyPreview new]; preview.files=plan;
        preview.install=^(NSInteger mode) {
            NSMutableArray *selected=[NSMutableArray array];
            for (NSDictionary *file in plan) if (mode==1 || (mode==0 && ![file[@"pjOptional"] boolValue])) [selected addObject:file];
            if (mode==2) selected=[NSMutableArray arrayWithObject:root];
            [self installFiles:selected index:0];
        };
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:preview] animated:YES completion:nil];
    }];
}

- (void)installFiles:(NSArray<NSDictionary *> *)files index:(NSUInteger)index {
    self.pendingInstallFiles=files; self.pendingInstallIndex=index;
    if (index>=files.count) { self.loading=NO; self.downloadTaskID=nil; self.pendingInstallFiles=nil; self.downloadPaused=NO; self.filterButton.menu=[self filterMenu]; self.tableView.tableHeaderView=nil; self.updatesByFile=@{}; [self.modIconCache removeAllObjects]; [self.modsWithoutIcons removeAllObjects]; [self reloadInstalledMods]; showDialog(localize(@"安装完成",nil),localize(@"所选模组已安装。",nil)); return; }
    if ([SurfaceViewController isRunning]) { self.loading=NO; showDialog(localize(@"安装失败",nil),localize(@"请先退出游戏再修改模组。",nil)); [self reloadInstalledMods]; return; }
    self.loading=YES; [self.tableView reloadData];
    NSDictionary *file=files[index];
    [self.addonService resolveDownload:file completion:^(NSDictionary *resolved, NSError *error) {
        if (error) { self.loading=NO; showDialog(localize(@"安装失败",nil),error.localizedDescription); [self reloadInstalledMods]; return; }
        self.downloadProgress=[[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; self.downloadProgress.frame=CGRectMake(0,0,self.tableView.bounds.size.width,4); self.tableView.tableHeaderView=self.downloadProgress;
        self.downloadTaskID=[PocketJDownloadClient.shared download:resolved instanceID:self.modStore.instanceID progress:^(double fraction) { [self.downloadProgress setProgress:fraction animated:YES]; } completion:^(NSURL *location, NSError *error) {
            if (error) { self.loading=NO; self.tableView.tableHeaderView=nil; self.filterButton.menu=[self filterMenu]; showDialog(localize(self.downloadPaused ? @"暂停下载":@"安装失败",nil),self.downloadPaused ? localize(@"下载已暂停，可从菜单继续。",nil):error.localizedDescription); [self reloadInstalledMods]; return; }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
                NSError *failure=nil;
                NSMutableDictionary *metadata=[resolved[@"pjMetadata"] mutableCopy] ?: [NSMutableDictionary dictionary];
                metadata[@"download"]=resolved;
                BOOL installed=![SurfaceViewController isRunning] && [self.modStore installJar:location fileName:resolved[@"filename"] replacingFile:file[@"pjReplacingFile"] metadata:metadata error:&failure];
                if (!installed && !failure) failure=[NSError errorWithDomain:@"PocketJ.ModStore" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"请先退出游戏再修改模组。",nil)}];
                if (installed && [file[@"pjEnableAfterInstall"] boolValue]) { NSString *name=[file[@"pjReplacingFile"] hasSuffix:@".disabled"] ? [resolved[@"filename"] stringByAppendingPathExtension:@"disabled"]:resolved[@"filename"]; [self.modStore setEnabled:YES file:name error:&failure]; }
                [NSFileManager.defaultManager removeItemAtURL:location error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (failure) { self.loading=NO; self.tableView.tableHeaderView=nil; showDialog(localize(@"安装失败",nil),failure.localizedDescription); [self reloadInstalledMods]; }
                    else [self installFiles:files index:index+1];
                });
            });
        }];
        self.filterButton.menu=[self filterMenu];
    }];
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
            self.versionReplacement=installed;
            [self installSelectedDescriptor:update[@"selectedFile"] compatible:YES];
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
    if (self.loading) return;
    self.versionReplacement=nil; self.loading=YES; [self.tableView reloadData];
    [self.addonService versionsForProvider:project[@"source"] ?: @"Modrinth" project:project[@"id"] minecraft:self.minecraftVersion loader:self.loader compatibleOnly:self.compatibleOnly completion:^(NSArray *versions, NSError *error) {
        self.loading=NO; [self.tableView reloadData];
        if (error) { showDialog(localize(@"加载失败", nil),error.localizedDescription); return; }
        [self showUnifiedVersionItems:versions title:project[@"title"] replacing:nil];
    }];
}

- (BOOL)allowModMutation {
    if ([SurfaceViewController isRunning]) {
        showDialog(localize(@"无法修改模组", nil), localize(@"请先退出游戏再修改模组。", nil)); return NO;
    }
    if (self.loading) return NO;
    return YES;
}

- (void)presentModMenu:(UIAlertController *)menu source:(UIView *)source {
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = source ?: self.view;
    menu.popoverPresentationController.sourceRect = source ? source.bounds : CGRectMake(self.view.bounds.size.width / 2, 80, 1, 1);
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)showActionsForMod:(NSDictionary *)mod source:(UIView *)source {
    NSString *details = [NSString stringWithFormat:@"%@\n%@", mod[@"fileName"], mod[@"notes"] ?: @""];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:mod[@"title"] message:details preferredStyle:UIAlertControllerStyleActionSheet];
    void (^add)(NSString *, void (^)(void)) = ^(NSString *title, void (^handler)(void)) {
        [menu addAction:[UIAlertAction actionWithTitle:localize(title, nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { handler(); }]];
    };
    add(@"导出 JAR", ^{ [self exportMods:@[mod] source:source]; });
    add(@"重命名文件", ^{ [self editMod:mod field:@"fileName"]; });
    add(@"显示名称与备注", ^{ [self editMod:mod field:@"notes"]; });
    add([mod[@"updateLocked"] boolValue] ? @"解锁更新" : @"锁定更新", ^{
        NSError *error; [self.modStore annotateFile:mod[@"fileName"] values:@{@"updateLocked":@(![mod[@"updateLocked"] boolValue])} error:&error];
        if (error) showDialog(localize(@"保存失败", nil), error.localizedDescription); [self reloadInstalledMods];
    });
    add(@"检查此模组更新", ^{ [self checkUpdatesForMods:@[mod]]; });
    add(@"更改版本", ^{ [self chooseVersionForInstalledMod:mod reinstall:NO]; });
    add(@"重新安装", ^{ [self chooseVersionForInstalledMod:mod reinstall:YES]; });
    NSDictionary *update = self.updatesByFile[mod[@"fileName"]];
    if (update) add(@"安装更新", ^{ [self presentUpdate:update forInstalledMod:mod]; });
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"删除", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self confirmDeleteMods:@[mod]]; }]];
    [self presentModMenu:menu source:source];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.page != PocketJModPageInstalled || self.loading || indexPath.row >= self.installedMods.count) return nil;
    NSDictionary *mod = self.installedMods[indexPath.row];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:localize(@"删除", nil) handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) { done(YES); [self confirmDeleteMods:@[mod]]; }];
    UIContextualAction *more = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:localize(@"更多", nil) handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) { done(YES); [self showActionsForMod:mod source:[tableView cellForRowAtIndexPath:indexPath]]; }];
    more.backgroundColor = UIColor.systemBlueColor;
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[remove, more]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (void)editMod:(NSDictionary *)mod field:(NSString *)field {
    BOOL rename = [field isEqual:@"fileName"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(rename ? @"重命名文件" : @"显示名称与备注", nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *text) {
        text.text = rename ? mod[@"fileName"] : mod[@"alias"]; text.placeholder = localize(rename ? @"文件名" : @"显示名称", nil);
        text.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    if (!rename) [alert addTextFieldWithConfigurationHandler:^(UITextField *text) { text.text = mod[@"notes"]; text.placeholder = localize(@"备注（仅保存在本机）", nil); }];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"保存", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (rename && ![self allowModMutation]) return;
        NSError *error = nil;
        if (rename) [self.modStore renameFile:mod[@"fileName"] to:alert.textFields.firstObject.text error:&error];
        else [self.modStore annotateFile:mod[@"fileName"] values:@{@"alias":alert.textFields[0].text ?: @"", @"notes":alert.textFields[1].text ?: @""} error:&error];
        if (error) showDialog(localize(@"保存失败", nil), error.localizedDescription);
        [self reloadInstalledMods];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteMods:(NSArray<NSDictionary *> *)mods {
    if (![self allowModMutation] || !mods.count) return;
    NSArray *dependents=[self dependentsOfMods:mods];
    NSString *message=localize(@"将永久删除所选 JAR 文件，不保留备份。依赖它们的其他模组可能无法启动。",nil);
    if (dependents.count) message=[message stringByAppendingFormat:@"\n\n%@",[dependents componentsJoinedByString:@"\n"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"删除模组", nil)
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"删除", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (![self allowModMutation]) return;
        NSError *error = nil; [self.modStore deleteFiles:[mods valueForKey:@"fileName"] error:&error];
        if (error) showDialog(localize(@"删除失败", nil), error.localizedDescription);
        [self setEditing:NO animated:YES]; [self reloadInstalledMods];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSArray<NSDictionary *> *)selectedMods {
    NSMutableArray *mods = [NSMutableArray array];
    for (NSIndexPath *index in self.tableView.indexPathsForSelectedRows) if (index.row < self.installedMods.count) [mods addObject:self.installedMods[index.row]];
    return mods;
}
- (NSArray<NSString *> *)dependentsOfMods:(NSArray<NSDictionary *> *)mods {
    NSMutableSet *IDs=[NSMutableSet set], *files=[NSMutableSet set];
    for (NSDictionary *mod in mods) { if ([mod[@"modID"] length]) [IDs addObject:mod[@"modID"]]; if (mod[@"fileName"]) [files addObject:mod[@"fileName"]]; }
    NSMutableArray *names=[NSMutableArray array];
    for (NSDictionary *mod in self.allInstalledMods) {
        if (![mod[@"enabled"] boolValue] || [files containsObject:mod[@"fileName"]]) continue;
        for (NSString *dependency in mod[@"embeddedRequires"]) if ([IDs containsObject:dependency]) { [names addObject:mod[@"title"] ?: mod[@"fileName"]]; break; }
    }
    return names;
}
- (void)setEditing:(BOOL)editing animated:(BOOL)animated { [super setEditing:editing animated:animated]; if (self.page==PocketJModPageInstalled) [self.tableView reloadData]; }
- (void)showBatchActions {
    NSArray *mods = [self selectedMods];
    if (!mods.count) { [self setEditing:YES animated:YES]; showDialog(localize(@"选择模组", nil), localize(@"选中模组后，再打开“所选模组操作”。", nil)); return; }
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:localize(@"所选模组操作", nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *enabled in @[@YES, @NO]) {
        [menu addAction:[UIAlertAction actionWithTitle:localize(enabled.boolValue ? @"全部启用" : @"全部停用", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (![self allowModMutation]) return;
            NSError *error = nil;
            for (NSDictionary *mod in mods) if (![self.modStore setEnabled:enabled.boolValue file:mod[@"fileName"] error:&error]) break;
            if (error) showDialog(localize(@"无法更改模组状态", nil), error.localizedDescription);
            [self setEditing:NO animated:YES]; [self reloadInstalledMods];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"导出所选模组", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self exportMods:mods source:self.view]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"检查更新", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self setEditing:NO animated:YES]; [self checkUpdatesForMods:mods]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"更新所选模组",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSMutableArray *roots=[NSMutableArray array];
        for (NSDictionary *mod in mods) {
            NSDictionary *update=self.updatesByFile[mod[@"fileName"]];
            if (!update || [mod[@"updateLocked"] boolValue]) continue;
            NSMutableDictionary *file=[update[@"selectedFile"] mutableCopy]; file[@"pjReplacingFile"]=mod[@"fileName"]; [roots addObject:file];
        }
        [self setEditing:NO animated:YES];
        if (!roots.count) { showDialog(localize(@"检查更新",nil),localize(@"请先检查更新，再选择有更新的模组。",nil)); return; }
        if ([self allowModMutation]) [self planBatchRoots:roots index:0 files:[NSMutableArray array]];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:localize(@"删除", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self confirmDeleteMods:mods]; }]];
    [self presentModMenu:menu source:self.view];
}
- (void)planBatchRoots:(NSArray *)roots index:(NSUInteger)index files:(NSMutableArray *)files {
    if (index>=roots.count) {
        self.loading=NO; [self.tableView reloadData];
        PocketJDependencyPreview *preview=[PocketJDependencyPreview new]; preview.files=files;
        preview.install=^(NSInteger mode) {
            NSMutableArray *selected=[NSMutableArray array];
            for (NSDictionary *file in files) if (mode==1 || (mode==0 && ![file[@"pjOptional"] boolValue])) [selected addObject:file];
            [self installFiles:mode==2 ? roots:selected index:0];
        };
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:preview] animated:YES completion:nil]; return;
    }
    self.loading=YES; [self.tableView reloadData];
    NSDictionary *root=roots[index]; NSMutableArray *installed=[NSMutableArray array];
    for (NSDictionary *mod in self.allInstalledMods) if (![mod[@"fileName"] isEqual:root[@"pjReplacingFile"]]) [installed addObject:mod];
    [self.addonService dependencyPlanForFile:root installed:installed minecraft:self.minecraftVersion loader:self.loader completion:^(NSArray *plan,NSError *error) {
        if (error) { self.loading=NO; [self.tableView reloadData]; showDialog(localize(@"无法解析依赖",nil),error.localizedDescription); return; }
        for (NSDictionary *file in plan) {
            NSDictionary *duplicate=nil;
            for (NSDictionary *existing in files) if ([existing[@"pjMetadata"][@"provider"] isEqual:file[@"pjMetadata"][@"provider"]] && [existing[@"pjMetadata"][@"projectID"] isEqual:file[@"pjMetadata"][@"projectID"]]) { duplicate=existing; break; }
            if (duplicate && ![duplicate[@"pjMetadata"][@"versionID"] isEqual:file[@"pjMetadata"][@"versionID"]]) { self.loading=NO; [self.tableView reloadData]; showDialog(localize(@"无法解析依赖",nil),NSLocalizedString(@"Dependencies require conflicting versions of the same project.",nil)); return; }
            if (!duplicate) [files addObject:file];
            else if (![file[@"pjOptional"] boolValue] && [duplicate[@"pjOptional"] boolValue]) { NSMutableDictionary *required=duplicate.mutableCopy; required[@"pjOptional"]=@NO; files[[files indexOfObject:duplicate]]=required; }
        }
        [self planBatchRoots:roots index:index+1 files:files];
    }];
}

- (void)importMods {
    if (![self allowModMutation]) return;
    self.importingSearchIndex=NO;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data", @"com.sun.java-archive"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self; picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)importSearchIndex {
    self.importingSearchIndex=YES;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.comma-separated-values-text",@"public.text"] inMode:UIDocumentPickerModeImport];
    picker.delegate=self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.importingSearchIndex) {
        self.importingSearchIndex=NO; NSURL *url=urls.firstObject; if (!url) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            BOOL access=[url startAccessingSecurityScopedResource]; NSError *error=nil; [PocketJModSearchIndex.shared importCSV:url error:&error]; if (access) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(),^{ showDialog(localize(error ? @"导入失败":@"导入完成",nil),error.localizedDescription ?: localize(@"中文搜索索引已保存，可离线使用。",nil)); });
        }); return;
    }
    if (![self allowModMutation]) return;
    self.loading = YES; [self.tableView reloadData];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *errors = [NSMutableArray array]; NSUInteger imported = 0, skipped = 0;
        NSMutableSet *hashes = [NSMutableSet set];
        for (NSDictionary *record in self.allInstalledMods) if ([record[@"sha1"] length]) [hashes addObject:record[@"sha1"]];
        for (NSURL *url in urls) {
            BOOL scoped = [url startAccessingSecurityScopedResource];
            NSError *error = nil;
            if (![url.pathExtension.lowercaseString isEqual:@"jar"]) error = [NSError errorWithDomain:@"PocketJ.ModStore" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"请选择 JAR 文件。", nil)}];
            NSString *hash = error ? nil : [PocketJModStore sha1AtPath:url.path];
            if (hash && [hashes containsObject:hash]) skipped++;
            else if (!error && ![SurfaceViewController isRunning] && [self.modStore installJar:url fileName:url.lastPathComponent replacingFile:nil metadata:@{} error:&error]) { imported++; if (hash) [hashes addObject:hash]; }
            else if (!error) error = [NSError errorWithDomain:@"PocketJ.ModStore" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"请先退出游戏再修改模组。", nil)}];
            if (error) [errors addObject:[NSString stringWithFormat:@"%@: %@", url.lastPathComponent, error.localizedDescription]];
            if (scoped) [url stopAccessingSecurityScopedResource];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            NSString *summary = [NSString stringWithFormat:localize(@"已导入 %lu 个，跳过重复 %lu 个。", nil), (unsigned long)imported, (unsigned long)skipped];
            if (errors.count) summary = [summary stringByAppendingFormat:@"\n%@", [errors componentsJoinedByString:@"\n"]];
            showDialog(localize(@"导入模组", nil), summary); [self reloadInstalledMods];
        });
    });
}
- (void)exportMods:(NSArray<NSDictionary *> *)mods source:(UIView *)source {
    if (!mods.count) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *error = nil; NSURL *result;
        if (mods.count == 1) {
            NSString *name = mods.firstObject[@"fileName"];
            if ([name hasSuffix:@".disabled"]) name = name.stringByDeletingPathExtension;
            result = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
            NSString *sourcePath = [self.modsPath stringByAppendingPathComponent:mods.firstObject[@"fileName"]];
            if ([[NSFileManager.defaultManager attributesOfItemAtPath:sourcePath error:&error][NSFileType] isEqual:NSFileTypeSymbolicLink]) error = [NSError errorWithDomain:@"PocketJ.ModStore" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"无法导出符号链接。", nil)}];
            if (!error) [NSFileManager.defaultManager copyItemAtPath:sourcePath toPath:result.path error:&error];
        } else {
            result = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"PocketJ-Mods.zip"]];
            UZKArchive *archive = [[UZKArchive alloc] initWithURL:result error:&error];
            NSMutableArray *manifest = [NSMutableArray array];
            for (NSDictionary *mod in mods) {
                NSString *name = mod[@"fileName"];
                NSString *path = [self.modsPath stringByAppendingPathComponent:name];
                if (![[NSFileManager.defaultManager attributesOfItemAtPath:path error:&error][NSFileType] isEqual:NSFileTypeRegular]) break;
                NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
                if (!data || ![archive writeData:data filePath:name error:&error]) break;
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                for (NSString *key in @[@"fileName", @"alias", @"notes", @"enabled", @"provider", @"projectID", @"versionID", @"sha1"]) if (mod[key]) entry[key] = mod[key];
                [manifest addObject:entry];
            }
            if (!error) [archive writeData:[NSJSONSerialization dataWithJSONObject:@{@"formatVersion":@1, @"mods":manifest} options:NSJSONWritingPrettyPrinted error:&error] filePath:@"pocketj-mods.json" error:&error];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !result) { [NSFileManager.defaultManager removeItemAtPath:directory error:nil]; showDialog(localize(@"导出失败", nil), error.localizedDescription); return; }
            UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[result] applicationActivities:nil];
            activity.popoverPresentationController.sourceView = source ?: self.view;
            activity.popoverPresentationController.sourceRect = source ? source.bounds : self.view.bounds;
            activity.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) { [NSFileManager.defaultManager removeItemAtPath:directory error:nil]; };
            [self presentViewController:activity animated:YES completion:nil];
        });
    });
}


@end
