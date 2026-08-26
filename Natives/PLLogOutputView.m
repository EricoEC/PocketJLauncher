#import "PLLogOutputView.h"
#import <MessageUI/MessageUI.h>
#import "SurfaceViewController.h"
#import "ModernUITheme.h"
#import "utils.h"

@interface PLLogOutputView()<UITableViewDataSource, UITableViewDelegate, MFMailComposeViewControllerDelegate>
@property(nonatomic) UITableView* logTableView;
@property(nonatomic) UINavigationBar* navigationBar;
@property(nonatomic) UIVisualEffectView *feedbackPanel;
@end

@implementation PLLogOutputView
static BOOL fatalErrorOccurred;
static NSMutableArray* logLines;
static PLLogOutputView* current;

- (instancetype)initWithFrame:(CGRect)frame {
    UIViewController *vc = [UIViewController new];
    vc.view = self;
    self.navController = [[UINavigationController alloc] initWithRootViewController:vc];
    self.navigationBar = self.navController.navigationBar;
    
    frame.origin.y = frame.size.height;
    self = [super initWithFrame:frame];
    frame.origin.y = 0;

    logLines = [NSMutableArray new];
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    self.navController.view.hidden = YES;

    vc.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
            target:self action:@selector(actionToggleLogOutput)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
            target:self action:@selector(actionClearLogOutput)]
    ];
    vc.title = localize(@"game.menu.log_output", nil);

    self.logTableView = [[UITableView alloc] initWithFrame:frame];
    //self.logTableView.allowsSelection = NO;
    self.logTableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.logTableView.backgroundColor = UIColor.clearColor;
    self.logTableView.contentInset = UIEdgeInsetsMake(self.navigationBar.frame.size.height, 0, 0, 0);
    self.logTableView.dataSource = self;
    self.logTableView.delegate = self;
    self.logTableView.layoutMargins = UIEdgeInsetsZero;
    self.logTableView.rowHeight = 20;
    self.logTableView.separatorInset = UIEdgeInsetsZero;
    self.logTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self addSubview:self.logTableView];
    [self addSubview:self.navigationBar];
    [self installFeedbackPanel];

    canAppendToLog = YES;
    [self actionStartStopLogOutput];

    current = self;
    return self;
}

