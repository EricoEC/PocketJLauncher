#import "PocketJResourceLibraryViewController.h"
#import "ModernUITheme.h"
#import "utils.h"
#import "ios_uikit_bridge.h"
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
    ];
}

@interface PocketJOnlineResourceViewController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic) NSDictionary *kind;
@property(nonatomic) NSString *destination;
@property(nonatomic) NSString *gameVersion;
@property(nonatomic) NSArray<NSDictionary *> *results;
@property(nonatomic) NSInteger provider;
@property(nonatomic) NSCache<NSString *, UIImage *> *iconCache;
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
    [NSFileManager.defaultManager removeItemAtPath:[self.folder stringByAppendingPathComponent:self.files[indexPath.row]] error:nil];
    [self reloadFiles];
}
- (void)toggleFile:(UISwitch *)toggle {
    if (toggle.tag >= self.files.count) return;
    NSString *old = self.files[toggle.tag];
    BOOL disabled = [old hasSuffix:@".disabled"];
    NSString *new = disabled ? [old substringToIndex:old.length - @".disabled".length] : [old stringByAppendingString:@".disabled"];
    [NSFileManager.defaultManager moveItemAtPath:[self.folder stringByAppendingPathComponent:old]
        toPath:[self.folder stringByAppendingPathComponent:new] error:nil];
    [self reloadFiles];
}
- (void)importFile {
    if ([self.kind[@"type"] isEqualToString:@"datapack"] && !self.selectedWorld.length) {
        [self chooseWorldFromCell:[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.selectedKind inSection:0]]]; return;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive", @"public.data"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self; picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        NSString *target = [self.folder stringByAppendingPathComponent:url.lastPathComponent];
        [NSFileManager.defaultManager removeItemAtPath:target error:nil];
        [NSFileManager.defaultManager copyItemAtURL:url toURL:[NSURL fileURLWithPath:target] error:nil];
    }
    [self reloadFiles];
}
- (void)browseOnline {
    if ([self.kind[@"type"] isEqualToString:@"datapack"] && !self.selectedWorld.length) {
        [self chooseWorldFromCell:[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.selectedKind inSection:0]]]; return;
    }
    PocketJOnlineResourceViewController *online = [PocketJOnlineResourceViewController new];
    online.kind = self.kind; online.destination = self.folder;
    NSDictionary *profile = [NSDictionary dictionaryWithContentsOfFile:[self.instancePath stringByAppendingPathComponent:@"launcher_profiles.plist"]];
    online.gameVersion = profile[@"lastVersionId"] ?: @"";
    [self.navigationController pushViewController:online animated:YES];
}
@end

@implementation PocketJOnlineResourceViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = [NSString stringWithFormat:localize(@"在线%@", nil), self.kind[@"title"]];
    self.iconCache = [NSCache new];
    [ModernUITheme styleController:self]; [ModernUITheme styleTableView:self.tableView];
    UISearchController *search = [UISearchController new]; search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO; self.navigationItem.searchController = search;
    UISegmentedControl *provider = [[UISegmentedControl alloc] initWithItems:@[@"Modrinth", @"CurseForge"]];
    provider.selectedSegmentIndex = 0; [provider addTarget:self action:@selector(providerChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = provider;
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
    NSDictionary *classIDs = @{@"shader": @6552, @"resourcepack": @12, @"datapack": @6945};
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
    NSDictionary *project = self.results[indexPath.row]; NSString *projectID = project[@"project_id"];
    if ([project[@"curseforge"] boolValue]) { [self downloadCurseForgeProject:projectID]; return; }
    NSString *urlString = [NSString stringWithFormat:@"https://api.modrinth.com/v2/project/%@/version", projectID];
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    if (self.gameVersion.length) components.queryItems = @[[NSURLQueryItem queryItemWithName:@"game_versions" value:[NSString stringWithFormat:@"[\"%@\"]", self.gameVersion]]];
    [[[NSURLSession sharedSession] dataTaskWithURL:components.URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSArray *versions = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *version = [versions isKindOfClass:NSArray.class] ? versions.firstObject : nil;
        NSDictionary *file = [version[@"files"] firstObject]; NSURL *url = [NSURL URLWithString:file[@"url"]];
        if (!url) return;
        [[[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            if (error || !location) return;
            NSString *name = file[@"filename"] ?: response.suggestedFilename ?: @"download.zip";
            NSString *target = [self.destination stringByAppendingPathComponent:name];
            [NSFileManager.defaultManager removeItemAtPath:target error:nil];
            [NSFileManager.defaultManager moveItemAtPath:location.path toPath:target error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ showDialog(localize(@"下载完成", nil), name); });
        }] resume];
    }] resume];
}
- (void)downloadCurseForgeProject:(NSString *)projectID {
    NSURLComponents *components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"https://api.curseforge.com/v1/mods/%@/files", projectID]];
    NSMutableArray *items = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"pageSize" value:@"50"]];
    if (self.gameVersion.length) [items addObject:[NSURLQueryItem queryItemWithName:@"gameVersion" value:self.gameVersion]];
    components.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:POCKETJ_CURSEFORGE_API_KEY forHTTPHeaderField:@"x-api-key"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *file = [json[@"data"] firstObject]; NSString *download = file[@"downloadUrl"];
        if (!download.length) return; NSURL *url = [NSURL URLWithString:download];
        [[[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            if (error || !location) return; NSString *name = file[@"fileName"] ?: response.suggestedFilename ?: @"download.zip";
            NSString *target = [self.destination stringByAppendingPathComponent:name];
            [NSFileManager.defaultManager removeItemAtPath:target error:nil];
            [NSFileManager.defaultManager moveItemAtPath:location.path toPath:target error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ showDialog(localize(@"下载完成", nil), name); });
        }] resume];
    }] resume];
}
@end
