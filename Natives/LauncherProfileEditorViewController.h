#import <UIKit/UIKit.h>
#import "PLPrefTableViewController.h"

@interface LauncherProfileEditorViewController : PLPrefTableViewController
@property(nonatomic) NSMutableDictionary* profile;
/// The directory name under POJAV_HOME/instances. It is the canonical,
/// read-only instance name shown by the editor.
@property(nonatomic, copy) NSString *instanceName;
@property(nonatomic, copy) BOOL (^renameInstance)(
    NSString *oldName, NSString *newName, NSString **errorMessage);
/// Fabric/Quilt already chose its Minecraft version in the installer.
/// Hide the duplicate picker only for that initial creation flow.
@property(nonatomic) BOOL hidesMinecraftVersion;
@property(nonatomic) BOOL creatingNewInstance;
@property(nonatomic, copy) dispatch_block_t cancelCreation;
@property(nonatomic, copy) dispatch_block_t creationDidFinish;
@property(nonatomic, copy) void (^loaderInstallationRequested)(
    NSString *loader, NSString *minecraftVersion);
@end
