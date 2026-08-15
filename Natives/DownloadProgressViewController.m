#import <dlfcn.h>
#import <objc/runtime.h>
#import "DownloadProgressViewController.h"
#import "ModernUITheme.h"
#import "WFWorkflowProgressView.h"
#import "utils.h"

static void *CellProgressObserverContext = &CellProgressObserverContext;
static void *TotalProgressObserverContext = &TotalProgressObserverContext;

@interface DownloadProgressViewController ()
@property NSInteger fileListCount;
@property(nonatomic) NSString *progressSummary;
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

    // Load WFWorkflowProgressView
    dlopen("/System/Library/PrivateFrameworks/WorkflowUIServices.framework/WorkflowUIServices", RTLD_GLOBAL);
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
[self.task.textProgress addObserver:self
        forKeyPath:@"fractionCompleted"
        options:NSKeyValueObservingOptionInitial
        context:TotalProgressObserverContext];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
[self.task.textProgress removeObserver:self forKeyPath:@"fractionCompleted"];
}

- (void)actionClose {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    NSProgress *progress = object;
    if (context == CellProgressObserverContext) {
        UITableViewCell *cell = objc_getAssociatedObject(progress, @"cell");
        if (!cell) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            cell.detailTextLabel.text = progress.localizedAdditionalDescription;
            WFWorkflowProgressView *progressView = (id)cell.accessoryView;
            progressView.fractionCompleted = progress.fractionCompleted;
            if (progress.finished) {
                [progressView transitionCompletedLayerToVisible:YES animated:NO haptic:NO];
            }
        });
    } else if (context == TotalProgressObserverContext) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.fileListCount != self.task.fileList.count) {
                [self.tableView reloadData];
            }
            self.fileListCount = self.task.fileList.count;
            NSInteger completedFiles = 0;
            for (NSProgress *fileProgress in self.task.progressList) {
                if (fileProgress.finished) completedFiles++;
            }
            NSInteger totalFiles = self.task.fileList.count;
            NSInteger percentage =
                (NSInteger)round(progress.fractionCompleted * 100.0);
            self.progressSummary = [NSString stringWithFormat:
                localize(@"已完成 %ld / %ld · %ld%%", nil),
                (long)MIN(completedFiles, totalFiles),
                (long)totalFiles,
                (long)MAX(0, MIN(percentage, 100))];
            UITableViewHeaderFooterView *header =
                [self.tableView headerViewForSection:0];
            header.textLabel.text = self.progressSummary;
        });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section {
    return self.progressSummary ?: localize(@"已完成 0 / 0 · 0%", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.task.fileList.count;
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

    // Unset the last cell displaying the progress
    NSProgress *lastProgress = objc_getAssociatedObject(cell, @"progress");
    if (lastProgress) {
        objc_setAssociatedObject(lastProgress, @"cell", nil, OBJC_ASSOCIATION_ASSIGN);
        @try {
            [lastProgress removeObserver:self forKeyPath:@"fractionCompleted"];
        } @catch(id anException) {}
    }

    NSProgress *progress = self.task.progressList[indexPath.row];
    objc_setAssociatedObject(cell, @"progress", progress, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(progress, @"cell", cell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [progress addObserver:self
        forKeyPath:@"fractionCompleted"
        options:NSKeyValueObservingOptionInitial
        context:CellProgressObserverContext];

    WFWorkflowProgressView *progressView = (id)cell.accessoryView;
    if (lastProgress.finished) {
        [progressView reset];
    }
    progressView.fractionCompleted = progress.fractionCompleted;
    [progressView transitionCompletedLayerToVisible:progress.finished animated:NO haptic:NO];
    [progressView transitionRunningLayerToVisible:!progress.finished animated:NO];

    cell.textLabel.text = self.task.fileList[indexPath.row];
    cell.detailTextLabel.text = progress.localizedAdditionalDescription;
    [ModernUITheme styleCell:cell destructive:NO];
    return cell;
}

@end
