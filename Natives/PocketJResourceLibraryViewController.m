#import "PocketJResourceLibraryViewController.h"
#import "ModernUITheme.h"
#import "utils.h"
#import "ios_uikit_bridge.h"
#import "PocketJAddonService.h"
#import "PocketJAddonVersionPicker.h"
#import "PocketJInstanceContext.h"
#import "PocketJDownloadClient.h"
#import "PocketJArchiveService.h"
#import "PocketJModStore.h"
#import "SurfaceViewController.h"
#if __has_include("CurseForgeSecrets.local.h")
#import "CurseForgeSecrets.local.h"
#else
#import "CurseForgeSecrets.sample.h"
#endif

static NSArray<NSDictionary *> *PocketJResourceKinds(void) {
    return @[
        @{@"title": localize(@"光影包", nil), @"folder": @"shaderpacks", @"type": @"shader", @"icon": @"sun.max.fill"},
        @{@"title": localize(@"材质包", nil), @"folder": @"resourcepacks", @"type": @"resourcepack", @"icon": @"paintpalette.fill"},
        @{@"title": localize(@"数据包", nil), @"folder": @"datapacks", @"type": @"datapack", @"icon": @"externaldrive.fill"},
        @{@"title": localize(@"世界存档", nil), @"folder": @"saves", @"type": @"world", @"icon": @"globe.europe.africa.fill"},
    ];
}

@interface PocketJOnlineResourceViewController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic) NSDictionary *kind;
@property(nonatomic) NSString *destination;
@property(nonatomic) NSString *gameVersion;
@property(nonatomic) NSArray<NSDictionary *> *results;
@property(nonatomic) NSInteger provider;
@property(nonatomic) NSCache<NSString *, UIImage *> *iconCache;
@property(nonatomic) PocketJAddonService *addonService;
@property(nonatomic) NSString *instanceID;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL installing;
@end

@interface PocketJResourceLibraryViewController () <UIDocumentPickerDelegate>
@property(nonatomic) NSString *instanceName;
@property(nonatomic) NSString *instancePath;
@property(nonatomic) NSInteger selectedKind;
@property(nonatomic) NSArray<NSString *> *files;
@property(nonatomic) NSString *selectedWorld;
@end

@implementation PocketJResourceLibraryViewController

