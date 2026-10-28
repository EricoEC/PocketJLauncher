#import <Foundation/Foundation.h>
@interface PocketJArchiveService : NSObject
+ (BOOL)validateArchive:(NSString *)path error:(NSError **)error;
+ (BOOL)installWorld:(NSURL *)archive saves:(NSString *)saves name:(NSString *)name error:(NSError **)error;
+ (NSURL *)exportWorld:(NSString *)path error:(NSError **)error;
/// Formats: zip, mrpack, curseforge, multimc, links. Only game files and
/// allowlisted manifest fields are exported; no account/keychain/pairing data.
+ (NSURL *)exportInstance:(NSString *)path name:(NSString *)name format:(NSString *)format error:(NSError **)error;
@end
