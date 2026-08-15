#import <AuthenticationServices/AuthenticationServices.h>
#import <objc/runtime.h>

#import "authenticator/BaseAuthenticator.h"
#import "AccountListViewController.h"
#import "AFNetworking.h"
#import "LauncherPreferences.h"
#import "ModernUITheme.h"
#import "UIImageView+AFNetworking.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface AccountListViewController()<ASWebAuthenticationPresentationContextProviding>

@property(nonatomic, strong) NSMutableArray *accountList;
@property(nonatomic) ASWebAuthenticationSession *authVC;

@end

static UIImage *PLCropSkinTile(CGImageRef source, CGFloat unit,
                               CGFloat x, CGFloat y) {
    CGImageRef tile = CGImageCreateWithImageInRect(
        source, CGRectMake(x * unit, y * unit, 8 * unit, 8 * unit));
    if (!tile) return nil;
    UIImage *image = [UIImage imageWithCGImage:tile scale:1
                                   orientation:UIImageOrientationUp];
    CGImageRelease(tile);
    return image;
}

static void PLDrawSkinTile(CGContextRef context, UIImage *tile,
                           CGPoint topLeft, CGPoint topRight,
                           CGPoint bottomLeft, CGFloat shade) {
    if (!context || !tile) return;
    CGPoint bottomRight = CGPointMake(
        topRight.x + bottomLeft.x - topLeft.x,
        topRight.y + bottomLeft.y - topLeft.y);
    UIBezierPath *face = [UIBezierPath bezierPath];
    [face moveToPoint:topLeft];
    [face addLineToPoint:topRight];
    [face addLineToPoint:bottomRight];
    [face addLineToPoint:bottomLeft];
    [face closePath];

    CGContextSaveGState(context);
    CGContextSetAllowsAntialiasing(context, NO);
    CGContextSetShouldAntialias(context, NO);
    [face addClip];
    CGAffineTransform transform = CGAffineTransformMake(
        (topRight.x - topLeft.x) / 8.0,
        (topRight.y - topLeft.y) / 8.0,
        (bottomLeft.x - topLeft.x) / 8.0,
        (bottomLeft.y - topLeft.y) / 8.0,
        topLeft.x, topLeft.y);
    CGContextConcatCTM(context, transform);
    [tile drawInRect:CGRectMake(0, 0, 8, 8)];
    CGContextRestoreGState(context);

    if (shade > 0) {
        CGContextSaveGState(context);
        CGContextSetAllowsAntialiasing(context, NO);
        CGContextSetShouldAntialias(context, NO);
        [face addClip];
        [[UIColor colorWithWhite:0 alpha:shade] setFill];
        UIRectFillUsingBlendMode(face.bounds, kCGBlendModeSourceAtop);
        CGContextRestoreGState(context);
    }
}

@implementation AccountListViewController

+ (UIImage *)normalizedAvatar:(UIImage *)image {
    if (!image) return nil;
    const CGFloat side = 40.0;
    CGSize source = image.size;
    if (source.width <= 0 || source.height <= 0) return image;
    CGFloat scale = MIN(side / source.width, side / source.height);
    CGSize drawSize =
        CGSizeMake(source.width * scale, source.height * scale);
    CGRect drawRect = CGRectMake((side - drawSize.width) / 2.0,
        (side - drawSize.height) / 2.0, drawSize.width, drawSize.height);
    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                               format:format];
    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *context) {
            CGContextSetInterpolationQuality(context.CGContext,
                                              kCGInterpolationNone);
            [image drawInRect:drawRect];
        }];
}

+ (NSString *)avatarCachePathForIdentity:(NSString *)identity {
    NSString *key = identity.length ? identity : @"account";
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    NSMutableString *safe = [NSMutableString string];
    for (NSUInteger index = 0; index < key.length; index++) {
        unichar character = [key characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [safe appendFormat:@"%C", character];
        } else {
            [safe appendString:@"_"];
        }
    }
    NSString *directory = [NSString stringWithFormat:
        @"%s/accounts/avatars", getenv("POJAV_HOME")];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:
        [[safe stringByAppendingString:@"_minecraft_3d"]
            stringByAppendingPathExtension:@"png"]];
}

