#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "input/ControllerInput.h"
#import "customcontrols/CustomControlsUtils.h"
#import "CustomControlsViewController.h"
#import "FileListViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPrefContCfgViewController.h"
#import "ModernUITheme.h"
#import "PickTextField.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#include "glfw_keycodes.h"

#define contentNavigationController (LauncherNavigationController *)UIApplication.sharedApplication.keyWindow.rootViewController.splitViewController.viewControllers[1]

typedef void(^CreateView)(UITableViewCell *, NSString *, NSDictionary *);

@interface LauncherPrefContCfgViewController ()<UITextFieldDelegate, UIPopoverPresentationControllerDelegate, UIPickerViewDataSource, UIPickerViewDelegate, UIDocumentPickerDelegate>
@property(nonatomic) NSString *currentFileName;
@property(nonatomic) NSMutableDictionary *currentMappings;
@property(nonatomic) NSDictionary *keycodePlist;
@property(nonatomic) UIPickerView *editPickMapping;
@property(nonatomic) UITextField *activeTextField;
@property(nonatomic) NSArray<NSString*>* prefSections;
@property(nonatomic) NSMutableArray<NSNumber*>* prefSectionsVisibility;
@property(nonatomic) NSArray<NSDictionary*> *prefControllerTypes;
@property(nonatomic) NSMutableArray *keyCodeMap, *keyValueMap;
@property(nonatomic) BOOL importingKeyLayout;
@property(nonatomic) NSArray<NSString *> *keyLayoutFiles;

@end

@implementation LauncherPrefContCfgViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = localize(@"控制", nil);
    
    self.keycodePlist = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"glfw_keycodes" ofType:@"plist"]];
    
    self.keyCodeMap = [[NSMutableArray alloc] init];
    self.keyValueMap = [[NSMutableArray alloc] init];
    initKeycodeTable(self.keyCodeMap, self.keyValueMap);
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
    self.tableView.sectionFooterHeight = 50;
    
    [self loadGamepadConfigurationFile];
    self.prefControllerTypes = @[@{@"name": @"xbox"}, @{@"name": @"playstation"}];
    
    self.prefSections = @[@"key_layout_editor", @"game_mappings", @"menu_mappings", @"controller_style"];
    self.prefSectionsVisibility = [@[
        @(![NSUserDefaults.standardUserDefaults boolForKey:@"PocketJTouchControlsCollapsed"]),
        @(![NSUserDefaults.standardUserDefaults boolForKey:@"PocketJGamepadControlsCollapsed"])
    ] mutableCopy];
    [self reloadKeyLayoutFiles];
    
    self.editPickMapping = [[UIPickerView alloc] init];
    self.editPickMapping.delegate = self;
    self.editPickMapping.dataSource = self;
}

- (void)loadGamepadConfigurationFile {
    NSString *gamepadPath = [NSString stringWithFormat:@"%s/controlmap/gamepads/%@", getenv("POJAV_HOME"), getPrefObject(@"control.default_gamepad_ctrl")];
    self.currentMappings = parseJSONFromFile(gamepadPath);
    self.currentFileName = [getPrefObject(@"control.default_ctrl") stringByDeletingPathExtension];
    NSPredicate *filterPredicate = [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *dict) {
        return ![obj[@"name"] hasPrefix:@"mouse_"];
    }];
    [self.currentMappings[@"mGameMappingList"] filterUsingPredicate:filterPredicate];
    [self.currentMappings[@"mMenuMappingList"] filterUsingPredicate:filterPredicate];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadKeyLayoutFiles];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                  withRowAnimation:UITableViewRowAnimationNone];
}

- (void)reloadKeyLayoutFiles {
    NSString *path =
        [NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *file in
            [NSFileManager.defaultManager contentsOfDirectoryAtPath:path
                                                               error:nil]) {
        BOOL isDirectory = NO;
        NSString *fullPath = [path stringByAppendingPathComponent:file];
        if ([NSFileManager.defaultManager fileExistsAtPath:fullPath
                                               isDirectory:&isDirectory] &&
            !isDirectory &&
            [file.pathExtension.lowercaseString isEqualToString:@"json"]) {
            [files addObject:file];
        }
    }
    [files sortUsingSelector:@selector(localizedStandardCompare:)];
    if ([files containsObject:@"default.json"]) {
        [files removeObject:@"default.json"];
        [files insertObject:@"default.json" atIndex:0];
    }
    self.keyLayoutFiles = files;
}

