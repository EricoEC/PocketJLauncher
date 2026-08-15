#import <UIKit/UIKit.h>

@interface PickTextField : UITextField
/// Present this picker as a native medium sheet on compact-width iPhone
/// instead of using the iOS 26 Liquid Glass popover adaptation.
@property(nonatomic) BOOL prefersMediumSheet;
- (void)setupDoneButtonWithTarget:(id)target action:(SEL)action;
@end
