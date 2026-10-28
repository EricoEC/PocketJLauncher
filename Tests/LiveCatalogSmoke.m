#import <Foundation/Foundation.h>
#import "PocketJAddonService.h"
int main(int argc,const char **argv) { @autoreleasepool {
    BOOL cf=argc>1 && !strcmp(argv[1],"--curseforge");
    NSString *key=getenv("POCKETJ_CF_TEST_KEY") ? @(getenv("POCKETJ_CF_TEST_KEY")):@"";
    if(cf && !key.length) { fprintf(stderr,"Missing test key in environment.\n"); return 2; }
    PocketJAddonService *service=[[PocketJAddonService alloc] initWithCurseForgeKey:key];
    __block BOOL done=NO; __block int result=1;
    [service versionsForProvider:cf ? @"CurseForge":@"Modrinth" project:cf ? @"394468":@"sodium" minecraft:@"1.21.11" loader:@"fabric" compatibleOnly:YES completion:^(NSArray *versions,NSError *error) {
        if(error) NSLog(@"Catalog smoke failed (%@ / %ld): %@",error.domain,(long)error.code,error.localizedDescription);
        else { NSLog(@"Catalog smoke passed: %@ returned %lu compatible versions.",cf ? @"CurseForge":@"Modrinth",(unsigned long)versions.count); result=versions.count ? 0:1; }
        done=YES;
    }];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:90]; while(!done && [deadline timeIntervalSinceNow]>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done ? result:3;
} }
