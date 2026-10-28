#import <UIKit/UIKit.h>
@interface PocketJModVersionPickerViewController : UITableViewController
@property(nonatomic, copy) NSString *projectTitle;
@property(nonatomic, strong) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) void (^selectionHandler)(NSDictionary *item);
@end
