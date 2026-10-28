#import "BaseAuthenticator.h"
#include "jni.h"

JNIEXPORT jstring JNICALL Java_com_erico_pocketj_value_MinecraftAccount_getAccessTokenFromKeychain(JNIEnv *env, jclass clazz, jstring xuid) {
    // This function should only be called once
    static BOOL called = NO;
    if (called) {
        abort();
    }
    called = YES;

    const char *xuidC = (*env)->GetStringUTFChars(env, xuid, 0);
    NSString *identity=@(xuidC);
    Class provider=NSClassFromString([identity hasPrefix:@"yggdrasil__"] ? @"YggdrasilAuthenticator" : @"MicrosoftAuthenticator");
    NSString *accessToken = [provider tokenDataOfProfile:identity][@"accessToken"];
    (*env)->ReleaseStringUTFChars(env, xuid, xuidC);
    return (*env)->NewStringUTF(env, (accessToken ?: @"0").UTF8String);
}

// Historical JNI symbol forwards to the same guarded token-read implementation.
JNIEXPORT jstring JNICALL Java_net_kdt_pojavlaunch_value_MinecraftAccount_getAccessTokenFromKeychain(JNIEnv *env, jclass clazz, jstring xuid) {
    return Java_com_erico_pocketj_value_MinecraftAccount_getAccessTokenFromKeychain(env, clazz, xuid);
}
