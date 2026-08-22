#import "ModernSettingsViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "LauncherPreferences.h"
#import "LauncherPrefContCfgViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "ModernUITheme.h"
#import "stikdebug/StikDebugViewController.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

static NSString *const ModernSettingTypeCapability = @"capability";
static NSString *const ModernSettingTypeSwitch = @"switch";
static NSString *const ModernSettingTypeSlider = @"slider";
static NSString *const ModernSettingTypePicker = @"picker";
static NSString *const ModernSettingTypeText = @"text";
static NSString *const ModernSettingTypeNavigation = @"navigation";
static NSString *const ModernSettingTypeAction = @"action";
static NSString *const ModernSettingTypeInformation = @"information";
static NSString *const ModernSettingTypeLink = @"link";
static NSString *const PocketJGitHubURLString = @"https://github.com/EricoEC/PocketJLauncher";
static NSCache<NSString *, UIImage *> *PocketJCreditsImageCache;

@interface ModernSettingsViewController ()
@property(nonatomic) NSArray<NSDictionary *> *sections;
@end

@implementation ModernSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (NSDictionary *)item:(NSString *)key
               section:(NSString *)section
                  type:(NSString *)type
                  icon:(NSString *)icon {
    return @{
        @"key": key ?: @"",
        @"section": section ?: @"",
        @"type": type,
        @"icon": icon ?: @"gearshape",
    };
}

- (NSDictionary *)slider:(NSString *)key
                 section:(NSString *)section
                    icon:(NSString *)icon
                     min:(NSInteger)minimum
                     max:(NSInteger)maximum
                  suffix:(NSString *)suffix {
    NSMutableDictionary *item =
        [[self item:key section:section type:ModernSettingTypeSlider icon:icon]
            mutableCopy];
    item[@"min"] = @(minimum);
    item[@"max"] = @(maximum);
    item[@"suffix"] = suffix ?: @"";
    return item;
}

- (NSDictionary *)fixedItemWithTitle:(NSString *)title
                                value:(NSString *)value
                                 type:(NSString *)type
                                 icon:(NSString *)icon
                                  key:(NSString *)key {
    return @{
        @"title": title,
        @"value": value ?: @"",
        @"type": type,
        @"icon": icon ?: @"info.circle",
        @"key": key ?: @"",
        @"section": @"",
    };
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"设置", nil);
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAutomatic;
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
    static dispatch_once_t cacheOnceToken;
    dispatch_once(&cacheOnceToken, ^{
        PocketJCreditsImageCache = [NSCache new];
        PocketJCreditsImageCache.countLimit = 8;
    });
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    [self buildSections];
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(jitStateDidChange:)
        name:@"PocketJJITStateDidChangeNotification" object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)jitStateDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self.tableView reloadData];
}

