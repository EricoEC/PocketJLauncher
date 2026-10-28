#import <UIKit/UIKit.h>

@interface PocketJStartupOverlay : UIView
@property(nonatomic, copy) void (^openLog)(void);
@property(nonatomic, copy) void (^exportLog)(UIView *source);
- (void)start;
- (void)stop;
@end