+ (NSString *)legacyAvatarCachePathForIdentity:(NSString *)identity {
    NSString *path = [self avatarCachePathForIdentity:identity];
    return [path stringByReplacingOccurrencesOfString:@"_minecraft_3d.png"
                                           withString:@"_minecraft.png"];
}

+ (NSString *)oldOfficialAvatarCachePathForIdentity:(NSString *)identity {
    NSString *path = [self avatarCachePathForIdentity:identity];
    return [path stringByReplacingOccurrencesOfString:@"_minecraft_3d.png"
                                           withString:@"_official.png"];
}

+ (NSString *)avatarCachePathForAccount:(NSDictionary *)account {
    return [self avatarCachePathForIdentity:
        [BaseAuthenticator storageKeyForAuthData:account]];
}

+ (NSArray<NSString *> *)avatarCacheIdentitiesForAccount:(NSDictionary *)account {
    NSMutableOrderedSet<NSString *> *identities = [NSMutableOrderedSet orderedSet];
    NSString *storageKey = [BaseAuthenticator storageKeyForAuthData:account];
    if (storageKey.length) [identities addObject:storageKey];
    for (NSString *field in @[@"xuid", @"profileId", @"username", @"oldusername"]) {
        NSString *value = account[field];
        if (![value isKindOfClass:NSString.class] || value.length == 0) continue;
        [identities addObject:value];
        [identities addObject:[@"microsoft__" stringByAppendingString:value]];
        [identities addObject:[@"local__" stringByAppendingString:value]];
    }
    return identities.array;
}

+ (UIImage *)cachedAvatarForAccount:(NSDictionary *)account {
    NSString *canonicalPath = [self avatarCachePathForAccount:account];
    for (NSString *identity in [self avatarCacheIdentitiesForAccount:account]) {
        NSArray *paths = @[
            [self avatarCachePathForIdentity:identity],
            [self legacyAvatarCachePathForIdentity:identity],
            [self oldOfficialAvatarCachePathForIdentity:identity]
        ];
        for (NSString *candidatePath in paths) {
            NSData *data = [NSData dataWithContentsOfFile:candidatePath];
            UIImage *avatar = data ? [UIImage imageWithData:data] : nil;
            if (!avatar) continue;
            avatar = [self normalizedAvatar:avatar];
            // Only migrate another identity's 3D cache. Old flat avatars stay
            // as an offline fallback until a fresh skin produces a 3D head.
            if (![candidatePath isEqualToString:canonicalPath] &&
                [candidatePath hasSuffix:@"_minecraft_3d.png"]) {
                NSData *png = UIImagePNGRepresentation(avatar);
                if (png.length) {
                    [png writeToFile:canonicalPath options:NSDataWritingAtomic error:nil];
                }
            }
            return avatar;
        }
    }
    return nil;
}

+ (void)cacheAvatar:(UIImage *)image forAccount:(NSDictionary *)account {
    image = [self normalizedAvatar:image];
    NSData *png = image ? UIImagePNGRepresentation(image) : nil;
    if (png.length > 0 && account) {
        [png writeToFile:[self avatarCachePathForAccount:account]
                 options:NSDataWritingAtomic error:nil];
    }
}

- (NSDictionary *)accountForStorageKey:(NSString *)storageKey {
    for (NSDictionary *account in self.accountList) {
        if ([[self accountKey:account] isEqualToString:storageKey]) {
            return account;
        }
    }
    return nil;
}