- (void)installFeedbackPanel {
    UIVisualEffectView *panel = [ModernUITheme glassViewWithCornerRadius:20 interactive:YES];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.hidden = YES;

    UIButton *issueButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButton *mailButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [issueButton addTarget:self action:@selector(actionSubmitIssue)
          forControlEvents:UIControlEventTouchUpInside];
    [mailButton addTarget:self action:@selector(actionSendFeedbackMail)
         forControlEvents:UIControlEventTouchUpInside];
    if (@available(iOS 15.0, *)) {
        issueButton.configuration = [ModernUITheme
            actionButtonConfigurationWithTitle:localize(@"提交 Issue", nil)
            image:[UIImage systemImageNamed:@"exclamationmark.bubble.fill"]
            tint:ModernUITheme.accentColor prominent:YES];
        mailButton.configuration = [ModernUITheme
            actionButtonConfigurationWithTitle:localize(@"发送反馈邮件", nil)
            image:[UIImage systemImageNamed:@"envelope.fill"]
            tint:ModernUITheme.accentColor prominent:NO];
    } else {
        [issueButton setTitle:localize(@"提交 Issue", nil) forState:UIControlStateNormal];
        [mailButton setTitle:localize(@"发送反馈邮件", nil) forState:UIControlStateNormal];
        issueButton.backgroundColor = ModernUITheme.accentColor;
        [issueButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        mailButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
        [ModernUITheme styleContinuousButton:issueButton cornerRadius:14];
        [ModernUITheme styleContinuousButton:mailButton cornerRadius:14];
    }
    issueButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    mailButton.titleLabel.adjustsFontForContentSizeCategory = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[issueButton, mailButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    [panel.contentView addSubview:stack];
    [self addSubview:panel];
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:12],
        [panel.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [panel.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor constant:10],
        [stack.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-10],
        [stack.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor constant:-10],
        [issueButton.heightAnchor constraintGreaterThanOrEqualToConstant:48],
        [mailButton.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    self.feedbackPanel = panel;
}

- (NSString *)latestLogPath {
    return [NSString stringWithFormat:@"%s/latestlog.txt", getenv("POJAV_HOME")];
}

- (void)actionSubmitIssue {
    NSURLComponents *components = [NSURLComponents componentsWithString:
        @"https://github.com/EricoEC/PocketJLauncher/issues/new"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"title" value:localize(@"[Bug] 请简要描述问题", nil)],
        [NSURLQueryItem queryItemWithName:@"body" value:localize(@"请描述复现步骤、Minecraft 版本、加载器与渲染器，并附上 latestlog.txt。", nil)],
    ];
    [UIApplication.sharedApplication openURL:components.URL options:@{} completionHandler:nil];
}

- (void)actionSendFeedbackMail {
    NSString *subject = localize(@"PocketJ Launcher 错误反馈", nil);
    NSString *body = localize(@"请在这里描述当时执行了什么操作、使用的 Minecraft 版本，以及遇到的错误：\n\n", nil);
    if ([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController *composer = [MFMailComposeViewController new];
        composer.mailComposeDelegate = self;
        [composer setToRecipients:@[@"report@epoxn.com"]];
        [composer setSubject:subject];
        [composer setMessageBody:body isHTML:NO];
        NSData *logData = [NSData dataWithContentsOfFile:self.latestLogPath];
        if (logData.length) {
            [composer addAttachmentData:logData mimeType:@"text/plain" fileName:@"latestlog.txt"];
        }
        [currentVC() presentViewController:composer animated:YES completion:nil];
        return;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:@"mailto:report@epoxn.com"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"subject" value:subject],
        [NSURLQueryItem queryItemWithName:@"body" value:body],
    ];
    [UIApplication.sharedApplication openURL:components.URL options:@{} completionHandler:nil];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return logLines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
        cell.backgroundColor = UIColor.clearColor;
        //cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont fontWithName:@"Menlo-Regular" size:16];
        cell.textLabel.textColor = UIColor.whiteColor;
    }
    cell.textLabel.text = logLines[indexPath.row];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSString *line = cell.textLabel.text;
    if (line.length == 0 || [line isEqualToString:@"\n"]) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:line preferredStyle:UIAlertControllerStyleActionSheet];
    alert.popoverPresentationController.sourceView = cell;
    alert.popoverPresentationController.sourceRect = cell.bounds;
    UIAlertAction *share = [UIAlertAction actionWithTitle:localize(localize(@"Share", nil), nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[line] applicationActivities:nil];
        activityVC.popoverPresentationController.sourceView = _navigationBar;
        activityVC.popoverPresentationController.sourceRect = _navigationBar.bounds;
        [currentVC() presentViewController:activityVC animated:YES completion:nil];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:share];
    [alert addAction:cancel];
    [currentVC() presentViewController:alert animated:YES completion:nil];
}

- (void)actionClearLogOutput {
    [logLines removeAllObjects];
    [self.logTableView reloadData];
}

- (void)actionShareLatestlog {
    NSString *latestlogPath = [NSString stringWithFormat:@"file://%s/latestlog.txt", getenv("POJAV_HOME")];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[@"latestlog.txt",
        [NSURL URLWithString:latestlogPath]] applicationActivities:nil];
    activityVC.popoverPresentationController.sourceView = self.navigationBar;
        activityVC.popoverPresentationController.sourceRect = self.navigationBar.bounds;
    [currentVC() presentViewController:activityVC animated:YES completion:nil];
}

- (void)actionStartStopLogOutput {
    canAppendToLog = !canAppendToLog;
    UINavigationItem* item = self.navigationBar.items[0];
    item.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:
            canAppendToLog ? UIBarButtonSystemItemPause : UIBarButtonSystemItemPlay
        target:self action:@selector(actionStartStopLogOutput)];
}

