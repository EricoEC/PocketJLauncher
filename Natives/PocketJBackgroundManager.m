#import "PocketJBackgroundManager.h"

NSNotificationName const PocketJBackgroundDidChangeNotification = @"PocketJBackgroundDidChangeNotification";
static NSInteger const PocketJBackgroundImageViewTag = 0x504A4247;
static NSString *const PocketJBackgroundOpacityKey = @"PocketJBackgroundOpacity";

@implementation PocketJBackgroundManager

+ (instancetype)shared {
    static PocketJBackgroundManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [PocketJBackgroundManager new]; });
    return manager;
}

- (NSString *)path {
    NSString *library = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *folder = [library stringByAppendingPathComponent:@"PocketJAppearance"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder stringByAppendingPathComponent:@"launcher-background.jpg"];
}

- (UIImage *)image { return [UIImage imageWithContentsOfFile:self.path]; }
- (BOOL)enabled { return self.image != nil; }
- (CGFloat)opacity {
    CGFloat value = [NSUserDefaults.standardUserDefaults floatForKey:PocketJBackgroundOpacityKey];
    return value > 0.0 ? value : 1.0;
}
- (void)setOpacity:(CGFloat)opacity {
    [NSUserDefaults.standardUserDefaults setFloat:MAX(0.15, MIN(opacity, 1.0)) forKey:PocketJBackgroundOpacityKey];
    [self notify];
}

- (BOOL)setBackgroundImage:(UIImage *)image error:(NSError **)error {
    NSData *data = UIImageJPEGRepresentation(image, 0.9);
    BOOL ok = data && [data writeToFile:self.path options:NSDataWritingAtomic error:error];
    if (ok) [self notify];
    return ok;
}

- (void)clearBackground {
    [NSFileManager.defaultManager removeItemAtPath:self.path error:nil];
    [self notify];
}

- (void)notify {
    [NSNotificationCenter.defaultCenter postNotificationName:PocketJBackgroundDidChangeNotification object:self];
}

- (void)applyToView:(UIView *)view {
    [[view viewWithTag:PocketJBackgroundImageViewTag] removeFromSuperview];
    UIImage *image = self.image;
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *tableView = (UITableView *)view;
        if (!image) {
            tableView.backgroundView = nil;
            tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
            return;
        }
        UIImageView *background = [[UIImageView alloc] initWithImage:image];
        background.tag = PocketJBackgroundImageViewTag;
        background.contentMode = UIViewContentModeScaleAspectFill;
        background.clipsToBounds = YES;
        background.alpha = self.opacity;
        tableView.backgroundView = background;
        tableView.backgroundColor = UIColor.clearColor;
        return;
    }
    if ([view isKindOfClass:UICollectionView.class]) {
        UICollectionView *collectionView = (UICollectionView *)view;
        if (!image) {
            collectionView.backgroundView = nil;
            collectionView.backgroundColor = UIColor.systemGroupedBackgroundColor;
            return;
        }
        UIImageView *background = [[UIImageView alloc] initWithImage:image];
        background.tag = PocketJBackgroundImageViewTag;
        background.contentMode = UIViewContentModeScaleAspectFill;
        background.clipsToBounds = YES;
        background.alpha = self.opacity;
        collectionView.backgroundView = background;
        collectionView.backgroundColor = UIColor.clearColor;
        return;
    }
    if (!image) {
        view.backgroundColor = UIColor.systemGroupedBackgroundColor;
        return;
    }
    view.backgroundColor = UIColor.clearColor;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.tag = PocketJBackgroundImageViewTag;
    imageView.frame = view.bounds;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.alpha = self.opacity;
    [view insertSubview:imageView atIndex:0];
}

@end