+ (UIImage *)minecraftHeadFromSkin:(UIImage *)skin {
    CGImageRef source = skin.CGImage;
    if (!source || CGImageGetWidth(source) < 64 ||
        CGImageGetHeight(source) < 32) {
        return skin;
    }

    CGFloat unit = (CGFloat)CGImageGetWidth(source) / 64.0;
    UIImage *top = PLCropSkinTile(source, unit, 8, 0);
    UIImage *front = PLCropSkinTile(source, unit, 8, 8);
    UIImage *right = PLCropSkinTile(source, unit, 0, 8);
    UIImage *hatTop = PLCropSkinTile(source, unit, 40, 0);
    UIImage *hatFront = PLCropSkinTile(source, unit, 40, 8);
    UIImage *hatRight = PLCropSkinTile(source, unit, 32, 8);
    if (!top || !front || !right) return skin;

    // Isometric cube matching the common launcher avatar: top, front and
    // right faces remain crisp, while the translucent hat layer sits slightly
    // outside the base head instead of being flattened into the face.
    CGSize outputSize = CGSizeMake(51, 51);
    UIGraphicsBeginImageContextWithOptions(outputSize, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextSetAllowsAntialiasing(context, NO);
    CGContextSetShouldAntialias(context, NO);

    PLDrawSkinTile(context, top,
        CGPointMake(3, 12), CGPointMake(25, 2), CGPointMake(25, 22), 0.02);
    PLDrawSkinTile(context, right,
        CGPointMake(25, 22), CGPointMake(47, 12), CGPointMake(25, 48), 0.16);
    PLDrawSkinTile(context, front,
        CGPointMake(3, 12), CGPointMake(25, 22), CGPointMake(3, 38), 0.03);

    PLDrawSkinTile(context, hatTop,
        CGPointMake(1, 11), CGPointMake(25, 0),
        CGPointMake(25, 23), 0.02);
    PLDrawSkinTile(context, hatRight,
        CGPointMake(25, 23), CGPointMake(49, 12),
        CGPointMake(25, 50), 0.16);
    PLDrawSkinTile(context, hatFront,
        CGPointMake(1, 11), CGPointMake(25, 23),
        CGPointMake(1, 38), 0.03);

    UIImage *head = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return head ?: skin;
}

+ (void)loadBestAvatarForAccount:(NSDictionary *)account
                      completion:(void (^)(UIImage *avatar))completion {
    UIImage *cached = [self cachedAvatarForAccount:account];
    if (cached && completion) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
    }
    void (^deliver)(UIImage *) = ^(UIImage *image) {
        if (!image) return;
        image = [self normalizedAvatar:image];
        [self cacheAvatar:image forAccount:account];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(image);
        });
    };
    void (^loadSkin)(NSString *) = ^(NSString *skinURL) {
        skinURL = [self secureSkinURL:skinURL];
        NSURL *url = [NSURL URLWithString:skinURL];
        if (!url) return;
        [[[NSURLSession sharedSession] dataTaskWithURL:url
            completionHandler:^(NSData *data, NSURLResponse *response,
                                NSError *error) {
                UIImage *skin = data ? [UIImage imageWithData:data] : nil;
                UIImage *head = skin ? [self minecraftHeadFromSkin:skin] : nil;
                if (head) deliver(head);
            }] resume];
    };

    NSString *savedSkinURL = account[@"skinTextureURL"];
    NSString *profileId = [account[@"profileId"]
        stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (profileId.length != 32) {
        loadSkin(savedSkinURL);
        return;
    }

    // Refresh the official Minecraft skin on every launcher session. Failure
    // never touches the on-disk avatar; the saved skin URL remains a fallback.
    NSURL *profileURL = [NSURL URLWithString:[NSString stringWithFormat:
        @"https://sessionserver.mojang.com/session/minecraft/profile/%@",
        profileId]];
    [[[NSURLSession sharedSession] dataTaskWithURL:profileURL
        completionHandler:^(NSData *data, NSURLResponse *response,
                            NSError *error) {
            NSDictionary *profile = data ? [NSJSONSerialization
                JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *encoded = nil;
            for (NSDictionary *property in profile[@"properties"]) {
                if ([property[@"name"] isEqualToString:@"textures"]) {
                    encoded = property[@"value"];
                    break;
                }
            }
            NSData *decoded = [[NSData alloc]
                initWithBase64EncodedString:encoded ?: @""
                options:NSDataBase64DecodingIgnoreUnknownCharacters];
            NSDictionary *textures = decoded ? [NSJSONSerialization
                JSONObjectWithData:decoded options:0 error:nil] : nil;
            NSString *freshSkinURL = textures[@"textures"][@"SKIN"][@"url"];
            if (freshSkinURL.length) {
                loadSkin(freshSkinURL);
            } else {
                loadSkin(savedSkinURL);
            }
        }] resume];
}

+ (NSString *)secureSkinURL:(NSString *)skinURL {
    if (skinURL.length == 0) {
        return nil;
    }
    return [skinURL stringByReplacingOccurrencesOfString:@"http://"
                                              withString:@"https://"];
}

- (void)loadSkinURL:(NSString *)skinURL
            forCell:(UITableViewCell *)cell
         accountKey:(NSString *)accountKey
        placeholder:(UIImage *)placeholder {
    NSString *secureURL = [AccountListViewController secureSkinURL:skinURL];
    NSURL *url = [NSURL URLWithString:secureURL];
    if (url == nil) {
        cell.imageView.image = placeholder;
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReturnCacheDataElseLoad
        timeoutInterval:15];
    __weak UITableViewCell *weakCell = cell;
    [cell.imageView setImageWithURLRequest:request
        placeholderImage:placeholder
        success:^(NSURLRequest *request, NSHTTPURLResponse *response,
                  UIImage *image) {
            UITableViewCell *strongCell = weakCell;
            if (strongCell &&
                [[objc_getAssociatedObject(strongCell,
                    @"AccountStorageKey") description]
                    isEqualToString:accountKey]) {
                strongCell.imageView.image =
                    [AccountListViewController normalizedAvatar:
                        [AccountListViewController minecraftHeadFromSkin:image]];
                [AccountListViewController
                    cacheAvatar:strongCell.imageView.image
                    forAccount:[self accountForStorageKey:accountKey]];
                [strongCell setNeedsLayout];
            }
        }
        failure:^(NSURLRequest *request, NSHTTPURLResponse *response,
                  NSError *error) {
            NSLog(@"[AccountAvatar] Failed to load official skin for %@: %@",
                accountKey, error.localizedDescription);
        }];
}

- (void)loadRenderedHeadURL:(NSString *)headURL
                    forCell:(UITableViewCell *)cell
                 accountKey:(NSString *)accountKey
                placeholder:(UIImage *)placeholder {
    NSURL *url = [NSURL URLWithString:headURL];
    if (url == nil) {
        cell.imageView.image = placeholder;
        return;
    }

    NSURLRequest *request = [NSURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReturnCacheDataElseLoad
        timeoutInterval:15];
    __weak UITableViewCell *weakCell = cell;
    [cell.imageView setImageWithURLRequest:request
        placeholderImage:placeholder
        success:^(NSURLRequest *request, NSHTTPURLResponse *response,
                  UIImage *image) {
            UITableViewCell *strongCell = weakCell;
            if (strongCell &&
                [[objc_getAssociatedObject(strongCell,
                    @"AccountStorageKey") description]
                    isEqualToString:accountKey]) {
                strongCell.imageView.image =
                    [AccountListViewController normalizedAvatar:image];
                [AccountListViewController cacheAvatar:image
                    forAccount:[self accountForStorageKey:accountKey]];
                [strongCell setNeedsLayout];
            }
        }
        failure:^(NSURLRequest *request, NSHTTPURLResponse *response,
                  NSError *error) {
            NSLog(@"[AccountAvatar] Failed to load rendered head for %@: %@",
                accountKey, error.localizedDescription);
        }];
}

- (void)fetchOfficialSkinForAccount:(NSMutableDictionary *)account
                                cell:(UITableViewCell *)cell
                          accountKey:(NSString *)accountKey
                         placeholder:(UIImage *)placeholder {
    NSString *profileId =
        [account[@"profileId"] stringByReplacingOccurrencesOfString:@"-"
                                                         withString:@""];
    if (profileId.length != 32) {
        cell.imageView.image = placeholder;
        return;
    }

    NSString *endpoint = [NSString stringWithFormat:
        @"https://sessionserver.mojang.com/session/minecraft/profile/%@",
        profileId];
    __weak typeof(self) weakSelf = self;
    [AFHTTPSessionManager.manager GET:endpoint parameters:nil headers:nil
        progress:nil
        success:^(NSURLSessionDataTask *task, NSDictionary *response) {
            NSString *encodedTextures = nil;
            for (NSDictionary *property in response[@"properties"]) {
                if ([property[@"name"] isEqualToString:@"textures"]) {
                    encodedTextures = property[@"value"];
                    break;
                }
            }
            NSData *decoded = [[NSData alloc]
                initWithBase64EncodedString:encodedTextures ?: @""
                options:NSDataBase64DecodingIgnoreUnknownCharacters];
            NSDictionary *textures = decoded
                ? [NSJSONSerialization JSONObjectWithData:decoded
                    options:0 error:nil] : nil;
            NSString *skinURL =
                textures[@"textures"][@"SKIN"][@"url"];
            skinURL = [AccountListViewController secureSkinURL:skinURL];
            if (skinURL.length == 0) {
                return;
            }

            account[@"skinTextureURL"] = skinURL;
            NSMutableDictionary *savedAccount = account.mutableCopy;
            [savedAccount removeObjectForKey:@"_sourceFile"];
            NSString *path = [NSString stringWithFormat:
                @"%s/accounts/%@.json", getenv("POJAV_HOME"), accountKey];
            NSError *saveError = saveJSONToFile(savedAccount, path);
            if (saveError) {
                NSLog(@"[AccountAvatar] Failed to cache skin URL for %@: %@",
                    accountKey, saveError.localizedDescription);
            }
            [weakSelf loadSkinURL:skinURL forCell:cell
                accountKey:accountKey placeholder:placeholder];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSLog(@"[AccountAvatar] Failed to fetch official profile for %@: %@",
                accountKey, error.localizedDescription);
        }];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }

    // List accounts
    NSString *listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:listPath error:nil];
    for(NSString *file in files) {
        NSString *path = [listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if(!isDir && [file hasSuffix:@".json"]) {
            NSMutableDictionary *account =
                [parseJSONFromFile(path) mutableCopy];
            if (account[@"NSErrorObject"]) {
                continue;
            }
            NSString *storageKey =
                [BaseAuthenticator storageKeyForAuthData:account];
            account[@"storageKey"] = storageKey;
            account[@"accountType"] =
                [storageKey hasPrefix:@"microsoft__"]
                    ? @"microsoft" : @"local";
            account[@"_sourceFile"] = file;
            [self addOrReplaceAccount:account];
        }
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.title = localize(@"账户", nil);
    [ModernUITheme styleController:self];
    [ModernUITheme styleTableView:self.tableView];
}

- (NSString *)accountKey:(NSDictionary *)account {
    return account[@"storageKey"] ?:
        [BaseAuthenticator storageKeyForAuthData:account];
}

- (void)addOrReplaceAccount:(NSDictionary *)account {
    NSString *storageKey = [self accountKey:account];
    if ([storageKey hasPrefix:@"microsoft__"]) {
        NSIndexSet *stale = [self.accountList indexesOfObjectsPassingTest:
            ^BOOL(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
                NSString *candidateKey = [self accountKey:candidate];
                if ([candidateKey isEqualToString:storageKey]) return NO;
                BOOL candidateIsMicrosoft =
                    [candidateKey hasPrefix:@"microsoft__"] ||
                    [candidate[@"expiresAt"] longLongValue] > 0 ||
                    [candidate[@"xuid"] length] > 0 ||
                    [candidate[@"xboxGamertag"] length] > 0;
                if (!candidateIsMicrosoft) return NO;
                return ([account[@"xuid"] length] > 0 &&
                        [candidate[@"xuid"] isEqual:account[@"xuid"]]) ||
                    ([account[@"profileId"] length] > 0 &&
                        [candidate[@"profileId"] isEqual:account[@"profileId"]]) ||
                    ([account[@"oldusername"] length] > 0 &&
                        [candidate[@"username"] isEqual:account[@"oldusername"]]);
            }];
        if (stale.count) [self.accountList removeObjectsAtIndexes:stale];
    }
    NSUInteger existing = [self.accountList
        indexOfObjectPassingTest:
            ^BOOL(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
                return [[self accountKey:candidate]
                    isEqualToString:storageKey];
            }];
    if (existing == NSNotFound) {
        [self.accountList addObject:account];
        return;
    }

    // Prefer the new identity-keyed file over its legacy username copy.
    NSString *expectedFile =
        [storageKey stringByAppendingPathExtension:@"json"];
    if (!account[@"_sourceFile"] ||
        [account[@"_sourceFile"] isEqualToString:expectedFile]) {
        // Authentication refreshes can omit optional profile fields while
        // offline. Merge instead of replacing so the last valid avatar URL and
        // identity metadata survive until a newer valid response arrives.
        NSMutableDictionary *merged = [self.accountList[existing] mutableCopy];
        [merged addEntriesFromDictionary:account];
        self.accountList[existing] = merged;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(self.accountList.count, 1);
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? localize(@"账户", nil) : localize(@"添加账户", nil);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return localize(@"无需购买正版账号也可使用离线模式，游玩单人世界或允许离线验证的服务器；正版服务器和正版身份需要 Microsoft 账户，我们仍建议购买正版 Minecraft。", nil);
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0 && self.accountList.count == 0) {
        cell.imageView.image = [UIImage systemImageNamed:@"person.crop.circle.badge.plus"];
        cell.textLabel.text = localize(@"还没有账户", nil);
        cell.detailTextLabel.text = localize(@"离线账户无需微软登录，可立即创建。", nil);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [ModernUITheme styleCell:cell destructive:NO];
        return cell;
    }

    if (indexPath.section == 1) {
        BOOL offline = indexPath.row == 0;
        cell.imageView.image = [UIImage systemImageNamed:offline ? @"person.badge.plus" : @"globe"];
        cell.textLabel.text = offline ? localize(@"添加离线账户", nil) : localize(@"登录 Microsoft", nil);
        cell.detailTextLabel.text = offline ? localize(@"使用 Minecraft 用户名", nil) : localize(@"使用正版账户登录", nil);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        [ModernUITheme styleCell:cell destructive:NO];
        return cell;
    }

    NSDictionary *selected = self.accountList[indexPath.row];
    // By default, display the saved username
    cell.textLabel.text = selected[@"username"];
    if ([selected[@"username"] hasPrefix:@"Demo."]) {
        // Remove the prefix "Demo."
        cell.textLabel.text = [selected[@"username"] substringFromIndex:5];
        cell.detailTextLabel.text = localize(@"login.option.demo", nil);
    } else if ([[self accountKey:selected] hasPrefix:@"local__"]) {
        cell.detailTextLabel.text = localize(@"离线账户", nil);
    } else {
        NSString *gamertag = selected[@"xboxGamertag"];
        cell.detailTextLabel.text = gamertag.length
            ? [NSString stringWithFormat:localize(@"Microsoft 正版账户 · %@", nil), gamertag]
            : localize(@"Microsoft 正版账户", nil);
    }

    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    UIImage *placeholder =
        [AccountListViewController cachedAvatarForAccount:selected] ?:
        [UIImage imageNamed:@"DefaultAccount"];
    NSString *accountKey = [self accountKey:selected];
    objc_setAssociatedObject(cell, @"AccountStorageKey", accountKey,
        OBJC_ASSOCIATION_COPY_NONATOMIC);
    if ([accountKey hasPrefix:@"microsoft__"]) {
        cell.imageView.image = placeholder;
        [AccountListViewController loadBestAvatarForAccount:selected
            completion:^(UIImage *avatar) {
                if ([[objc_getAssociatedObject(cell, @"AccountStorageKey")
                        description] isEqualToString:accountKey]) {
                    cell.imageView.image = avatar;
                    [cell setNeedsLayout];
                }
            }];
    } else {
        NSString *profileURL = [selected[@"profilePicURL"]
            stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        [cell.imageView setImageWithURL:[NSURL URLWithString:profileURL]
            placeholderImage:placeholder];
    }

    NSString *selectedKey = getPrefObject(@"internal.selected_account");
    BOOL isCurrent =
        [[self accountKey:selected] isEqualToString:selectedKey] ||
        [selected[@"username"] isEqualToString:selectedKey];
    cell.accessoryType = isCurrent ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    [ModernUITheme styleCell:cell destructive:NO];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            [self actionLoginLocal:cell];
        } else {
            [self actionLoginMicrosoft:cell];
        }
        return;
    }
    if (self.accountList.count == 0) {
        return;
    }

    self.modalInPresentation = YES;
    self.tableView.userInteractionEnabled = NO;
    [self addActivityIndicatorTo:cell];

    id callback = ^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^(){
            [self callbackMicrosoftAuth:status success:success forCell:cell];
        });
    };
    [[BaseAuthenticator
        loadSavedName:[self accountKey:self.accountList[indexPath.row]]]
        refreshTokenWithCallback:callback];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 0 && self.accountList.count > 0) {
        // TODO: invalidate token

        NSDictionary *account = self.accountList[indexPath.row];
        NSString *storageKey = [self accountKey:account];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (self.whenDelete != nil) {
            self.whenDelete(storageKey);
        }
        NSString *xuid = account[@"xuid"];
        if (xuid) {
            [MicrosoftAuthenticator clearTokenDataOfProfile:xuid];
        }
        NSString *accountsPath =
            [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
        for (NSString *file in
                [fm contentsOfDirectoryAtPath:accountsPath error:nil]) {
            if (![file hasSuffix:@".json"]) {
                continue;
            }
            NSString *path =
                [accountsPath stringByAppendingPathComponent:file];
            NSDictionary *saved = parseJSONFromFile(path);
            if ([[BaseAuthenticator storageKeyForAuthData:saved]
                    isEqualToString:storageKey]) {
                [fm removeItemAtPath:path error:nil];
            }
        }
        [self.accountList removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section != 0 || self.accountList.count == 0) {
        return UITableViewCellEditingStyleNone;
    } else {
        return UITableViewCellEditingStyleDelete;
    }
}

- (NSDictionary *)parseQueryItems:(NSString *)url {
    NSMutableDictionary *result = [NSMutableDictionary new];
    NSArray<NSURLQueryItem *> *queryItems = [NSURLComponents componentsWithString:url].queryItems;
    for (NSURLQueryItem *item in queryItems) {
        result[item.name] = item.value;
    }
    return result;
}

- (void)actionAddAccount:(UITableViewCell *)sender {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *actionMicrosoft = [UIAlertAction actionWithTitle:localize(@"login.option.microsoft", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self actionLoginMicrosoft:sender];
    }];
    [picker addAction:actionMicrosoft];
    UIAlertAction *actionLocal = [UIAlertAction actionWithTitle:localize(@"login.option.local", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self actionLoginLocal:sender];
    }];
    [picker addAction:actionLocal];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [picker addAction:cancel];

    picker.popoverPresentationController.sourceView = sender;
    picker.popoverPresentationController.sourceRect = sender.bounds;

    [self presentViewController:picker animated:YES completion:nil];
}

