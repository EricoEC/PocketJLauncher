#include "PocketJEnvironment.h"
#import "PocketJStartupOverlay.h"
#import "PocketJGameStartup.h"
#import "utils.h"

@interface PocketJStartupOverlay ()
@property(nonatomic) UIActivityIndicatorView *spinner;
@property(nonatomic) UILabel *stageLabel;
@property(nonatomic) UILabel *timerLabel;
@property(nonatomic) UIButton *exportButton;
@property(nonatomic) NSTimer *timer;
@property(nonatomic) NSTimeInterval started;
@property(nonatomic) uint64_t session;
@end

@implementation PocketJStartupOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    // Visual contract copied from GameWindow.swift's pre-first-frame VStack:
    // black canvas, centered vertical content, spacing 12, outer padding 24.
    self.backgroundColor = UIColor.blackColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = UIColor.whiteColor;
    self.spinner.hidesWhenStopped = YES;
    self.stageLabel = [UILabel new];
    self.stageLabel.textColor = UIColor.whiteColor;
    self.stageLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.stageLabel.adjustsFontForContentSizeCategory = YES;
    self.stageLabel.numberOfLines = 0;
    self.stageLabel.textAlignment = NSTextAlignmentCenter;
    self.stageLabel.accessibilityTraits |= UIAccessibilityTraitUpdatesFrequently;
    self.timerLabel = [UILabel new];
    self.timerLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular]];
    self.timerLabel.adjustsFontForContentSizeCategory = YES;
    self.timerLabel.textColor = UIColor.secondaryLabelColor;
    self.timerLabel.textAlignment = NSTextAlignmentCenter;
    UIButton *logs = [self buttonWithTitle:localize(@"engine.log.title", nil)
        symbol:@"doc.text.magnifyingglass" action:@selector(showLog)];
    self.exportButton = [self buttonWithTitle:localize(@"engine.log.export", nil)
        symbol:@"square.and.arrow.up" action:@selector(shareLog:)];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[self.spinner, self.stageLabel, self.timerLabel, logs, self.exportButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    // Keep the same centered content on phones and iPads, but allow scrolling
    // rather than clipping when landscape + accessibility text cannot fit.
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:scroll];
    [scroll addSubview:content];
    [content addSubview:stack];
    NSLayoutConstraint *fillHeight = [content.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor];
    fillHeight.priority = UILayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        fillHeight,
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [stack.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-48],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:content.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-24],
        [self.stageLabel.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor],
        [logs.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor],
        [self.exportButton.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor],
    ]];
    return self;
}

- (UIButton *)buttonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *image = [UIImage systemImageNamed:symbol];
    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration glassButtonConfiguration];
        configuration.title = title;
        configuration.image = image;
        configuration.imagePadding = 6;
        button.configuration = configuration;
    } else {
        [button setTitle:[@" " stringByAppendingString:title] forState:UIControlStateNormal];
        [button setImage:image forState:UIControlStateNormal];
        button.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    }
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.titleLabel.numberOfLines = 0;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)start {
    [self stop];
    self.session = PocketJGameStartupSnapshot().session;
    self.started = NSProcessInfo.processInfo.systemUptime;
    self.hidden = NO;
    [self refresh];
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)refresh {
    PJStartupSnapshot state = PocketJGameStartupSnapshot();
    if (state.session != self.session || state.hasFrame) {
        [self stop];
        [self removeFromSuperview];
        return;
    }
    NSString *key;
    switch (state.stage) {
        case PJStartupRuntime: key = @"engine.stage.jli"; break;
        case PJStartupJVM: key = @"engine.stage.jvm"; break;
        case PJStartupJNI: key = @"engine.stage.jni"; break;
        case PJStartupRenderer: key = state.metal ? @"engine.stage.renderer" : @"engine.stage.renderer.generic"; break;
        case PJStartupFrame: key = @"engine.stage.frame"; break;
        case PJStartupExited: key = @"engine.stage.exited"; break;
        case PJStartupFailed: key = @"engine.stage.failed"; break;
        default: key = @"engine.stage.window"; break;
    }
    NSString *text = localize(key, nil);
    if (![self.stageLabel.text isEqualToString:text]) self.stageLabel.text = text;
    if (state.active) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    NSUInteger seconds = (NSUInteger)MAX(0, NSProcessInfo.processInfo.systemUptime - self.started);
    self.timerLabel.text = seconds >= 3600
        ? [NSString stringWithFormat:@"%lu:%02lu:%02lu", (unsigned long)(seconds / 3600), (unsigned long)(seconds / 60 % 60), (unsigned long)(seconds % 60)]
        : [NSString stringWithFormat:@"%lu:%02lu", (unsigned long)(seconds / 60), (unsigned long)(seconds % 60)];
    NSString *path = [NSString stringWithFormat:@"%s/latestlog.txt", PocketJGetEnv("POCKETJ_HOME")];
    self.exportButton.hidden = ![NSFileManager.defaultManager fileExistsAtPath:path];
    if (!state.active) [self stop];
}

- (void)showLog { if (self.openLog) self.openLog(); }
- (void)shareLog:(UIButton *)sender { if (self.exportLog) self.exportLog(sender); }
- (void)dealloc { [self stop]; }
@end