- (void)actionToggleLogOutput {
    if (fatalErrorOccurred) {
        [UIApplication.sharedApplication performSelector:@selector(suspend)];
        dispatch_group_leave(fatalExitGroup);
        return;
    }

    UIViewAnimationOptions opt = self.navController.view.hidden ? UIViewAnimationOptionCurveEaseOut : UIViewAnimationOptionCurveEaseIn;
    [UIView transitionWithView:self duration:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^(void){
        CGRect frame = self.frame;
        frame.origin.y = self.navController.view.hidden ? 0 : frame.size.height;
        self.navController.view.hidden = NO;
        self.frame = frame;
    } completion: ^(BOOL finished) {
        self.navController.view.hidden = self.frame.origin.y != 0;
    }];
}

+ (void)_appendToLog:(NSString *)line {
    if (line.length == 0) {
        return;
    }

    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:logLines.count inSection:0];
    [logLines addObject:line];
    UIView.animationsEnabled = NO;
    [current.logTableView beginUpdates];
    [current.logTableView
        insertRowsAtIndexPaths:@[indexPath]
        withRowAnimation:UITableViewRowAnimationNone];
    [current.logTableView endUpdates];
    UIView.animationsEnabled = YES;

    [current.logTableView 
        scrollToRowAtIndexPath:indexPath
        atScrollPosition:UITableViewScrollPositionBottom animated:NO];
}

+ (void)appendToLog:(NSString *)string {
    dispatch_async(dispatch_get_main_queue(), ^(void){
        NSArray *lines = [string componentsSeparatedByCharactersInSet:
            NSCharacterSet.newlineCharacterSet];
        for (NSString *line in lines) {
            [self _appendToLog:line];
        }
    });
}

+ (BOOL)handleExitCode:(int)code {
    if (!current) return NO;
    dispatch_async(dispatch_get_main_queue(), ^(void){
        if (current.navController.view.hidden) {
            [current actionToggleLogOutput];
        }
        // Cleanup navigation bar
        UINavigationBar *navigationBar = current.navigationBar;
        UILabel *exitTitle = [UILabel new];
        exitTitle.text = [NSString stringWithFormat:
            localize(@"game.title.exit_code", nil), code];
        exitTitle.textColor = UIColor.whiteColor;
        exitTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        exitTitle.adjustsFontForContentSizeCategory = YES;
        exitTitle.adjustsFontSizeToFitWidth = YES;
        exitTitle.minimumScaleFactor = 0.72;
        exitTitle.textAlignment = NSTextAlignmentCenter;
        navigationBar.topItem.titleView = exitTitle;
        navigationBar.tintColor = UIColor.whiteColor;
        navigationBar.items[0].leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemAction
            target:current action:@selector(actionShareLatestlog)];
        UIBarButtonItem *exitItem = navigationBar.items[0].rightBarButtonItems[0];
        navigationBar.items[0].rightBarButtonItems = nil;
        navigationBar.items[0].rightBarButtonItem = exitItem;
        current.feedbackPanel.hidden = NO;
        UIEdgeInsets inset = current.logTableView.contentInset;
        inset.bottom = 132;
        current.logTableView.contentInset = inset;
        current.logTableView.scrollIndicatorInsets = inset;

        if (canAppendToLog) {
            canAppendToLog = NO;
            fatalErrorOccurred = YES;
            return;
        }
        [current actionClearLogOutput];
        [self _appendToLog:@"... (latestlog.txt)"];
        NSString *latestlogPath = [NSString stringWithFormat:@"%s/latestlog.txt", getenv("POJAV_HOME")];
        NSString *linesStr = [NSString stringWithContentsOfFile:latestlogPath
            encoding:NSUTF8StringEncoding error:nil];
        NSArray *lines = [linesStr componentsSeparatedByCharactersInSet:
            NSCharacterSet.newlineCharacterSet];

        // Print last 100 lines from latestlog.txt
        for (int i = (lines.count > 100) ? lines.count - 100 : 0; i < lines.count; i++) {
            [self _appendToLog:lines[i]];
        }

        fatalErrorOccurred = YES;
    });
    return YES;
}

@end