- (void)actionLoginLocal:(UIView *)sender {
    if (getPrefBool(@"warnings.local_warn")) {
        setPrefBool(@"warnings.local_warn", NO);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"login.warn.title.localmode", nil) message:localize(@"login.warn.message.localmode", nil) preferredStyle:UIAlertControllerStyleActionSheet];
        alert.popoverPresentationController.sourceView = sender;
        alert.popoverPresentationController.sourceRect = sender.bounds;
        UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {[self actionLoginLocal:sender];}];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:localize(@"Sign in", nil) message:localize(@"login.option.local", nil) preferredStyle:UIAlertControllerStyleAlert];
    [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = localize(@"login.alert.field.username", nil);
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *textFields = controller.textFields;
        UITextField *usernameField = textFields[0];
        if (usernameField.text.length < 3 || usernameField.text.length > 16) {
            controller.message = localize(@"login.error.username.outOfRange", nil);
            [self presentViewController:controller animated:YES completion:nil];
        } else {
            id callback = ^(id status, BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!success) return;
                    if (self.whenItemSelected) self.whenItemSelected();
                    NSString *storageKey = [BaseAuthenticator
                        storageKeyForAuthData:BaseAuthenticator.current.authData];
                    setPrefObject(@"internal.selected_account", storageKey);
                    if (BaseAuthenticator.current.authData) {
                        [self addOrReplaceAccount:
                            BaseAuthenticator.current.authData.copy];
                    }
                    [self.tableView reloadData];
                });
            };
            [[[LocalAuthenticator alloc] initWithInput:usernameField.text] loginWithCallback:callback];
        }
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)actionLoginMicrosoft:(UITableViewCell *)sender {
    NSURL *url = [NSURL URLWithString:@"https://login.live.com/oauth20_authorize.srf?client_id=00000000402b5328&response_type=code&scope=service%3A%3Auser.auth.xboxlive.com%3A%3AMBI_SSL&redirect_url=https%3A%2F%2Flogin.live.com%2Foauth20_desktop.srf"];

    self.authVC =
        [[ASWebAuthenticationSession alloc] initWithURL:url
        callbackURLScheme:@"ms-xal-00000000402b5328"
        completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error)
    {
        if (callbackURL == nil) {
            if (error.code != ASWebAuthenticationSessionErrorCodeCanceledLogin) {
                showDialog(localize(@"Error", nil), error.localizedDescription);
            }
            return;
        }
        // NSLog(@"URL returned = %@", [callbackURL absoluteString]);

        NSDictionary *queryItems = [self parseQueryItems:callbackURL.absoluteString];
        if (queryItems[@"code"]) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                self.modalInPresentation = YES;
                self.tableView.userInteractionEnabled = NO;
                [self addActivityIndicatorTo:sender];
            });
            id callback = ^(id status, BOOL success) {
                if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"] && success) {
                    showDialog(localize(@"login.warn.title.demomode", nil), localize(@"login.warn.message.demomode", nil));
                }
                dispatch_async(dispatch_get_main_queue(), ^(){
                    [self callbackMicrosoftAuth:status success:success forCell:sender];
                });
            };
            [[[MicrosoftAuthenticator alloc] initWithInput:queryItems[@"code"]] loginWithCallback:callback];
        } else {
            if ([queryItems[@"error"] hasPrefix:@"access_denied"]) {
                // Ignore access denial responses
                return;
            }
            showDialog(localize(@"Error", nil), queryItems[@"error_description"]);
        }
    }];

    self.authVC.prefersEphemeralWebBrowserSession = YES;
    self.authVC.presentationContextProvider = self;

    if ([self.authVC start] == NO) {
        showDialog(localize(@"Error", nil), localize(@"localization.error.open_safari", nil));
    }
}

