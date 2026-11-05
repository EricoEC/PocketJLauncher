#import "PocketJPairingViewController.h"
#import "PocketJPairingHost.h"
#import "StikDebugEngine.h"
#import "StikDebugViewController.h"
#import "../ModernUITheme.h"
#import "../utils.h"

@implementation PocketJPairingViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"本机配对", nil);
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pairingChanged:)
        name:PocketJPairingHostDidChangeNotification object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) {
        [PocketJPairingHost.sharedHost cancel];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updatePairingPresentation];
}
- (void)updatePairingPresentation {
    self.navigationItem.rightBarButtonItem = PocketJPairingHost.sharedHost.state == PocketJPairingStateSucceeded
        ? [[UIBarButtonItem alloc] initWithTitle:localize(@"重新配对", nil) style:UIBarButtonItemStylePlain
            target:self action:@selector(startPairing)] : nil;
    [self.tableView reloadData];
}
- (void)pairingChanged:(NSNotification *)note { if (self.isViewLoaded) [self updatePairingPresentation]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return PocketJPairingHost.sharedHost.state == PocketJPairingStateSucceeded ? 3 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return PocketJPairingHost.sharedHost.state == PocketJPairingStateSucceeded ? 1 : 3; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (PocketJPairingHost.sharedHost.state == PocketJPairingStateSucceeded) return section == 2 ? localize(@"下一步：连接 LocalDevVPN，再开启 JIT。", nil) : nil;
    return localize(@"需要 iOS 27 或更高版本。允许本地网络访问，开启 Wi-Fi 和开发者模式。启动后前往系统设置 → 隐私与安全性 → 开发者模式，选择“与 PocketJ Launcher 配对”，输入通知或此页面显示的配对码。未允许通知时，返回此页查看配对码。三分钟内完成；成功后仍需 LocalDevVPN 才能开启 JIT。电脑生成和导入方式仍可使用。", nil);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    [ModernUITheme styleCell:cell destructive:NO];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    PocketJPairingHost *host = PocketJPairingHost.sharedHost;
    if (host.state == PocketJPairingStateSucceeded) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (path.section == 0) {
            cell.backgroundColor = UIColor.clearColor;
            UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
            icon.tintColor = ModernUITheme.accentColor; icon.contentMode = UIViewContentModeScaleAspectFit;
            UILabel *title = [UILabel new]; title.text = localize(@"配对成功", nil);
            title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
            title.adjustsFontForContentSizeCategory = YES; title.textAlignment = NSTextAlignmentCenter; title.numberOfLines = 0;
            UILabel *detail = [UILabel new]; detail.text = localize(@"配对文件已保存，可以返回继续", nil);
            detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
            detail.adjustsFontForContentSizeCategory = YES; detail.textColor = UIColor.secondaryLabelColor;
            detail.textAlignment = NSTextAlignmentCenter; detail.numberOfLines = 0;
            UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, detail]];
            stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12; stack.alignment = UIStackViewAlignmentCenter;
            stack.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:stack];
            [NSLayoutConstraint activateConstraints:@[
                [icon.widthAnchor constraintEqualToConstant:52], [icon.heightAnchor constraintEqualToConstant:52],
                [title.widthAnchor constraintEqualToAnchor:stack.widthAnchor], [detail.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
                [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:24],
                [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-24]]];
        } else if (path.section == 1) {
            cell.textLabel.text = localize(@"配对文件", nil);
            cell.detailTextLabel.text = localize(@"已就绪", nil);
            cell.detailTextLabel.textColor = ModernUITheme.accentColor;
        } else {
            cell.backgroundColor = UIColor.clearColor;
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            NSString *title = localize(@"返回 JIT 设置", nil);
            if (@available(iOS 15.0, *)) button.configuration = [ModernUITheme primaryButtonConfigurationWithTitle:title image:nil];
            else {
                [button setTitle:title forState:UIControlStateNormal];
                button.backgroundColor = ModernUITheme.accentColor;
                [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
                [ModernUITheme styleContinuousButton:button cornerRadius:18];
            }
            [button addTarget:self action:@selector(returnToJIT) forControlEvents:UIControlEventTouchUpInside];
            button.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:button];
            [NSLayoutConstraint activateConstraints:@[
                [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [button.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
                [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
                [button.heightAnchor constraintGreaterThanOrEqualToConstant:56]]];
        }
        return cell;
    }
    if (path.row == 0) {
        cell.textLabel.text = localize(@"配对状态", nil);
        cell.detailTextLabel.text = host.status.length ? host.status : localize(@"准备好后点击“开始本机配对”。", nil);
        cell.detailTextLabel.textColor = host.state == PocketJPairingStateFailed ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.row == 1) {
        cell.textLabel.text = host.PIN ?: localize(@"等待配对码", nil);
        cell.textLabel.font = [UIFont monospacedDigitSystemFontOfSize:28 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = localize(@"点击复制配对码", nil);
        cell.selectionStyle = host.PIN ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = host.running ? localize(@"取消本机配对", nil) : localize(@"开始本机配对", nil);
        cell.textLabel.textColor = host.running ? UIColor.systemRedColor : UIColor.systemBlueColor;
        if (!PocketJPairingHost.isSupported) {
            cell.detailTextLabel.text = localize(@"当前系统请使用电脑生成并导入配对文件。", nil);
            cell.textLabel.textColor = UIColor.secondaryLabelColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    PocketJPairingHost *host = PocketJPairingHost.sharedHost;
    if (host.state == PocketJPairingStateSucceeded) {
        if (path.section == 2) [self returnToJIT];
        return;
    }
    if (path.row == 1 && host.PIN) {
        [UIPasteboard.generalPasteboard setItems:@[@{@"public.utf8-plain-text": host.PIN}]
            options:@{UIPasteboardOptionLocalOnly: @YES,
                      UIPasteboardOptionExpirationDate: [NSDate dateWithTimeIntervalSinceNow:180]}];
        return;
    }
    if (path.row != 2 || !PocketJPairingHost.isSupported) return;
    if (host.running) { [host cancel]; return; }
    [self startPairing];
}
- (void)returnToJIT {
    for (UIViewController *controller in self.navigationController.viewControllers) {
        if ([controller isKindOfClass:StikDebugViewController.class]) {
            [self.navigationController popToViewController:controller animated:YES];
            return;
        }
    }
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)startPairing {
    PocketJPairingHost *host = PocketJPairingHost.sharedHost;
    if (host.running || !PocketJPairingHost.isSupported) return;
    if (!StikDebugEngine.sharedEngine.hasPairingFile) { [host start]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"重新配对本机", nil)
        message:localize(@"成功后将替换当前配对文件；失败或取消会保留原文件。电脑导入方式仍然可用。", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"取消", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"继续", nil) style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) { [host start]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