- (instancetype)initWithInstanceName:(NSString *)instanceName instancePath:(NSString *)instancePath {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { _instanceName = instanceName; _instancePath = instancePath; }
    return self;
}
- (NSDictionary *)kind { return PocketJResourceKinds()[self.selectedKind]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadFiles]; }
- (NSString *)folder {
    NSString *folder;
    if ([self.kind[@"type"] isEqualToString:@"datapack"]) {
        if (!self.selectedWorld.length) return @"";
        folder = [[[self.instancePath stringByAppendingPathComponent:@"saves"]
            stringByAppendingPathComponent:self.selectedWorld] stringByAppendingPathComponent:@"datapacks"];
    } else {
        folder = [self.instancePath stringByAppendingPathComponent:self.kind[@"folder"]];
    }
    if (!folder.length) return @"";
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return folder;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"资源管理", nil);
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(importFile)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"icloud.and.arrow.down"] style:UIBarButtonItemStylePlain target:self action:@selector(browseOnline)]
    ];
    [self reloadFiles];
}
- (void)reloadFiles {
    if ([self.kind[@"type"] isEqualToString:@"datapack"] && !self.selectedWorld.length) {
        self.files = @[]; [self.tableView reloadData]; return;
    }
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.folder error:nil] ?: @[];
    self.files = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        NSString *path=[self.folder stringByAppendingPathComponent:name];
        if ([[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeSymbolicLink]) return NO;
        if ([self.kind[@"type"] isEqual:@"world"]) return [NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingPathComponent:@"level.dat"]];
        return ![name hasPrefix:@"."];
    }]];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section ? self.files.count : PocketJResourceKinds().count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section ? self.kind[@"title"] : localize(@"资源类型", nil); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.section == 0) {
        NSDictionary *kind = PocketJResourceKinds()[indexPath.row];
        cell.textLabel.text = kind[@"title"];
        cell.imageView.image = [UIImage systemImageNamed:kind[@"icon"]];
        cell.accessoryType = indexPath.row == self.selectedKind ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        NSString *file = self.files[indexPath.row];
        BOOL disabled = [file hasSuffix:@".disabled"];
        cell.textLabel.text = disabled ? [file substringToIndex:file.length - @".disabled".length] : file;
        cell.detailTextLabel.text = disabled ? localize(@"已停用", nil) : localize(@"已启用", nil);
        cell.imageView.image = [UIImage systemImageNamed:disabled ? @"archivebox" : @"archivebox.fill"];
        UISwitch *toggle = [UISwitch new]; toggle.on = !disabled; toggle.tag = indexPath.row;
        [toggle addTarget:self action:@selector(toggleFile:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        if ([self.kind[@"type"] isEqual:@"world"]) { cell.accessoryView=nil; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.detailTextLabel.text=localize(@"点击导出世界存档",nil); }
    }
    [ModernUITheme styleCell:cell destructive:NO];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        self.selectedKind = indexPath.row;
        if ([self.kind[@"type"] isEqualToString:@"datapack"]) [self chooseWorldFromCell:[tableView cellForRowAtIndexPath:indexPath]];
        else [self reloadFiles];
    } else if ([self.kind[@"type"] isEqual:@"world"]) {
        [self exportResource:self.files[indexPath.row] source:[tableView cellForRowAtIndexPath:indexPath]];
    }
}
- (void)chooseWorldFromCell:(UITableViewCell *)cell {
    NSString *saves = [self.instancePath stringByAppendingPathComponent:@"saves"];
    NSArray *worlds = [NSFileManager.defaultManager contentsOfDirectoryAtPath:saves error:nil] ?: @[];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:localize(@"选择世界", nil)
        message:worlds.count ? nil : localize(@"请先在 Minecraft 中创建世界。", nil)
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *world in worlds) {
        [sheet addAction:[UIAlertAction actionWithTitle:world style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            self.selectedWorld = world; [self reloadFiles];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell; sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 1; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    [self confirmDeleteResource:self.files[indexPath.row]];
}
- (void)confirmDeleteResource:(NSString *)name {
    if ([SurfaceViewController isRunning]) { showDialog(localize(@"无法修改资源",nil),localize(@"请先退出游戏再修改资源。",nil)); return; }
    NSString *path=[self.folder stringByAppendingPathComponent:name];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:localize(@"永久删除？",nil) message:name preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消",nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"删除",nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if ([SurfaceViewController isRunning]) return;
        NSError *error=nil; [NSFileManager.defaultManager removeItemAtPath:path error:&error];
        if (error) showDialog(localize(@"删除失败",nil),error.localizedDescription); [self reloadFiles];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)index {
    if (index.section!=1 || index.row>=self.files.count) return nil;
    NSString *name=self.files[index.row];
    UIContextualAction *remove=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:localize(@"删除",nil) handler:^(UIContextualAction *action,UIView *view,void (^done)(BOOL)) { done(YES); [self confirmDeleteResource:name]; }];
    UIContextualAction *export=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:localize(@"导出",nil) handler:^(UIContextualAction *action,UIView *view,void (^done)(BOOL)) { done(YES); [self exportResource:name source:[table cellForRowAtIndexPath:index]]; }];
    UISwipeActionsConfiguration *config=[UISwipeActionsConfiguration configurationWithActions:@[remove,export]]; config.performsFirstActionWithFullSwipe=NO; return config;
}
- (void)exportResource:(NSString *)name source:(UIView *)source {
    NSString *path=[self.folder stringByAppendingPathComponent:name]; BOOL world=[self.kind[@"type"] isEqual:@"world"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil; NSURL *url=world ? [PocketJArchiveService exportWorld:path error:&error]:[NSURL fileURLWithPath:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !url) { showDialog(localize(@"导出失败",nil),error.localizedDescription); return; }
            UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
            share.popoverPresentationController.sourceView=source ?: self.view; share.popoverPresentationController.sourceRect=source ? source.bounds:self.view.bounds;
            if (world) share.completionWithItemsHandler=^(UIActivityType type,BOOL done,NSArray *items,NSError *error) { [NSFileManager.defaultManager removeItemAtPath:url.path.stringByDeletingLastPathComponent error:nil]; };
            [self presentViewController:share animated:YES completion:nil];
        });
    });
}
- (void)toggleFile:(UISwitch *)toggle {
    if ([SurfaceViewController isRunning]) { toggle.on=!toggle.on; showDialog(localize(@"无法修改资源",nil),localize(@"请先退出游戏再修改资源。",nil)); return; }
    if (toggle.tag >= self.files.count) return;
    NSString *old = self.files[toggle.tag];
    BOOL disabled = [old hasSuffix:@".disabled"];
    NSString *new = disabled ? [old substringToIndex:old.length - @".disabled".length] : [old stringByAppendingString:@".disabled"];
    [NSFileManager.defaultManager moveItemAtPath:[self.folder stringByAppendingPathComponent:old]
        toPath:[self.folder stringByAppendingPathComponent:new] error:nil];
    [self reloadFiles];
}
- (void)importFile {
    if ([SurfaceViewController isRunning]) { showDialog(localize(@"无法修改资源",nil),localize(@"请先退出游戏再修改资源。",nil)); return; }
    if ([self.kind[@"type"] isEqualToString:@"datapack"] && !self.selectedWorld.length) {
        [self chooseWorldFromCell:[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.selectedKind inSection:0]]]; return;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive", @"public.data"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self; picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if ([SurfaceViewController isRunning]) return;
    NSString *folder=self.folder; BOOL world=[self.kind[@"type"] isEqual:@"world"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSMutableArray *errors=[NSMutableArray array];
        for (NSURL *url in urls) {
            BOOL scoped=[url startAccessingSecurityScopedResource]; NSError *error=nil;
            if (world) [PocketJArchiveService installWorld:url saves:folder name:url.lastPathComponent.stringByDeletingPathExtension error:&error];
            else if ([PocketJArchiveService validateArchive:url.path error:&error]) {
                // Import never removes an existing resource on name collision.
                [NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:url.lastPathComponent]] error:&error];
            }
            if (scoped) [url stopAccessingSecurityScopedResource];
            if (error) [errors addObject:[NSString stringWithFormat:@"%@: %@",url.lastPathComponent,error.localizedDescription]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (errors.count) showDialog(localize(@"导入失败",nil),[errors componentsJoinedByString:@"\n"]); [self reloadFiles]; });
    });
}
- (void)browseOnline {
    if ([self.kind[@"type"] isEqualToString:@"datapack"] && !self.selectedWorld.length) {
        [self chooseWorldFromCell:[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.selectedKind inSection:0]]]; return;
    }
    PocketJOnlineResourceViewController *online = [PocketJOnlineResourceViewController new];
    online.kind = self.kind; online.destination = self.folder;
    online.gameVersion = [[PocketJInstanceContext alloc] initWithInstancePath:self.instancePath].minecraftVersion;
    online.instanceID = [[PocketJModStore alloc] initWithInstancePath:self.instancePath].instanceID;
    [self.navigationController pushViewController:online animated:YES];
}
@end