- (void)buildSections {
    NSArray *rendererKeys = getRendererKeys(NO);
    NSArray *rendererNames = getRendererNames(NO);
    NSInteger physicalMemory =
        (NSInteger)(NSProcessInfo.processInfo.physicalMemory / 1048576);

    NSMutableDictionary *appIcon =
        [[self item:@"appicon"
             section:@"general"
                type:ModernSettingTypePicker
                icon:@"paintbrush"] mutableCopy];
    appIcon[@"values"] = @[@"automatic", @"AppIcon-White", @"AppIcon-Dark"];
    appIcon[@"labels"] = @[
        localize(@"preference.title.appicon-automatic", nil),
        localize(@"preference.title.appicon-default", nil),
        localize(@"preference.title.appicon-dark", nil)
    ];

    NSMutableDictionary *renderer =
        [[self item:@"renderer"
             section:@"video"
                type:ModernSettingTypePicker
                icon:@"cpu"] mutableCopy];
    renderer[@"values"] = rendererKeys;
    renderer[@"labels"] = rendererNames;

    NSMutableDictionary *resetWarnings =
        [[self item:@"reset_warnings"
             section:@"general"
                type:ModernSettingTypeAction
                icon:@"exclamationmark.triangle"] mutableCopy];
    resetWarnings[@"action"] = @"resetWarnings";

    NSMutableDictionary *resetSettings =
        [[self item:@"reset_settings"
             section:@"general"
                type:ModernSettingTypeAction
                icon:@"arrow.counterclockwise"] mutableCopy];
    resetSettings[@"action"] = @"resetSettings";
    resetSettings[@"destructive"] = @YES;

    NSMutableDictionary *eraseDemo =
        [[self item:@"erase_demo_data"
             section:@"general"
                type:ModernSettingTypeAction
                icon:@"trash"] mutableCopy];
    eraseDemo[@"action"] = @"eraseDemo";
    eraseDemo[@"destructive"] = @YES;

    NSDictionary *controlPane =
        [self fixedItemWithTitle:localize(@"preference.title.default_gamepad_ctrl", nil)
                          value:@""
                           type:ModernSettingTypeNavigation
                           icon:@"gamecontroller"
                            key:@"controls"];
    NSDictionary *runtimePane =
        [self fixedItemWithTitle:localize(@"preference.title.manage_runtime", nil)
                          value:@"Java 8 / 17 / 21 / 25"
                           type:ModernSettingTypeNavigation
                           icon:@"cup.and.saucer.fill"
                            key:@"runtime"];
    NSMutableDictionary *fluidButtonSlide =
        [[self item:@"fluid_button_slide"
             section:@"control"
                type:ModernSettingTypeSwitch
                icon:@"hand.draw.fill"] mutableCopy];
    fluidButtonSlide[@"title"] = localize(@"丝滑滑入按键", nil);
    fluidButtonSlide[@"detail"] =
        localize(@"滑入即触发，跨缝不中断，并支持四向对角移动。", nil);

    NSMutableDictionary *legacyCompatibility =
        [[self item:@"legacy_compatibility"
             section:@"general"
                type:ModernSettingTypeSwitch
                icon:@"clock.arrow.trianglehead.counterclockwise.rotate.90"] mutableCopy];
    legacyCompatibility[@"title"] =
        localize(@"preference.title.legacy_compatibility", nil);
    legacyCompatibility[@"detail"] =
        localize(@"preference.detail.legacy_compatibility", nil);

    NSMutableDictionary *logViewer =
        [[self fixedItemWithTitle:localize(@"启动与错误日志", nil)
                           value:@""
                            type:ModernSettingTypeAction
                            icon:@"doc.text.magnifyingglass"
                             key:@"viewLog"] mutableCopy];
    logViewer[@"action"] = @"viewLog";
    NSMutableDictionary *logShare =
        [[self fixedItemWithTitle:localize(@"导出诊断日志", nil)
                           value:@""
                            type:ModernSettingTypeAction
                            icon:@"square.and.arrow.up"
                             key:@"shareLog"] mutableCopy];
    logShare[@"action"] = @"shareLog";

    NSMutableDictionary *creator =
        [[self fixedItemWithTitle:@"Erico"
                           value:localize(@"PocketJ Launcher 制作者", nil)
                            type:ModernSettingTypeLink
                            icon:@"person.crop.circle.fill"
                             key:@"credits_erico"] mutableCopy];
    creator[@"url"] = @"https://github.com/EricoEC";
    creator[@"avatarURL"] = @"https://github.com/EricoEC.png?size=128";

    self.sections = @[
        @{
            @"title": localize(@"运行环境", nil),
            @"footer": localize(@"JIT 取决于当前启动方式；内存权限取决于安装包的签名与描述文件。", nil),
            @"items": @[
                [self fixedItemWithTitle:@"JIT" value:@"" type:ModernSettingTypeCapability icon:@"bolt.fill" key:@"jit"],
                [self fixedItemWithTitle:localize(@"扩展虚拟地址空间", nil) value:@"" type:ModernSettingTypeCapability icon:@"memorychip" key:@"extendedVA"],
                [self fixedItemWithTitle:localize(@"更高内存上限", nil) value:@"" type:ModernSettingTypeCapability icon:@"gauge.with.dots.needle.67percent" key:@"memoryLimit"],
            ],
        },
        @{
            @"title": localize(@"preference.section.general", nil),
            @"items": @[
                [self item:@"check_sha" section:@"general" type:ModernSettingTypeSwitch icon:@"lock.shield"],
                legacyCompatibility,
                [self item:@"cosmetica" section:@"general" type:ModernSettingTypeSwitch icon:@"eyeglasses"],
                [self item:@"debug_logging" section:@"general" type:ModernSettingTypeSwitch icon:@"doc.badge.gearshape"],
                appIcon,
                resetWarnings,
                resetSettings,
                eraseDemo,
            ],
        },
        @{
            @"title": localize(@"preference.section.video", nil),
            @"items": @[
                renderer,
                [self slider:@"resolution" section:@"video" icon:@"viewfinder" min:25 max:150 suffix:@"%"],
                [self item:@"max_framerate" section:@"video" type:ModernSettingTypeSwitch icon:@"timelapse"],
                [self item:@"performance_hud" section:@"video" type:ModernSettingTypeSwitch icon:@"waveform.path.ecg"],
                [self item:@"fullscreen_airplay" section:@"video" type:ModernSettingTypeSwitch icon:@"airplayvideo"],
                [self item:@"silence_other_audio" section:@"video" type:ModernSettingTypeSwitch icon:@"speaker.slash"],
                [self item:@"silence_with_switch" section:@"video" type:ModernSettingTypeSwitch icon:@"speaker.zzz"],
                [self item:@"allow_microphone" section:@"video" type:ModernSettingTypeSwitch icon:@"mic"],
            ],
        },
        @{
            @"title": localize(@"preference.section.control", nil),
            @"items": @[
                controlPane,
                fluidButtonSlide,
                [self item:@"hardware_hide" section:@"control" type:ModernSettingTypeSwitch icon:@"eye.slash"],
                [self item:@"recording_hide" section:@"control" type:ModernSettingTypeSwitch icon:@"record.circle"],
                [self item:@"gesture_mouse" section:@"control" type:ModernSettingTypeSwitch icon:@"cursorarrow.click"],
                [self item:@"gesture_hotbar" section:@"control" type:ModernSettingTypeSwitch icon:@"hand.tap"],
                [self item:@"disable_haptics" section:@"control" type:ModernSettingTypeSwitch icon:@"wave.3.left"],
                [self item:@"slideable_hotbar" section:@"control" type:ModernSettingTypeSwitch icon:@"slider.horizontal.below.rectangle"],
                [self slider:@"press_duration" section:@"control" icon:@"cursorarrow.click.badge.clock" min:100 max:1000 suffix:@" ms"],
                [self slider:@"button_scale" section:@"control" icon:@"aspectratio" min:50 max:500 suffix:@"%"],
                [self slider:@"mouse_scale" section:@"control" icon:@"arrow.up.left.and.arrow.down.right.circle" min:25 max:300 suffix:@"%"],
                [self slider:@"mouse_speed" section:@"control" icon:@"cursorarrow.motionlines" min:25 max:300 suffix:@"%"],
                [self item:@"virtmouse_enable" section:@"control" type:ModernSettingTypeSwitch icon:@"cursorarrow.rays"],
                [self item:@"gyroscope_enable" section:@"control" type:ModernSettingTypeSwitch icon:@"gyroscope"],
                [self item:@"gyroscope_invert_x_axis" section:@"control" type:ModernSettingTypeSwitch icon:@"arrow.left.and.right"],
                [self slider:@"gyroscope_sensitivity" section:@"control" icon:@"move.3d" min:50 max:300 suffix:@"%"],
            ],
        },
        @{
            @"title": localize(@"preference.section.java", nil),
            @"items": @[
                runtimePane,
                [self item:@"java_args" section:@"java" type:ModernSettingTypeText icon:@"text.badge.plus"],
                [self item:@"env_variables" section:@"java" type:ModernSettingTypeText icon:@"terminal"],
                [self item:@"auto_ram" section:@"java" type:ModernSettingTypeSwitch icon:@"wand.and.stars"],
                [self slider:@"allocated_memory" section:@"java" icon:@"memorychip" min:250 max:(NSInteger)(physicalMemory * 0.85) suffix:@" MB"],
            ],
        },
        @{
            @"title": localize(@"preference.section.debug", nil),
            @"footer": localize(@"仅在排查启动或兼容问题时修改。", nil),
            @"items": @[
                [self item:@"debug_always_attached_jit" section:@"debug" type:ModernSettingTypeSwitch icon:@"app.connected.to.app.below.fill"],
                [self item:@"debug_skip_wait_jit" section:@"debug" type:ModernSettingTypeSwitch icon:@"forward"],
                [self item:@"debug_hide_home_indicator" section:@"debug" type:ModernSettingTypeSwitch icon:@"iphone.and.arrow.forward"],
                [self item:@"debug_ipad_ui" section:@"debug" type:ModernSettingTypeSwitch icon:@"ipad"],
                [self item:@"debug_wide_ui" section:@"debug" type:ModernSettingTypeSwitch icon:@"rectangle.expand.vertical"],
                [self item:@"debug_auto_correction" section:@"debug" type:ModernSettingTypeSwitch icon:@"textformat.abc.dottedunderline"],
            ],
        },
        @{
            @"title": localize(@"诊断", nil),
            @"footer": localize(@"启动失败不会静默处理；可直接查看或导出原版内核日志。", nil),
            @"items": @[logViewer, logShare],
        },
        @{
            @"title": localize(@"关于", nil),
            @"items": @[
                [self fixedItemWithTitle:localize(@"版本", nil) value:@"V1.1" type:ModernSettingTypeInformation icon:@"number" key:@""],
                [self fixedItemWithTitle:@"GitHub" value:PocketJGitHubURLString type:ModernSettingTypeLink icon:@"chevron.left.forwardslash.chevron.right" key:@"github"],
                [self fixedItemWithTitle:localize(@"兼容系统", nil) value:@"iOS 14–27" type:ModernSettingTypeInformation icon:@"iphone" key:@""],
                creator,
            ],
        },
    ];
}

