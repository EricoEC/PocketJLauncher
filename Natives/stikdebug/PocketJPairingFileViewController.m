#import "PocketJPairingFileViewController.h"
#import "PocketJPairingViewController.h"
#import "PocketJPairingHost.h"
#import "StikDebugEngine.h"
#import "../ModernUITheme.h"
#import "../utils.h"
#import "../ios_uikit_bridge.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation PocketJPairingFileViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = localize(@"配对文件", nil);
    [ModernUITheme styleController:self]; [ModernUITheme styleTableView:self.tableView];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [StikDebugEngine.sharedEngine synchronizePairingFileFromDocuments:nil];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : 3; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return localize(section == 0 ? @"获取配对文件" : @"文件管理", nil);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? localize(@"本机配对需 iOS 27 或更高版本；电脑配对方式仍可使用。", nil) : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    BOOL destructive = path.section == 1 && path.row == 2;
    [ModernUITheme styleCell:cell destructive:destructive];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NSArray *titles = path.section == 0 ? @[@"本机配对", @"从电脑导入"] : @[@"导入已有文件", @"导出配对文件", @"删除配对文件"];
    NSArray *icons = path.section == 0 ? @[@"iphone.radiowaves.left.and.right", @"desktopcomputer"] : @[@"square.and.arrow.down", @"square.and.arrow.up", @"trash"];
    cell.textLabel.text = localize(titles[path.row], nil);
    cell.imageView.image = [UIImage systemImageNamed:icons[path.row]];
    if (path.section == 0 && path.row == 0) cell.detailTextLabel.text = localize(@"免电脑，在本机完成", nil);
    if (destructive) cell.accessoryType = UITableViewCellAccessoryNone;
    if (path.section == 1 && path.row > 0 && !StikDebugEngine.sharedEngine.hasPairingFile) {
        cell.userInteractionEnabled = NO; cell.textLabel.enabled = NO;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && path.row == 0) {
        [self.navigationController pushViewController:[PocketJPairingViewController new] animated:YES];
    } else if (path.section == 0) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/EricoEC/PocketJLauncher/releases#release-pairing-tool-v1.0"] options:@{} completionHandler:nil];
    } else if (path.row == 0) {
        NSMutableArray *types = [NSMutableArray arrayWithObject:UTTypePropertyList];
        UTType *pairing = [UTType typeWithFilenameExtension:@"mobiledevicepairing" conformingToType:UTTypeData];
        if (pairing) [types addObject:pairing];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        picker.delegate = self; picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (path.row == 1) {
        NSError *error = nil; NSURL *URL = [StikDebugEngine.sharedEngine exportablePairingFileURL:&error];
        if (!URL) { showDialog(localize(@"导出失败", nil), error.localizedDescription); return; }
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[URL] applicationActivities:nil];
        share.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:path];
        [self presentViewController:share animated:YES completion:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"删除配对文件", nil)
            message:localize(@"从 PocketJ Launcher 中移除本机配对凭据", nil) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"删除", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            NSError *error = nil;
            if (![StikDebugEngine.sharedEngine deletePairingFile:&error]) showDialog(localize(@"删除失败", nil), error.localizedDescription);
            [weakSelf.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)URLs {
    if (!URLs.count) return;
    NSError *error = nil;
    if (![StikDebugEngine.sharedEngine importPairingFileAtURL:URLs.firstObject error:&error]) {
        showDialog(localize(@"导入失败", nil), error.localizedDescription);
    }
    [self.tableView reloadData];
}
@end
