#import <UIKit/UIKit.h>
@interface PocketJTouchController : NSObject
@property(nonatomic,readonly) BOOL ready;
@property(nonatomic,copy) void (^keyboardHandler)(BOOL visible);
@property(nonatomic,copy) void (^readyHandler)(void);
- (instancetype)initWithMode:(NSString *)mode;
- (void)poll;
- (BOOL)routeTouches:(NSSet<UITouch *> *)touches view:(UIView *)view ended:(BOOL)ended;
- (void)releasePointers;
@end
