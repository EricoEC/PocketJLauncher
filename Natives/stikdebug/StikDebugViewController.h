#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, PocketJJITSetupState) {
    PocketJJITSetupStateUnavailable,
    PocketJJITSetupStateWaitingConfiguration,
    PocketJJITSetupStateReady,
    PocketJJITSetupStateEnabled,
};

@interface StikDebugViewController : UITableViewController
    <UIDocumentPickerDelegate>
+ (PocketJJITSetupState)setupState;
+ (void)enableEmbeddedJITWithCompletion:
    (void (^)(BOOL success, NSString *message))completion;
@end