#pragma mark External UITableView functions

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.prefSections.count;
}

- (NSArray *)prefContentForIndex:(NSInteger)index {
    switch (index) {
        case 0: return nil; // one single cell is defined in cellForRowAtIndexPath
        case 1: return self.currentMappings[@"mGameMappingList"];
        case 2: return self.currentMappings[@"mMenuMappingList"];
        case 3: return self.prefControllerTypes;
        default: return nil;
    } 
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        if (!self.prefSectionsVisibility[0].boolValue) return 0;
        return self.keyLayoutFiles.count + 3;
    } else {
        // Sections 1...end are one native "Gamepad Controls" disclosure group.
        if (!self.prefSectionsVisibility[1].boolValue) return 0;
        return [self prefContentForIndex:section].count;
    }
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableDictionary *item = [self prefContentForIndex:indexPath.section][indexPath.row];
    NSString *cellID = [NSString stringWithFormat:@"cellValue%ld", indexPath.section];
    UITableViewCellStyle cellStyle = indexPath.section == 0
        ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:cellStyle reuseIdentifier:cellID];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }

    if(indexPath.section == 0) {
        cell.accessoryView = nil;
        if (indexPath.row == 0) {
            cell.imageView.image = [UIImage systemImageNamed:@"hand.draw.fill"];
            cell.textLabel.text = localize(@"丝滑滑入按键", nil);
            cell.detailTextLabel.text = localize(@"滑入即触发，跨缝不中断，并支持四向对角移动。", nil);
            UISwitch *toggle = [UISwitch new];
            toggle.on = getPrefBool(@"control.fluid_button_slide");
            [toggle addTarget:self action:@selector(toggleFluidButtonSlide:)
                forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row <= self.keyLayoutFiles.count) {
            NSString *fileName = self.keyLayoutFiles[indexPath.row - 1];
            cell.imageView.image =
                [UIImage systemImageNamed:@"keyboard.badge.ellipsis"];
            cell.textLabel.text = fileName.stringByDeletingPathExtension;
            cell.detailTextLabel.text =
                [fileName isEqualToString:getPrefObject(@"control.default_ctrl")]
                    ? localize(@"当前键位", nil) : nil;
            cell.accessoryType =
                [fileName isEqualToString:getPrefObject(@"control.default_ctrl")]
                    ? UITableViewCellAccessoryCheckmark
                    : UITableViewCellAccessoryDisclosureIndicator;
        } else {
            BOOL exporting = indexPath.row == self.keyLayoutFiles.count + 1;
            cell.imageView.image = [UIImage systemImageNamed:
                exporting ? @"square.and.arrow.up" : @"square.and.arrow.down"];
            cell.textLabel.text =
                exporting ? localize(@"导出当前键位 JSON", nil) : localize(@"导入键位 JSON", nil);
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.detailTextLabel.text = nil;
        }
    } else if(indexPath.section == 1 || indexPath.section == 2) {
        NSNumber *keycode = (NSNumber *)item[@"keycode"];
        cell.textLabel.text = localize(([NSString stringWithFormat:@"controller_configurator.%@.title.%@", getPrefObject(@"control.controller_type"), item[@"name"]]), nil);
        PickTextField *view = (id)cell.accessoryView;
        if (view == nil) {
            view = [[PickTextField alloc] initWithFrame:CGRectMake(0, 0, cell.bounds.size.width / 2.1, cell.bounds.size.height)];
            [view addTarget:view action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];
            view.autocorrectionType = UITextAutocorrectionTypeNo;
            view.autocapitalizationType = UITextAutocapitalizationTypeNone;
            view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin;
            view.delegate = self;
            view.returnKeyType = UIReturnKeyDone;
            view.tag = indexPath.section;
            view.textAlignment = NSTextAlignmentRight;
            view.tintColor = UIColor.clearColor;
            view.adjustsFontSizeToFitWidth = YES;
            view.inputView = self.editPickMapping;
            [view setupDoneButtonWithTarget:self action:@selector(closeTextField:)];
            cell.accessoryView = view;
        }
        view.text = self.keyCodeMap[[self.keyValueMap indexOfObject:keycode]];
        objc_setAssociatedObject(view, @"gamepad_button", item[@"name"], OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(view, @"item", item, OBJC_ASSOCIATION_ASSIGN);
    } else if(indexPath.section == 3) {
        cell.textLabel.text = localize([NSString stringWithFormat:@"controller_configurator.title.type.%@", item[@"name"]], nil);
        if ([getPrefObject(@"control.controller_type") isEqualToString:item[@"name"]]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        } else {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }
    [ModernUITheme styleCell:cell destructive:NO];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return localize(@"触控键位", nil);
    }
    if (section == 1) {
        return localize(@"手柄键位", nil);
    }
    if (!self.prefSectionsVisibility[1].boolValue) return nil;
    return localize([NSString stringWithFormat:@"controller_configurator.section.%@", self.prefSections[section]], nil);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section > 1) return nil;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = section;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    button.contentEdgeInsets = UIEdgeInsetsMake(4, 20, 4, 20);
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    NSString *title = section == 0 ? localize(@"触控键位", nil) : localize(@"手柄键位", nil);
    UIImage *image = [UIImage systemImageNamed:
        self.prefSectionsVisibility[section].boolValue ? @"chevron.down" : @"chevron.right"];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.title = title;
        configuration.image = image;
        configuration.imagePlacement = NSDirectionalRectEdgeTrailing;
        configuration.imagePadding = 8;
        configuration.baseForegroundColor = UIColor.secondaryLabelColor;
        button.configuration = configuration;
    } else {
        [button setTitle:title forState:UIControlStateNormal];
        [button setImage:image forState:UIControlStateNormal];
        button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        button.tintColor = UIColor.secondaryLabelColor;
    }
    [button addTarget:self action:@selector(toggleControlSection:)
        forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityHint = localize(@"轻点展开或折叠", nil);
    return button;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section <= 1) return 48.0;
    return self.prefSectionsVisibility[1].boolValue ? UITableViewAutomaticDimension : 0.01;
}