- (NSDictionary *)itemAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections[indexPath.section][@"items"][indexPath.row];
}

- (NSString *)preferenceKeyForItem:(NSDictionary *)item {
    NSString *section = item[@"section"];
    NSString *key = item[@"key"];
    if (!section.length || !key.length) return @"";
    return [NSString stringWithFormat:@"%@.%@", section, key];
}

- (NSString *)titleForItem:(NSDictionary *)item {
    NSString *title = item[@"title"];
    if (title.length) return title;
    return localize([NSString stringWithFormat:@"preference.title.%@", item[@"key"]], nil);
}

- (NSString *)detailForItem:(NSDictionary *)item {
    NSString *explicitDetail = item[@"detail"];
    if (explicitDetail.length) return explicitDetail;
    NSString *key = item[@"key"];
    if (!key.length) return nil;
    NSString *localizationKey =
        [NSString stringWithFormat:@"preference.detail.%@", key];
    NSString *detail = localize(localizationKey, nil);
    return [detail isEqualToString:localizationKey] ? nil : detail;
}

- (NSString *)detailForItem:(NSDictionary *)item value:(NSString *)value {
    NSString *detail = [self detailForItem:item];
    if (!detail.length) return value;
    if (!value.length) return detail;
    return [NSString stringWithFormat:@"%@\n%@", value, detail];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"items"] count];
}

