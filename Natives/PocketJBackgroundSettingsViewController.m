#import "PocketJBackgroundSettingsViewController.h"
#import "PocketJBackgroundManager.h"
#import "ModernUITheme.h"
#import "utils.h"
#import "ios_uikit_bridge.h"

@implementation PocketJBackgroundSettingsViewController

- (UIImage *)cropImage:(UIImage *)image toDeviceAspectForView:(UIView *)view {
    CGSize target = view.window.screen.bounds.size;
    if (target.width <= 0 || target.height <= 0) target = UIScreen.mainScreen.bounds.size;
    CGFloat targetAspect = target.width / target.height;
    CGSize source = image.size;
    CGFloat sourceAspect = source.width / source.height;
    CGRect crop = CGRectMake(0, 0, source.width, source.height);
    if (sourceAspect > targetAspect) {
        crop.size.width = source.height * targetAspect;
        crop.origin.x = (source.width - crop.size.width) * 0.5;
    } else {
        crop.size.height = source.width / targetAspect;
        crop.origin.y = (source.height - crop.size.height) * 0.5;
    }
    CGImageRef cgImage = CGImageCreateWithImageInRect(image.CGImage, crop);
    if (!cgImage) return image;
    UIImage *result = [UIImage imageWithCGImage:cgImage scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(cgImage);
    return result;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"启动器背景", nil);
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section ? 2 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section ? localize(@"显示效果", nil) : localize(@"自定义图片", nil);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section ? localize(@"自定义背景只改变启动器内容背景，不会更改应用图标。", nil) :
        localize(@"选择图片后会按当前 iPhone 或 iPad 的屏幕比例居中裁剪。", nil);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (indexPath.section == 0) {
        cell.textLabel.text = PocketJBackgroundManager.shared.enabled ? localize(@"更换背景图片", nil) : localize(@"选择背景图片", nil);
        cell.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.row == 0) {
        cell.textLabel.text = localize(@"背景透明度", nil);
        UISlider *slider = [UISlider new]; slider.frame = CGRectMake(0, 0, 150, 30);
        // This control describes transparency, while UIImageView uses opacity.
        // Right means more transparent; left means more opaque.
        slider.minimumValue = 0.0; slider.maximumValue = 0.85;
        slider.value = 1.0 - PocketJBackgroundManager.shared.opacity;
        [slider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = slider;
    } else {
        cell.textLabel.text = localize(@"恢复系统背景", nil);
        cell.textLabel.textColor = UIColor.systemRedColor;
        cell.imageView.image = [UIImage systemImageNamed:@"arrow.counterclockwise"];
    }
    [ModernUITheme styleCell:cell destructive:indexPath.section == 1 && indexPath.row == 1];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        picker.allowsEditing = NO;
        picker.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
        picker.popoverPresentationController.sourceRect = [tableView cellForRowAtIndexPath:indexPath].bounds;
        [self presentViewController:picker animated:YES completion:nil];
    } else if (indexPath.row == 1) {
        [PocketJBackgroundManager.shared clearBackground];
        [self.tableView reloadData];
    }
}
- (void)opacityChanged:(UISlider *)sender { PocketJBackgroundManager.shared.opacity = 1.0 - sender.value; }
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *source = info[UIImagePickerControllerOriginalImage];
    UIImage *image = source ? [self cropImage:source toDeviceAspectForView:self.view] : nil;
    NSError *error;
    if (image && ![PocketJBackgroundManager.shared setBackgroundImage:image error:&error]) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
    }
    [picker dismissViewControllerAnimated:YES completion:^{ [self.tableView reloadData]; }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }

@end