- (void)toggleControlSection:(UIButton *)sender {
    NSInteger section = sender.tag;
    if (section < 0 || section >= self.prefSectionsVisibility.count) return;
    BOOL expanded = !self.prefSectionsVisibility[section].boolValue;
    self.prefSectionsVisibility[section] = @(expanded);
    NSString *key = section == 0
        ? @"PocketJTouchControlsCollapsed" : @"PocketJGamepadControlsCollapsed";
    [NSUserDefaults.standardUserDefaults setBool:!expanded forKey:key];
    NSRange range = section == 0 ? NSMakeRange(0, 1)
        : NSMakeRange(1, self.prefSections.count - 1);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:range]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return localize(@"开启后，手指从屏幕任意位置滑入按键即可触发；滑过按键间隙不会中断，滑入方向键夹角时可同时触发两个方向。", nil);
    }
    if (!self.prefSectionsVisibility[1].boolValue) return nil;
    NSString *key = [NSString stringWithFormat:@"controller_configurator.section.footer.%@", self.prefSections[section]];
    NSString *footer = localize(key, nil);
    return [footer isEqualToString:key] ? nil : footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section > 0 && !self.prefSectionsVisibility[1].boolValue) return 0.01;
    return UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    NSDictionary *item = [self prefContentForIndex:indexPath.section][indexPath.row];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if(indexPath.section == 0) {
        if (indexPath.row == 0) {
            return;
        } else if (indexPath.row <= self.keyLayoutFiles.count) {
            NSString *fileName = self.keyLayoutFiles[indexPath.row - 1];
            setPrefObject(@"control.default_ctrl", fileName);
            self.currentFileName = fileName.stringByDeletingPathExtension;
            [self openKeyLayoutEditor];
        } else if (indexPath.row == self.keyLayoutFiles.count + 1) {
            [self exportKeyLayout];
        } else {
            [self importKeyLayout];
        }
    } else if(indexPath.section == 3) {
        setPrefObject(@"control.controller_type", self.prefControllerTypes[indexPath.row][@"name"]);
        NSIndexSet *section = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)];
        [self.tableView reloadSections:section withRowAnimation:UITableViewRowAnimationNone];
    }
    // 1 and 2 handle themselves with picker views.
}

- (void)toggleFluidButtonSlide:(UISwitch *)sender {
    setPrefBool(@"control.fluid_button_slide", sender.isOn);
    [NSNotificationCenter.defaultCenter
        postNotificationName:@"FluidButtonSlidePreferenceDidChangeNotification"
                      object:nil];
}

#pragma mark Key layout editor

- (void)openKeyLayoutEditor {
    CustomControlsViewController *editor =
        [[CustomControlsViewController alloc] init];
    editor.modalPresentationStyle = UIModalPresentationOverFullScreen;
    editor.setDefaultCtrl = ^(NSString *name) {
        setPrefObject(@"control.default_ctrl", name);
    };
    editor.getDefaultCtrl = ^{
        return getPrefObject(@"control.default_ctrl");
    };
    [self presentViewController:editor animated:YES completion:nil];
}