- (NSString *)tableView:(UITableView *)tableView
 titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (NSString *)tableView:(UITableView *)tableView
 titleForFooterInSection:(NSInteger)section {
    return self.sections[section][@"footer"];
}

- (BOOL)capabilityForKey:(NSString *)key {
    if ([key isEqualToString:@"jit"]) return isJITEnabled(YES);
    if ([key isEqualToString:@"extendedVA"]) {
        return getEntitlementValue(
            @"com.apple.developer.kernel.extended-virtual-addressing");
    }
    return getEntitlementValue(
        @"com.apple.developer.kernel.increased-memory-limit");
}

- (NSString *)displayValueForPicker:(NSDictionary *)item {
    NSString *current = getPrefObject([self preferenceKeyForItem:item]);
    NSArray *values = item[@"values"];
    NSArray *labels = item[@"labels"];
    NSUInteger index = [values indexOfObject:current ?: @""];
    if (index != NSNotFound && index < labels.count) return labels[index];
    return current.length ? current : localize(@"自动", nil);
}

- (BOOL)itemIsEnabled:(NSDictionary *)item {
    NSString *key = item[@"key"];
    if ([key isEqualToString:@"appicon"]) {
        return UIApplication.sharedApplication.supportsAlternateIcons;
    }
    if ([key isEqualToString:@"max_framerate"]) {
        return UIScreen.mainScreen.maximumFramesPerSecond > 60;
    }
    if ([key isEqualToString:@"performance_hud"]) {
        return [CAMetalLayer instancesRespondToSelector:@selector(developerHUDProperties)];
    }
    if ([key isEqualToString:@"allocated_memory"]) {
        return !getPrefBool(@"java.auto_ram");
    }
    return YES;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    NSString *type = item[@"type"];
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"NativeSettingCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc]
            initWithStyle:UITableViewCellStyleSubtitle
          reuseIdentifier:@"NativeSettingCell"];
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityHint = nil;
    cell.textLabel.text = [self titleForItem:item];
    cell.detailTextLabel.text = [self detailForItem:item];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [cell.textLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                   forAxis:UILayoutConstraintAxisHorizontal];
    [cell.detailTextLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                         forAxis:UILayoutConstraintAxisHorizontal];
    cell.imageView.image = [UIImage systemImageNamed:item[@"icon"]];
    NSString *avatarURL = item[@"avatarURL"];
    if (avatarURL.length) {
        UIImage *cachedAvatar = [PocketJCreditsImageCache objectForKey:avatarURL];
        if (cachedAvatar) {
            cell.imageView.image = cachedAvatar;
        } else {
            [self loadCreditsAvatar:avatarURL atIndexPath:indexPath];
        }
    }
    BOOL destructive = [item[@"destructive"] boolValue];
    [ModernUITheme styleCell:cell destructive:destructive];

    NSInteger tag = indexPath.section * 1000 + indexPath.row;
    NSString *preferenceKey = [self preferenceKeyForItem:item];
    if ([type isEqualToString:ModernSettingTypeSwitch]) {
        UISwitch *control = [UISwitch new];
        control.tag = tag;
        control.on = getPrefBool(preferenceKey);
        [control addTarget:self
                    action:@selector(switchChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessibilityHint = [self detailForItem:item];
    } else if ([type isEqualToString:ModernSettingTypeSlider]) {
        UISlider *control = [UISlider new];
        control.tag = tag;
        control.minimumValue = [item[@"min"] floatValue];
        control.maximumValue = [item[@"max"] floatValue];
        control.value = getPrefFloat(preferenceKey);
        control.continuous = YES;
        [control.widthAnchor constraintGreaterThanOrEqualToConstant:84].active = YES;
        [control.widthAnchor constraintLessThanOrEqualToConstant:132].active = YES;
        [control setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                  forAxis:UILayoutConstraintAxisHorizontal];
        [control addTarget:self
                    action:@selector(sliderChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = control;
        NSString *value = [NSString stringWithFormat:@"%ld%@",
            (long)lroundf(control.value), item[@"suffix"]];
        cell.detailTextLabel.text = [self detailForItem:item value:value];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:ModernSettingTypeCapability]) {
        BOOL available = [self capabilityForKey:item[@"key"]];
        UILabel *state = [UILabel new];
        state.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        state.adjustsFontForContentSizeCategory = YES;
        state.text = available ? localize(@"可用", nil) : localize(@"不可用", nil);
        state.textColor =
            available ? UIColor.systemGreenColor : UIColor.systemRedColor;
        [state sizeToFit];
        if ([item[@"key"] isEqualToString:@"jit"]) {
            UIImageView *chevron = [[UIImageView alloc] initWithImage:
                [UIImage systemImageNamed:@"chevron.right"]];
            chevron.tintColor = UIColor.tertiaryLabelColor;
            chevron.contentMode = UIViewContentModeScaleAspectFit;
            [chevron.widthAnchor constraintEqualToConstant:8.0].active = YES;
            [chevron.heightAnchor constraintEqualToConstant:14.0].active = YES;
            UIStackView *accessory = [[UIStackView alloc]
                initWithArrangedSubviews:@[state, chevron]];
            accessory.axis = UILayoutConstraintAxisHorizontal;
            accessory.alignment = UIStackViewAlignmentCenter;
            accessory.spacing = 8.0;
            [accessory sizeToFit];
            CGSize fittingSize = [accessory
                systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
            accessory.frame = CGRectMake(0, 0,
                MAX(52.0, fittingSize.width), MAX(24.0, fittingSize.height));
            cell.accessoryView = accessory;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessibilityHint = localize(@"打开 JIT 设置", nil);
        } else {
            cell.accessoryView = state;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else if ([type isEqualToString:ModernSettingTypePicker]) {
        cell.detailTextLabel.text = [self detailForItem:item
            value:[self displayValueForPicker:item]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([type isEqualToString:ModernSettingTypeText]) {
        NSString *value = getPrefObject(preferenceKey);
        cell.detailTextLabel.text = [self detailForItem:item
            value:(value.length ? value : localize(@"未设置", nil))];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([type isEqualToString:ModernSettingTypeNavigation]) {
        cell.detailTextLabel.text = [self detailForItem:item value:item[@"value"]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([type isEqualToString:ModernSettingTypeInformation]) {
        cell.detailTextLabel.text = item[@"value"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:ModernSettingTypeLink]) {
        cell.detailTextLabel.text = item[@"value"];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *image = [UIImage systemImageNamed:@"arrow.up.right"];
        if (@available(iOS 26.0, *)) {
            UIButtonConfiguration *configuration =
                [UIButtonConfiguration glassButtonConfiguration];
            configuration.image = image;
            configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
            configuration.baseForegroundColor = ModernUITheme.accentColor;
            button.configuration = configuration;
        } else if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *configuration =
                [UIButtonConfiguration tintedButtonConfiguration];
            configuration.image = image;
            configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
            configuration.baseForegroundColor = ModernUITheme.accentColor;
            configuration.baseBackgroundColor = ModernUITheme.accentColor;
            button.configuration = configuration;
        } else {
            [button setImage:image forState:UIControlStateNormal];
            button.tintColor = ModernUITheme.accentColor;
            button.backgroundColor = UIColor.secondarySystemBackgroundColor;
            [ModernUITheme styleContinuousButton:button cornerRadius:22.0];
        }
        button.accessibilityLabel = [NSString stringWithFormat:localize(@"打开 %@ 的 GitHub", nil),
            [self titleForItem:item]];
        button.accessibilityIdentifier = item[@"url"] ?: item[@"value"];
        [button addTarget:self
                   action:@selector(openLink:)
         forControlEvents:UIControlEventTouchUpInside];
        // UITableViewCell does not lay out an accessory view from Auto Layout
        // constraints. Give it a concrete size so it stays at the trailing edge.
        button.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
        cell.accessoryView = button;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    BOOL enabled = [self itemIsEnabled:item];
    cell.userInteractionEnabled = enabled;
    cell.textLabel.enabled = enabled;
    cell.detailTextLabel.enabled = enabled;
    if ([cell.accessoryView isKindOfClass:UIControl.class]) {
        [(UIControl *)cell.accessoryView setEnabled:enabled];
    }
    return cell;
}

- (void)loadCreditsAvatar:(NSString *)URLString
              atIndexPath:(NSIndexPath *)indexPath {
    NSURL *URL = [NSURL URLWithString:URLString];
    if (!URL) return;
    NSURLRequest *request = [NSURLRequest requestWithURL:URL
        cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:15.0];
    [[NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) return;
        UIImage *source = [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
        if (!source) return;
        CGSize size = CGSizeMake(44.0, 44.0);
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = UIScreen.mainScreen.scale;
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
            initWithSize:size format:format];
        UIImage *renderedAvatar = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGRect bounds = (CGRect){CGPointZero, size};
            [[UIBezierPath bezierPathWithOvalInRect:bounds] addClip];
            CGFloat scale = MAX(size.width / source.size.width,
                size.height / source.size.height);
            CGSize drawSize = CGSizeMake(source.size.width * scale,
                source.size.height * scale);
            CGRect drawRect = CGRectMake((size.width - drawSize.width) / 2.0,
                (size.height - drawSize.height) / 2.0, drawSize.width, drawSize.height);
            [source drawInRect:drawRect];
        }];
        UIImage *avatar = [renderedAvatar imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [PocketJCreditsImageCache setObject:avatar forKey:URLString];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (indexPath.section >= self.sections.count ||
                indexPath.row >= [self.sections[indexPath.section][@"items"] count]) return;
            NSDictionary *currentItem = [self itemAtIndexPath:indexPath];
            if (![currentItem[@"avatarURL"] isEqualToString:URLString]) return;
            UITableViewCell *visibleCell = [self.tableView cellForRowAtIndexPath:indexPath];
            visibleCell.imageView.image = avatar;
            [visibleCell setNeedsLayout];
        });
    }] resume];
}

- (void)openLink:(UIButton *)sender {
    NSURL *URL = [NSURL URLWithString:sender.accessibilityIdentifier ?: @""];
    if (!URL) return;
    [UIApplication.sharedApplication openURL:URL
                                     options:@{}
                           completionHandler:nil];
}

- (CGFloat)tableView:(UITableView *)tableView
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    NSString *type = item[@"type"];
    NSString *title = [self titleForItem:item] ?: @"";
    NSString *detail = [self detailForItem:item] ?: @"";
    if ([type isEqualToString:ModernSettingTypeInformation] ||
        [type isEqualToString:ModernSettingTypeLink]) {
        detail = item[@"value"] ?: @"";
    }

    CGFloat accessoryWidth = 28.0;
    if ([type isEqualToString:ModernSettingTypeSwitch] ||
        [type isEqualToString:ModernSettingTypeCapability]) {
        accessoryWidth = 76.0;
    } else if ([type isEqualToString:ModernSettingTypeSlider]) {
        accessoryWidth = MIN(132.0, MAX(84.0,
            CGRectGetWidth(tableView.bounds) * 0.28));
    } else if ([type isEqualToString:ModernSettingTypeLink]) {
        accessoryWidth = 52.0;
    }

    // Account for grouped insets, image, accessory and the cell's internal
    // margins. Text gets the real remaining width and grows vertically for any
    // language or Dynamic Type size instead of overlapping the next row.
    CGFloat textWidth = CGRectGetWidth(tableView.bounds) -
        32.0 - 44.0 - accessoryWidth - 32.0;
    textWidth = MAX(textWidth, 120.0);
    UIFont *titleFont = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIFont *detailFont = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    NSStringDrawingOptions options =
        NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading;
    CGFloat titleHeight = ceil([title boundingRectWithSize:
        CGSizeMake(textWidth, CGFLOAT_MAX) options:options
        attributes:@{NSFontAttributeName: titleFont} context:nil].size.height);
    CGFloat detailHeight = detail.length ? ceil([detail boundingRectWithSize:
        CGSizeMake(textWidth, CGFLOAT_MAX) options:options
        attributes:@{NSFontAttributeName: detailFont} context:nil].size.height) : 0;
    return MAX(62.0, titleHeight + detailHeight + (detail.length ? 22.0 : 28.0));
}

- (NSIndexPath *)indexPathForControl:(UIControl *)control {
    return [NSIndexPath indexPathForRow:control.tag % 1000
                             inSection:control.tag / 1000];
}

- (void)switchChanged:(UISwitch *)control {
    NSIndexPath *indexPath = [self indexPathForControl:control];
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    setPrefBool([self preferenceKeyForItem:item], control.isOn);
    if ([item[@"key"] isEqualToString:@"debug_logging"]) {
        debugLogEnabled = control.isOn;
    }
    if ([item[@"key"] isEqualToString:@"auto_ram"]) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)sliderChanged:(UISlider *)control {
    NSIndexPath *indexPath = [self indexPathForControl:control];
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    NSInteger value = lroundf(control.value);
    if ([item[@"key"] isEqualToString:@"allocated_memory"]) {
        value = lround(value / 256.0) * 256;
    }
    setPrefInt([self preferenceKeyForItem:item], value);
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSString *displayValue =
        [NSString stringWithFormat:@"%ld%@", (long)value, item[@"suffix"]];
    cell.detailTextLabel.text = [self detailForItem:item value:displayValue];
    control.accessibilityValue = cell.detailTextLabel.text;
}

- (void)showPickerForItem:(NSDictionary *)item
                     cell:(UITableViewCell *)cell {
    UIAlertController *picker =
        [UIAlertController alertControllerWithTitle:[self titleForItem:item]
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *values = item[@"values"];
    NSArray *labels = item[@"labels"];
    for (NSUInteger index = 0; index < values.count; index++) {
        NSString *label = index < labels.count ? labels[index] : values[index];
        [picker addAction:[UIAlertAction actionWithTitle:label
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            NSString *value = values[index];
            setPrefObject([self preferenceKeyForItem:item], value);
            if ([item[@"key"] isEqualToString:@"appicon"]) {
                NSString *iconName =
                    ([value isEqualToString:@"automatic"] ||
                     [value isEqualToString:@"AppIcon-Light"]) ? nil : value;
                [UIApplication.sharedApplication
                    setAlternateIconName:iconName
                       completionHandler:^(NSError *error) {
                    if (error) showDialog(localize(@"Error", nil), error.localizedDescription);
                }];
            }
            [self.tableView reloadData];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    picker.popoverPresentationController.sourceView = cell;
    picker.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)showTextEditorForItem:(NSDictionary *)item {
    NSString *preferenceKey = [self preferenceKeyForItem:item];
    UIAlertController *editor =
        [UIAlertController alertControllerWithTitle:[self titleForItem:item]
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];
    [editor addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = getPrefObject(preferenceKey);
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [editor addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [editor addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil)
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        setPrefObject(preferenceKey, editor.textFields.firstObject.text ?: @"");
        [self.tableView reloadData];
    }]];
    [self presentViewController:editor animated:YES completion:nil];
}

- (void)confirmDestructiveAction:(NSString *)action {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:localize(@"确认操作", nil)
                                            message:localize(@"此操作会修改或移除当前设置。", nil)
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:localize(@"继续", nil)
                                             style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *selected) {
        if ([action isEqualToString:@"resetSettings"]) {
            loadPreferences(YES);
        } else if ([action isEqualToString:@"eraseDemo"]) {
            NSString *path =
                [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")];
            [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            [NSFileManager.defaultManager
                createDirectoryAtPath:path
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        }
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performAction:(NSString *)action fromCell:(UITableViewCell *)cell {
    if ([action isEqualToString:@"resetWarnings"]) {
        resetWarnings();
        return;
    }
    if ([action isEqualToString:@"resetSettings"] ||
        [action isEqualToString:@"eraseDemo"]) {
        [self confirmDestructiveAction:action];
        return;
    }

    NSString *path =
        [NSString stringWithFormat:@"%s/latestlog.txt", getenv("POJAV_HOME")];
    if ([action isEqualToString:@"viewLog"]) {
        NSString *text =
            [NSString stringWithContentsOfFile:path
                                      encoding:NSUTF8StringEncoding
                                         error:nil];
        UIViewController *viewer = [UIViewController new];
        viewer.title = localize(@"诊断日志", nil);
        UITextView *textView = [UITextView new];
        textView.editable = NO;
        textView.font =
            [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
        textView.text = text.length ? text : localize(@"暂无日志", nil);
        textView.adjustsFontForContentSizeCategory = YES;
        viewer.view = textView;
        [self.navigationController pushViewController:viewer animated:YES];
    } else if ([action isEqualToString:@"shareLog"]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
            showDialog(localize(@"Error", nil), localize(@"暂无可导出的日志", nil));
            return;
        }
        UIActivityViewController *share =
            [[UIActivityViewController alloc]
                initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                applicationActivities:nil];
        share.popoverPresentationController.sourceView = cell;
        share.popoverPresentationController.sourceRect = cell.bounds;
        [self presentViewController:share animated:YES completion:nil];
    }
}

- (void)tableView:(UITableView *)tableView
 didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = [self itemAtIndexPath:indexPath];
    NSString *type = item[@"type"];
    if ([type isEqualToString:ModernSettingTypePicker]) {
        [self showPickerForItem:item cell:cell];
    } else if ([type isEqualToString:ModernSettingTypeText]) {
        [self showTextEditorForItem:item];
    } else if ([type isEqualToString:ModernSettingTypeCapability] &&
               [item[@"key"] isEqualToString:@"jit"]) {
        [self.navigationController
            pushViewController:[StikDebugViewController new]
                      animated:YES];
    } else if ([type isEqualToString:ModernSettingTypeNavigation]) {
        if ([item[@"key"] isEqualToString:@"stikdebug"]) {
            [self.navigationController
                pushViewController:[StikDebugViewController new]
                          animated:YES];
        } else if ([item[@"key"] isEqualToString:@"runtime"]) {
            [self.navigationController
                pushViewController:[LauncherPrefManageJREViewController new]
                          animated:YES];
        } else {
            [self.navigationController
                pushViewController:[LauncherPrefContCfgViewController new]
                          animated:YES];
        }
    } else if ([type isEqualToString:ModernSettingTypeAction]) {
        [self performAction:item[@"action"] fromCell:cell];
    }
}

@end