- (void)addActivityIndicatorTo:(UITableViewCell *)cell {
    UIActivityIndicatorViewStyle indicatorStyle = UIActivityIndicatorViewStyleMedium;
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:indicatorStyle];
    cell.accessoryView = indicator;
    [indicator sizeToFit];
    [indicator startAnimating];
}

- (void)removeActivityIndicatorFrom:(UITableViewCell *)cell {
    UIActivityIndicatorView *indicator = (id)cell.accessoryView;
    [indicator stopAnimating];
    cell.accessoryView = nil;
}

- (void)callbackMicrosoftAuth:(id)status success:(BOOL)success forCell:(UITableViewCell *)cell {
    if (status != nil) {
        if (success) {
            cell.detailTextLabel.text = status;
        } else {
            self.modalInPresentation = NO;
            self.tableView.userInteractionEnabled = YES;
            [self removeActivityIndicatorFrom:cell];
            cell.detailTextLabel.text = [status localizedDescription];
            NSData *errorData = ((NSError *)status).userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
            NSString *errorStr = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
            NSLog(@"[MSA] Error: %@", errorStr);
            showDialog(localize(@"Error", nil), errorStr);
        }
    } else if (success) {
        if (self.whenItemSelected) self.whenItemSelected();
        NSString *storageKey = [BaseAuthenticator
            storageKeyForAuthData:BaseAuthenticator.current.authData];
        setPrefObject(@"internal.selected_account", storageKey);
        [self removeActivityIndicatorFrom:cell];
        self.modalInPresentation = NO;
        self.tableView.userInteractionEnabled = YES;
        if (BaseAuthenticator.current.authData) {
            [self addOrReplaceAccount:
                BaseAuthenticator.current.authData.copy];
        }
        [self.tableView reloadData];
    }
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - ASWebAuthenticationPresentationContextProviding
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    return UIApplication.sharedApplication.windows.firstObject;
}

@end