#pragma mark Key layout import and export

- (NSString *)currentKeyLayoutPath {
    NSString *fileName = getPrefObject(@"control.default_ctrl");
    if (fileName.length == 0) {
        fileName = @"default.json";
    }
    return [NSString stringWithFormat:@"%s/controlmap/%@", getenv("POJAV_HOME"), fileName];
}

- (void)exportKeyLayout {
    NSURL *fileURL = [NSURL fileURLWithPath:[self currentKeyLayoutPath]];
    if (![NSFileManager.defaultManager fileExistsAtPath:fileURL.path]) {
        showDialog(localize(@"无法导出键位", nil), localize(@"当前键位文件不存在，请先在键位编辑器中保存。", nil));
        return;
    }

    self.importingKeyLayout = NO;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importKeyLayout {
    self.importingKeyLayout = YES;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!self.importingKeyLayout || urls.count == 0) {
        return;
    }
    self.importingKeyLayout = NO;

    NSURL *sourceURL = urls.firstObject;
    BOOL securityScoped = [sourceURL startAccessingSecurityScopedResource];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:sourceURL options:0 error:&error];
    if (securityScoped) {
        [sourceURL stopAccessingSecurityScopedResource];
    }
    if (data == nil) {
        showDialog(localize(@"无法导入键位", nil), error.localizedDescription ?: localize(@"无法读取所选文件。", nil));
        return;
    }

    NSMutableDictionary *layout =
        [NSJSONSerialization JSONObjectWithData:data
                                        options:NSJSONReadingMutableContainers
                                          error:&error];
    if (![layout isKindOfClass:NSMutableDictionary.class]) {
        showDialog(localize(@"无法导入键位", nil), error.localizedDescription ?: localize(@"所选文件不是有效的键位 JSON。", nil));
        return;
    }
    if (!convertLayoutIfNecessary(layout)) {
        return;
    }

    NSString *fileName = sourceURL.lastPathComponent;
    if (![fileName.pathExtension.lowercaseString isEqualToString:@"json"]) {
        fileName = [fileName stringByAppendingPathExtension:@"json"];
    }
    NSString *controlMapDirectory =
        [NSString stringWithFormat:@"%s/controlmap", getenv("POJAV_HOME")];
    [NSFileManager.defaultManager createDirectoryAtPath:controlMapDirectory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:&error];
    NSData *normalizedData =
        [NSJSONSerialization dataWithJSONObject:layout
                                        options:NSJSONWritingPrettyPrinted
                                          error:&error];
    NSString *destinationPath =
        [controlMapDirectory stringByAppendingPathComponent:fileName];
    if (normalizedData == nil ||
        ![normalizedData writeToFile:destinationPath options:NSDataWritingAtomic error:&error]) {
        showDialog(localize(@"无法导入键位", nil), error.localizedDescription ?: localize(@"保存键位文件失败。", nil));
        return;
    }

    setPrefObject(@"control.default_ctrl", fileName);
    [self reloadKeyLayoutFiles];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
    showDialog(localize(@"键位导入成功", nil),
        [NSString stringWithFormat:localize(@"“%@”已设为当前键位。", nil), fileName.stringByDeletingPathExtension]);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.importingKeyLayout = NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
        editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 ||
        indexPath.row == 0 || indexPath.row > self.keyLayoutFiles.count ||
        [self.keyLayoutFiles[indexPath.row - 1] isEqualToString:@"default.json"]) {
        return UITableViewCellEditingStyleNone;
    }
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView
        commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
         forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete ||
        indexPath.section != 0 ||
        indexPath.row == 0 || indexPath.row > self.keyLayoutFiles.count) {
        return;
    }

    NSString *fileName = self.keyLayoutFiles[indexPath.row - 1];
    NSString *path = [NSString stringWithFormat:
        @"%s/controlmap/%@", getenv("POJAV_HOME"), fileName];
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
        showDialog(localize(@"无法删除键位", nil), error.localizedDescription);
        return;
    }
    if ([fileName isEqualToString:getPrefObject(@"control.default_ctrl")]) {
        setPrefObject(@"control.default_ctrl", @"default.json");
    }
    [self reloadKeyLayoutFiles];
    [tableView deleteRowsAtIndexPaths:@[indexPath]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark UITextField + UIPickerView

- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view
{
    UILabel *label = (UILabel *)view;
    if (label == nil) {
        label = [UILabel new];
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.5;
        label.textAlignment = NSTextAlignmentCenter;
    }
    label.text = [self pickerView:pickerView titleForRow:row forComponent:component];

    return label;
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    self.activeTextField.text = [self.keyCodeMap objectAtIndex:row];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)thePickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return self.keyCodeMap.count;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return [self.keyCodeMap objectAtIndex:row];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    self.activeTextField = textField;
    [self.editPickMapping selectRow:[self.keyCodeMap indexOfObject:textField.text] inComponent:0 animated:NO];
}
- (void)textFieldDidEndEditing:(UITextField *)textField
{
    UITableViewCell *cell = (UITableViewCell *)textField.superview;
    NSMutableDictionary *item = objc_getAssociatedObject(cell.accessoryView, @"item");
    if(![textField.text hasPrefix:@"SPECIALBTN"]) {
        item[@"keycode"] = self.keycodePlist[[@"GLFW_KEY_" stringByAppendingString:textField.text]];
    } else {
        item[@"keycode"] = self.keycodePlist[textField.text];
    }
    self.activeTextField = nil;
}

