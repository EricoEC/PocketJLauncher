#import <dlfcn.h>
#import <objc/runtime.h>
#import "DownloadProgressViewController.h"
#import "ModernUITheme.h"
#import "WFWorkflowProgressView.h"
#import "utils.h"

@interface DownloadProgressViewController ()
@property NSInteger fileListCount;
@property(nonatomic) NSString *progressSummary;
@property(nonatomic) NSArray<NSString *> *displayFiles;
@property(nonatomic) NSArray<NSProgress *> *displayProgresses;
@property(nonatomic) NSTimer *refreshTimer;
@end

@implementation DownloadProgressViewController

- (instancetype)initWithTask:(MinecraftResourceDownloadTask *)task {
    self = [super init];
    self.task = task;
    return self;
}

- (void)loadView {
    [super loadView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(actionClose)];
    self.title = localize(@"下载进度", nil);
    self.tableView.allowsSelection = NO;
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];

    // Reveal the native page-sheet material instead of covering it with a
    // fixed grouped background, especially in light appearance.
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = nil;
    self.navigationController.view.backgroundColor = UIColor.clearColor;

    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = UIColor.clearColor;
    appearance.shadowColor = UIColor.clearColor;
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance;

    // Load WFWorkflowProgressView
    dlopen("/System/Library/PrivateFrameworks/WorkflowUIServices.framework/WorkflowUIServices", RTLD_GLOBAL);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshProgressUI];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.2
        target:self selector:@selector(refreshProgressUI)
        userInfo:nil repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)refreshProgressUI {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshProgressUI]; });
        return;
    }
    NSArray *files, *progresses;
    [self.task snapshotFileList:&files progressList:&progresses];
    BOOL countChanged = self.fileListCount != (NSInteger)files.count;
    self.displayFiles = files;
    self.displayProgresses = progresses;
    self.fileListCount = files.count;

    NSInteger completedFiles = 0;
    for (NSProgress *fileProgress in progresses) {
        if (fileProgress.finished) completedFiles++;
    }
    NSInteger percentage = (NSInteger)round(self.task.textProgress.fractionCompleted * 100.0);
    self.progressSummary = [NSString stringWithFormat:
        localize(@"已完成 %ld / %ld · %ld%%", nil),
        (long)completedFiles, (long)files.count,
        (long)MAX(0, MIN(percentage, 100))];

    if (countChanged) {
        [self.tableView reloadData];
    } else {
        for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            if (indexPath.row >= (NSInteger)progresses.count) continue;
            NSProgress *progress = progresses[indexPath.row];
            cell.detailTextLabel.text = progress.localizedAdditionalDescription;
            WFWorkflowProgressView *progressView = (id)cell.accessoryView;
            progressView.fractionCompleted = progress.fractionCompleted;
            [progressView transitionCompletedLayerToVisible:progress.finished animated:NO haptic:NO];
            [progressView transitionRunningLayerToVisible:!progress.finished animated:NO];
        }
    }
    [self.tableView headerViewForSection:0].textLabel.text = self.progressSummary;
}

- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section {
    return self.progressSummary ?: localize(@"已完成 0 / 0 · 0%", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.displayFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
        WFWorkflowProgressView *progressView = [[NSClassFromString(@"WFWorkflowProgressView") alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
        progressView.resolvedTintColor = self.view.tintColor;
        progressView.stopSize = 0;
        cell.accessoryView = progressView;
    }

    if (indexPath.row >= (NSInteger)self.displayProgresses.count) return cell;
    NSProgress *progress = self.displayProgresses[indexPath.row];

    WFWorkflowProgressView *progressView = (id)cell.accessoryView;
    [progressView reset];
    progressView.fractionCompleted = progress.fractionCompleted;
    [progressView transitionCompletedLayerToVisible:progress.finished animated:NO haptic:NO];
    [progressView transitionRunningLayerToVisible:!progress.finished animated:NO];

    cell.textLabel.text = self.displayFiles[indexPath.row];
    cell.detailTextLabel.text = progress.localizedAdditionalDescription;
    [ModernUITheme styleCell:cell destructive:NO];
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    return cell;
}

@end