@implementation PocketJOnlineResourceViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = [NSString stringWithFormat:localize(@"在线%@", nil), self.kind[@"title"]];
    self.iconCache = [NSCache new];
    self.addonService=[[PocketJAddonService alloc] initWithCurseForgeKey:POCKETJ_CURSEFORGE_API_KEY];
    [ModernUITheme styleController:self]; [ModernUITheme styleTableView:self.tableView];
    UISearchController *search = [UISearchController new]; search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO; self.navigationItem.searchController = search;
    UISegmentedControl *provider = [[UISegmentedControl alloc] initWithItems:@[@"Modrinth", @"CurseForge"]];
    provider.selectedSegmentIndex = 0; [provider addTarget:self action:@selector(providerChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = provider;
    if ([self.kind[@"type"] isEqual:@"world"]) { self.provider=1; provider.selectedSegmentIndex=1; [provider setEnabled:NO forSegmentAtIndex:0]; }
    [self search:@""];
}
- (void)providerChanged:(UISegmentedControl *)sender { self.provider = sender.selectedSegmentIndex; [self search:self.navigationItem.searchController.searchBar.text ?: @""]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self search:searchController.searchBar.text ?: @""]; }
- (void)search:(NSString *)query {
    if (self.provider == 1) { [self searchCurseForge:query]; return; }
    NSString *facets = [NSString stringWithFormat:@"[[\"project_type:%@\"]]", self.kind[@"type"]];
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://api.modrinth.com/v2/search"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"query" value:query], [NSURLQueryItem queryItemWithName:@"facets" value:facets], [NSURLQueryItem queryItemWithName:@"limit" value:@"30"]];
    [[[NSURLSession sharedSession] dataTaskWithURL:components.URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ self.results = json[@"hits"] ?: @[]; [self.tableView reloadData]; });
    }] resume];
}
- (void)searchCurseForge:(NSString *)query {
    if (POCKETJ_CURSEFORGE_API_KEY.length == 0) {
        self.results = @[]; [self.tableView reloadData]; return;
    }
    NSDictionary *classIDs = @{@"shader": @6552, @"resourcepack": @12, @"datapack": @6945, @"world":@17};
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://api.curseforge.com/v1/mods/search"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"gameId" value:@"432"],
        [NSURLQueryItem queryItemWithName:@"classId" value:[classIDs[self.kind[@"type"]] stringValue]],
        [NSURLQueryItem queryItemWithName:@"searchFilter" value:query],
        [NSURLQueryItem queryItemWithName:@"pageSize" value:@"30"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:POCKETJ_CURSEFORGE_API_KEY forHTTPHeaderField:@"x-api-key"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *item in json[@"data"] ?: @[]) {
            NSString *icon = item[@"logo"][@"thumbnailUrl"] ?: @"";
            [mapped addObject:@{@"title": item[@"name"] ?: @"", @"description": item[@"summary"] ?: @"",
                @"project_id": [item[@"id"] stringValue] ?: @"", @"curseforge": @YES, @"icon_url": icon}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ self.results = mapped; [self.tableView reloadData]; });
    }] resume];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.results.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.results[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = item[@"title"] ?: item[@"slug"];
    cell.detailTextLabel.text = item[@"description"];
    cell.detailTextLabel.numberOfLines = 2; cell.imageView.image = [UIImage systemImageNamed:self.kind[@"icon"]];
    NSString *iconURL = item[@"icon_url"];
    if (iconURL.length) [self loadIcon:iconURL forCell:cell expectedTitle:cell.textLabel.text];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; [ModernUITheme styleCell:cell destructive:NO]; return cell;
}
- (void)loadIcon:(NSString *)urlString forCell:(UITableViewCell *)cell expectedTitle:(NSString *)title {
    UIImage *cached = [self.iconCache objectForKey:urlString];
    if (cached) { cell.imageView.image = cached; return; }
    NSURL *url = [NSURL URLWithString:urlString]; if (!url) return;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil; if (!image) return;
        [self.iconCache setObject:image forKey:urlString];
        dispatch_async(dispatch_get_main_queue(), ^{ if ([cell.textLabel.text isEqualToString:title]) { cell.imageView.image = image; [cell setNeedsLayout]; } });
    }] resume];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.installing || indexPath.row>=self.results.count) return;
    NSDictionary *item=self.results[indexPath.row];
    NSString *provider=[item[@"curseforge"] boolValue] ? @"CurseForge":@"Modrinth";
    [self.addonService versionsForProvider:provider project:item[@"project_id"] minecraft:self.gameVersion loader:@"" compatibleOnly:NO completion:^(NSArray *versions,NSError *error) {
        if (error || !versions.count) { showDialog(localize(@"加载失败",nil),error.localizedDescription ?: localize(@"没有找到可下载的文件。",nil)); return; }
        PocketJModVersionPickerViewController *picker=[PocketJModVersionPickerViewController new]; picker.projectTitle=item[@"title"]; picker.items=versions;
        picker.selectionHandler=^(NSDictionary *version) {
            NSDictionary *file=version[@"payload"];
            if ([version[@"compatible"] boolValue]) [self installResource:file];
            else {
                UIAlertController *warning=[UIAlertController alertControllerWithTitle:localize(@"兼容性警告",nil) message:localize(@"该文件可能无法在当前实例中运行。",nil) preferredStyle:UIAlertControllerStyleAlert];
                [warning addAction:[UIAlertAction actionWithTitle:localize(@"取消",nil) style:UIAlertActionStyleCancel handler:nil]];
                [warning addAction:[UIAlertAction actionWithTitle:localize(@"仍然安装",nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self installResource:file]; }]];
                [self presentViewController:warning animated:YES completion:nil];
            }
        };
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
    }];
}
- (void)installResource:(NSDictionary *)file {
    if (self.installing || [SurfaceViewController isRunning]) return;
    self.installing=YES; self.tableView.userInteractionEnabled=NO;
    [self.addonService resolveDownload:file completion:^(NSDictionary *descriptor,NSError *error) {
        if (error) { self.installing=NO; self.tableView.userInteractionEnabled=YES; showDialog(localize(@"下载失败",nil),error.localizedDescription); return; }
        [PocketJDownloadClient.shared download:descriptor instanceID:self.instanceID ?: self.destination progress:nil completion:^(NSURL *location,NSError *error) {
            if (error) { self.installing=NO; self.tableView.userInteractionEnabled=YES; showDialog(localize(@"下载失败",nil),error.localizedDescription); return; }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
                NSError *failure=nil; NSString *name=descriptor[@"filename"];
                if ([SurfaceViewController isRunning]) failure=[NSError errorWithDomain:@"PocketJ.Resource" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"请先退出游戏再修改资源。",nil)}];
                else if ([self.kind[@"type"] isEqual:@"world"]) [PocketJArchiveService installWorld:location saves:self.destination name:name.stringByDeletingPathExtension error:&failure];
                else if (![PocketJModStore isSafeFileName:name]) failure=[NSError errorWithDomain:@"PocketJ.Resource" code:1 userInfo:@{NSLocalizedDescriptionKey:localize(@"无效的文件名。",nil)}];
                else if ([PocketJArchiveService validateArchive:location.path error:&failure]) {
                    NSURL *target=[NSURL fileURLWithPath:[self.destination stringByAppendingPathComponent:name]];
                    if ([NSFileManager.defaultManager fileExistsAtPath:target.path]) [NSFileManager.defaultManager replaceItemAtURL:target withItemAtURL:location backupItemName:nil options:0 resultingItemURL:nil error:&failure];
                    else [NSFileManager.defaultManager moveItemAtURL:location toURL:target error:&failure];
                }
                [NSFileManager.defaultManager removeItemAtURL:location error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{ self.installing=NO; self.tableView.userInteractionEnabled=YES; showDialog(localize(failure ? @"下载失败":@"下载完成",nil),failure.localizedDescription ?: name); });
            });
        }];
    }];
}
@end