- (void)closeTextField:(UIBarButtonItem *)sender {
    [self.activeTextField endEditing:YES];
}

#pragma mark UI

- (void) dismissModalViewController {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)actionOpenFilePicker:(void (^)(NSString *name))handler {
    FileListViewController *vc = [[FileListViewController alloc] init];
    vc.listPath = [NSString stringWithFormat:@"%s/controlmap/gamepads", getenv("POJAV_HOME")];
    
    vc.whenItemSelected = handler;
    vc.modalPresentationStyle = UIModalPresentationPopover;
    vc.preferredContentSize = CGSizeMake(350, 250);

    UIPopoverPresentationController *popoverController = [vc popoverPresentationController];
    popoverController.sourceView = self.tableView;
    popoverController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    popoverController.delegate = self;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)actionMenuLoad {
    [self actionOpenFilePicker:^void(NSString* name) {
        NSString *currentFile = [NSString stringWithFormat:@"%@.json", getPrefObject(@"control.default_gamepad_ctrl")];
        if(![currentFile isEqualToString:name]) {
            setPrefObject(@"control.default_gamepad_ctrl", [NSString stringWithFormat:@"%@.json", name]);
            [self loadGamepadConfigurationFile];
            [self.tableView reloadData];
        }
    }];
}

- (void)actionMenuSaveWithExit:(BOOL)exit {
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:localize(@"custom_controls.control_menu.save", nil)
        message:exit?localize(@"custom_controls.control_menu.exit.warn", nil):@""
        preferredStyle:UIAlertControllerStyleAlert];
    [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = localize(@"localization.field.name", nil);
        textField.text = self.currentFileName;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *textFields = controller.textFields;
        UITextField *field = textFields[0];
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.currentMappings options:NSJSONWritingPrettyPrinted error:&error];
        if (jsonData == nil) {
            showDialog(localize(@"custom_controls.control_menu.save.error.json", nil), error.localizedDescription);
            return;
        }
        BOOL success = [jsonData writeToFile:[NSString stringWithFormat:@"%s/controlmap/gamepads/%@.json", getenv("POJAV_HOME"), field.text] options:NSDataWritingAtomic error:&error];
        if (!success) {
            showDialog(localize(@"custom_controls.control_menu.save.error.write", nil), error.localizedDescription);
            return;
        }

        if (exit) {
            [self dismissModalViewController];
        }

        setPrefObject(@"control.default_gamepad_ctrl", [NSString stringWithFormat:@"%@.json", field.text]);
    }]];
    if (exit) {
        [controller addAction:[UIAlertAction actionWithTitle:localize(@"custom_controls.control_menu.discard_changes", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self dismissModalViewController];
        }]];
    }
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)actionMenuSave {
    [self actionMenuSaveWithExit:NO];
}

- (void)exitButtonSelector {
    NSString *gamepadPath = [NSString stringWithFormat:@"%s/controlmap/gamepads/%@", getenv("POJAV_HOME"), getPrefObject(@"control.default_gamepad_ctrl")];
    if([self.currentMappings isEqualToDictionary:parseJSONFromFile(gamepadPath)]) {
        [self dismissModalViewController];
    } else {
        [self actionMenuSaveWithExit:YES];
    }
}

@end
