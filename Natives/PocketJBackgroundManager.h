#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const PocketJBackgroundDidChangeNotification;

@interface PocketJBackgroundManager : NSObject
@property(class, nonatomic, readonly) PocketJBackgroundManager *shared;
@property(nonatomic, readonly, nullable) UIImage *image;
@property(nonatomic) CGFloat opacity;
@property(nonatomic, readonly) BOOL enabled;
- (BOOL)setBackgroundImage:(UIImage *)image error:(NSError **)error;
- (void)clearBackground;
- (void)applyToView:(UIView *)view;
@end

NS_ASSUME_NONNULL_END
