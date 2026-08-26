#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "utils.h"

#import "ios_uikit_bridge.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "MinecraftOptionUtils.h"
#import "PLLogOutputView.h"
#import "PLProfiles.h"
#import "ZinkConfig.h"

#define fm NSFileManager.defaultManager

extern char **environ;

static void PocketJDisableUnsupportedDesktopInputMods(NSString *gameDirectory) {
    NSString *modsDirectory = [gameDirectory stringByAppendingPathComponent:@"mods"];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:modsDirectory error:nil];
    for (NSString *entry in entries) {
        NSString *lowercase = entry.lowercaseString;
        if (![lowercase hasSuffix:@".jar"] ||
            (![lowercase containsString:@"imblocker"] &&
             ![lowercase containsString:@"inputmethodblocker"])) {
            continue;
        }

        NSString *source = [modsDirectory stringByAppendingPathComponent:entry];
        NSString *destination = [source stringByAppendingString:@".disabled"];
        NSUInteger duplicateIndex = 2;
        while ([fm fileExistsAtPath:destination]) {
            destination = [source stringByAppendingFormat:@".%lu.disabled",
                (unsigned long)duplicateIndex++];
        }
        NSError *error = nil;
        [fm moveItemAtPath:source toPath:destination error:&error];
        if (error) {
            NSLog(@"[PocketJ Mod Compatibility] Failed to disable %@: %@",
                entry, error.localizedDescription);
            continue;
        }
        NSLog(@"[PocketJ Mod Compatibility] Disabled desktop-only input-method mod %@; its macOS JNA library cannot run inside an iOS app.", entry);
    }
}

static NSString *PocketJConfigureModernForgeGameRoot(NSString *versionID) {
    const char *currentRoot = getenv("POJAV_GAME_DIR");
    const char *savedRoot = getenv("POCKETJ_REAL_GAME_DIR");
    NSString *realRoot = savedRoot ? @(savedRoot) : (currentRoot ? @(currentRoot) : nil);
    if (!savedRoot && realRoot.length) {
        setenv("POCKETJ_REAL_GAME_DIR", realRoot.UTF8String, 1);
    }

    NSString *lowercase = versionID.lowercaseString;
    BOOL modernForge = [lowercase containsString:@"forge"];
    if (!modernForge || !realRoot.length) {
        if (realRoot.length) setenv("POJAV_GAME_DIR", realRoot.UTF8String, 1);
        return realRoot;
    }

    const char *homeValue = getenv("POJAV_HOME");
    if (!homeValue) return realRoot;
    NSString *alias = [@(homeValue) stringByAppendingPathComponent:@".pocketj-loader-runtime"];
    NSString *target = [fm destinationOfSymbolicLinkAtPath:alias error:nil];
    if (![target isEqualToString:realRoot]) {
        if ([[fm attributesOfItemAtPath:alias error:nil].fileType
                isEqualToString:NSFileTypeSymbolicLink]) {
            [fm removeItemAtPath:alias error:nil];
        }
        if (![fm fileExistsAtPath:alias]) {
            [fm createSymbolicLinkAtPath:alias withDestinationPath:realRoot error:nil];
        }
    }
    if ([[fm destinationOfSymbolicLinkAtPath:alias error:nil] isEqualToString:realRoot]) {
        setenv("POJAV_GAME_DIR", alias.UTF8String, 1);
        NSLog(@"[Forge Compatibility] Using URI-safe game root %@", alias);
        return alias;
    }
    setenv("POJAV_GAME_DIR", realRoot.UTF8String, 1);
    return realRoot;
}

static NSString *PocketJConfigureModernForgeInstanceRoot(NSString *versionID,
                                                         NSString *gameDirectory) {
    if (![versionID.lowercaseString containsString:@"forge"] || !gameDirectory.length) {
        return gameDirectory;
    }

    const char *homeValue = getenv("POJAV_HOME");
    if (!homeValue) return gameDirectory;
    NSString *alias = [@(homeValue) stringByAppendingPathComponent:@".pocketj-instance-runtime"];
    NSString *target = [fm destinationOfSymbolicLinkAtPath:alias error:nil];
    if (![target isEqualToString:gameDirectory]) {
        if ([[fm attributesOfItemAtPath:alias error:nil].fileType
                isEqualToString:NSFileTypeSymbolicLink]) {
            [fm removeItemAtPath:alias error:nil];
        }
        if (![fm fileExistsAtPath:alias]) {
            [fm createSymbolicLinkAtPath:alias withDestinationPath:gameDirectory error:nil];
        }
    }
    if ([[fm destinationOfSymbolicLinkAtPath:alias error:nil]
            isEqualToString:gameDirectory]) {
        NSLog(@"[Forge Compatibility] Using URI-safe instance root %@", alias);
        return alias;
    }
    return gameDirectory;
}

BOOL validateVirtualMemorySpace(size_t size) {
    size <<= 20; // convert to MB
    void *map = mmap(0, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    // check if process successfully maps and unmaps a contiguous range
    if(map == MAP_FAILED || munmap(map, size) != 0)
        return NO;
    return YES;
}

void init_loadDefaultEnv() {
    /* Define default env */

    // Silent Caciocavallo NPE error in locating Android-only lib
    setenv("LD_LIBRARY_PATH", "", 1);

    // Ignore mipmap for performance(?) seems does not affect iOS
    //setenv("LIBGL_MIPMAP", "3", 1);

    // Disable overloaded functions hack for Minecraft 1.17+
    setenv("LIBGL_NOINTOVLHACK", "1", 1);

    // Fix white color on banner and sheep, since GL4ES 1.1.5
    setenv("LIBGL_NORMALIZE", "1", 1);

    // Override OpenGL version to 4.1 for Zink
    setenv("MESA_GL_VERSION_OVERRIDE", "4.1", 1);

    // Runs JVM in a separate thread
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);
}

void init_loadCustomEnv() {
    NSString *envvars = getPrefObject(@"java.env_variables");
    if (envvars == nil) return;
    NSLog(@"[JavaLauncher] Reading custom environment variables");
    for (NSString *line in [envvars componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        if (![line containsString:@"="]) {
            NSLog(@"[JavaLauncher] Warning: skipped empty value custom env variable: %@", line);
            continue;
        }
        NSRange range = [line rangeOfString:@"="];
        NSString *key = [line substringToIndex:range.location];
        NSString *value = [line substringFromIndex:range.location+range.length];
        setenv(key.UTF8String, value.UTF8String, 1);
        NSLog(@"[JavaLauncher] Added custom env variable: %@", line);
    }
}

void init_loadCustomJvmFlags(int* argc, const char** argv) {
    NSString *jvmargs = [PLProfiles resolveKeyForCurrentProfile:@"javaArgs"];
    if (jvmargs == nil) return;
    // Make the separator happy
    jvmargs = [jvmargs stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    jvmargs = [@" " stringByAppendingString:jvmargs];

    NSLog(@"[JavaLauncher] Reading custom JVM flags");
    NSArray *argsToPurge = @[@"Xms", @"Xmx", @"d32", @"d64"];
    for (NSString *arg in [jvmargs componentsSeparatedByString:@" -"]) {
        NSString *jvmarg = [arg stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (jvmarg.length == 0) continue;
        BOOL ignore = NO;
        for (NSString *argToPurge in argsToPurge) {
            if ([jvmarg hasPrefix:argToPurge]) {
                NSLog(@"[JavaLauncher] Ignored JVM flag: -%@", jvmarg);
                ignore = YES;
                break;
            }
        }
        if (ignore) continue;

        ++*argc;
        argv[*argc] = [@"-" stringByAppendingString:jvmarg].UTF8String;

        NSLog(@"[JavaLauncher] Added custom JVM flag: %s", argv[*argc]);
    }
}

static int PocketJJavaVersionFromMetadata(NSDictionary *metadata) {
    NSDictionary *javaVersion = [metadata[@"javaVersion"] isKindOfClass:NSDictionary.class]
        ? metadata[@"javaVersion"] : nil;
    int major = [javaVersion[@"majorVersion"] intValue];
    if (major <= 0) major = [javaVersion[@"version"] intValue];
    return major;
}

int PocketJRequiredJavaVersionForMinecraft(NSString *versionID) {
    if (versionID.length == 0) return 8;

    if ([versionID isEqualToString:@"latest-release"]) {
        versionID = getPrefObject(@"internal.latest_version.release") ?: versionID;
    } else if ([versionID isEqualToString:@"latest-snapshot"]) {
        versionID = getPrefObject(@"internal.latest_version.snapshot") ?: versionID;
    }

    NSFileManager *manager = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    const char *gameDir = getenv("POJAV_GAME_DIR");
    if (gameDir) [roots addObject:@(gameDir)];
    const char *home = getenv("POJAV_HOME");
    if (home) [roots addObject:[NSString stringWithFormat:@"%s/instances/%@", home,
        getPrefObject(@"general.game_directory") ?: @"default"]];

    for (NSString *root in roots) {
        NSString *path = [NSString stringWithFormat:@"%@/versions/%@/%@.json",
            root, versionID, versionID];
        if (![manager fileExistsAtPath:path]) continue;
        int major = PocketJJavaVersionFromMetadata(parseJSONFromFile(path));
        if (major > 0) {
            NSLog(@"[JavaResolver] %@ requires Java %d from Mojang metadata",
                versionID, major);
            return major;
        }
    }

    NSString *lower = versionID.lowercaseString;
    NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:@"^(\\d+)(?:\\.(\\d+))?" options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:lower options:0
        range:NSMakeRange(0, lower.length)];
    NSInteger majorVersion = 0;
    NSInteger minorVersion = 0;
    if (match.numberOfRanges > 1) {
        majorVersion = [[lower substringWithRange:[match rangeAtIndex:1]] integerValue];
        if (match.numberOfRanges > 2 && [match rangeAtIndex:2].location != NSNotFound) {
            minorVersion = [[lower substringWithRange:[match rangeAtIndex:2]] integerValue];
        }
    }

    int required = 8;
    if (majorVersion >= 26) {
        required = 25;
    } else if (majorVersion == 1 && minorVersion >= 20) {
        NSArray<NSString *> *parts = [lower componentsSeparatedByString:@"."];
        NSInteger patch = parts.count > 2 ? [parts[2] integerValue] : 0;
        required = (minorVersion > 20 || patch >= 5) ? 21 : 17;
    } else if (majorVersion == 1 && minorVersion >= 17) {
        required = 17;
    }
    NSLog(@"[JavaResolver] %@ requires Java %d from version-era fallback",
        versionID, required);
    return required;
}

int launchJVM(NSString *username, id launchTarget, int width, int height, int minVersion) {
    NSLog(@"[JavaLauncher] Beginning JVM launch");

    init_loadDefaultEnv();
    init_loadCustomEnv();

    DeviceGetJITFlags(YES); // refresh JIT flags right after loading env
    BOOL requiresTXMWorkaround = DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM);
    BOOL jit26AlwaysAttached = getPrefBool(@"debug.debug_always_attached_jit");
    if (requiresTXMWorkaround) {
        static void *result;
        if(!result) result = JIT26CreateRegionLegacy(getpagesize());
        if ((uint32_t)result != 0x690000E0) {
            munmap(result, getpagesize());
            // we can't continue since legacy script only allows calling breakpoint once
            NSString *inBundleScriptPath = [NSBundle.mainBundle pathForResource:@"UniversalJIT26" ofType:@"js"];
            NSString *lcAppInfoPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"];
            NSMutableDictionary *lcAppInfo = [NSMutableDictionary dictionaryWithContentsOfFile:lcAppInfoPath];
            if(lcAppInfo) {
                // If this is inside LiveContainer, assign the script and prompt the user to restart PocketJ Launcher.
                lcAppInfo[@"jitLaunchScriptJs"] = [[NSData dataWithContentsOfFile:inBundleScriptPath] base64EncodedStringWithOptions:0];
                if([lcAppInfo writeToFile:lcAppInfoPath atomically:YES]) {
                    showDialog(localize(@"Error", nil), localize(@"localization.error.legacy_script_updated", nil));
                    [PLLogOutputView handleExitCode:1];
                    return 1;
                }
            }
            [NSFileManager.defaultManager copyItemAtPath:inBundleScriptPath toPath:[NSString stringWithFormat:@"%s/UniversalJIT26.js", getenv("POJAV_HOME")] error:nil];
            showDialog(localize(@"Error", nil), localize(@"localization.error.legacy_script_removed", nil));
            [PLLogOutputView handleExitCode:1];
            return 1;
        }
        JIT26SendJITScript([NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"UniversalJIT26Extension" ofType:@"js"]]);
        JIT26SetDetachAfterFirstBr(!jit26AlwaysAttached);
        // make sure we don't get stuck in EXC_BAD_ACCESS
        task_set_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS, 0, EXCEPTION_DEFAULT, MACHINE_THREAD_STATE);
    }
    if (!requiresTXMWorkaround || jit26AlwaysAttached) {
        if (jit26AlwaysAttached) {
            // Only allow StikDebug to catch our breakpoints to prevent any stutters
            task_set_exception_ports(mach_task_self(), EXC_MASK_ALL & ~EXC_MASK_BREAKPOINT, 0,
                EXCEPTION_DEFAULT, THREAD_STATE_NONE);
        }
        // Activate Library Validation bypass for external runtime and dylibs (JNA, etc)
        init_bypassDyldLibValidation();
    } else {
        NSLog(@"[DyldLVBypass] Hook disabled! Loading unsigned dylib will cause code signature error.");
    }

    BOOL launchJar = NO;
    NSString *gameDir;
    NSString *defaultJRETag;
    NSCAssert(launchTarget, @"Unexpected nil launchTarget");
    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        // Keep automatic selection identical to the instance editor. Mojang's
        // metadata is authoritative when present; custom loader manifests may
        // omit it, so fall back to the instance's underlying Minecraft version.
        NSString *minecraftVersion = PLProfiles.current.selectedProfile[@"pocketjMinecraftVersion"];
        if (!minecraftVersion.length) minecraftVersion = launchTarget[@"id"];
        PocketJConfigureModernForgeGameRoot(launchTarget[@"id"]);
        int automaticJavaVersion = PocketJRequiredJavaVersionForMinecraft(minecraftVersion);
        minVersion = MAX(MAX(minVersion, 8), automaticJavaVersion);
        int preferredJavaVersion = [PLProfiles resolveKeyForCurrentProfile:@"javaVersion"].intValue;
        if (preferredJavaVersion > 0) {
            if (minVersion > preferredJavaVersion) {
                NSLog(@"[JavaLauncher] Profile's preferred Java version (%d) does not meet the minimum version (%d), dropping request", preferredJavaVersion, minVersion);
            } else {
                NSDebugLog(@"[PLProfiles] Applying javaVersion");
                minVersion = preferredJavaVersion;
            }
        }
        if (minVersion <= 8) {
            defaultJRETag = @"1_16_5_older";
        } else {
            defaultJRETag = @"1_17_newer";
        }

        // Setup POJAV_RENDERER
        NSString *renderer = [PLProfiles resolveKeyForCurrentProfile:@"renderer"];
        if ([renderer isEqualToString:@"auto"] && automaticJavaVersion >= 25) {
            // Minecraft 26.x is known to render incorrectly on the iOS ANGLE
            // path.  Use the complete Mesa/Zink + MoltenVK stack shipped by
            // the Java-25 Amethyst fork instead of layering more ANGLE hacks.
            renderer = @ RENDERER_NAME_VK_ZINK;
            [ZinkConfig applyZinkEnvironmentFromPreferences];
            NSLog(@"[JavaLauncher] Auto-selected Mesa/Zink for Minecraft %@ (required Java %d)",
                minecraftVersion, automaticJavaVersion);
        }
        NSLog(@"[JavaLauncher] RENDERER is set to %@\n", renderer);
        setenv("POJAV_RENDERER", renderer.UTF8String, 1);
        BOOL needsAngle26TextureBufferWorkaround = automaticJavaVersion >= 25 &&
            [renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE];
        setenv("POCKETJ_ANGLE_26_TEXTURE_BUFFER_WORKAROUND",
            needsAngle26TextureBufferWorkaround ? "1" : "0", 1);
        // Setup gameDir
        gameDir = [NSString stringWithFormat:@"%s/instances/%@/%@",
            getenv("POJAV_HOME"), getPrefObject(@"general.game_directory"),
            [PLProfiles resolveKeyForCurrentProfile:@"gameDir"]]
            .stringByStandardizingPath;
        gameDir = PocketJConfigureModernForgeInstanceRoot(launchTarget[@"id"], gameDir);
        if (automaticJavaVersion >= 17) {
            PocketJDisableUnsupportedDesktopInputMods(gameDir);
        }
    } else {
        defaultJRETag = @"execute_jar";
        gameDir = @(getenv("POJAV_GAME_DIR"));
        launchJar = YES;
    }
    NSLog(@"[JavaLauncher] Looking for Java %d or later", minVersion);
    NSString *javaHome = getSelectedJavaHome(defaultJRETag, minVersion);

    if (javaHome == nil) {
        UIKit_returnToSplitView();
        BOOL isExecuteJar = [defaultJRETag isEqualToString:@"execute_jar"];
        showDialog(localize(@"Error", nil), [NSString stringWithFormat:localize(@"java.error.missing_runtime", nil),
            isExecuteJar ? [launchTarget lastPathComponent] : PLProfiles.current.selectedProfile[@"lastVersionId"], minVersion]);
        return 1;
    } else if ([javaHome hasPrefix:@(getenv("POJAV_HOME"))]) {
        // Copy libawt_xawt.dylib
        NSString *dest = [NSString stringWithFormat:@"%@/lib/libawt_xawt.dylib", javaHome];
        NSString *source = [NSString stringWithFormat:@"%@/Frameworks/libawt_xawt.dylib", NSBundle.mainBundle.bundlePath];
        NSError *error;
        [fm removeItemAtPath:dest error:nil];
        [fm copyItemAtPath:source toPath:dest error:&error];
        if (error) {
            NSLog(@"[JavaLauncher] Copy libawt_xawt.dylib failed: %@", error.localizedDescription);
        }
    }

    setenv("JAVA_HOME", javaHome.UTF8String, 1);
    NSLog(@"[JavaLauncher] JAVA_HOME has been set to %@", javaHome);

    int allocmem;
    if (getPrefBool(@"java.auto_ram")) {
        CGFloat autoRatio = getEntitlementValue(@"com.apple.private.memorystatus") ? 0.4 : 0.25;
        allocmem = roundf((NSProcessInfo.processInfo.physicalMemory >> 20) * autoRatio);
    } else {
        allocmem = getPrefInt(@"java.allocated_memory");
    }
    BOOL isLegacyCompatibilityRuntime = NO;
    if (!launchJar && getPrefBool(@"general.legacy_compatibility")) {
        NSString *versionID = [launchTarget[@"id"] lowercaseString] ?: @"";
        NSString *versionType = [launchTarget[@"type"] lowercaseString] ?: @"";
        BOOL isClassic = [versionID hasPrefix:@"rd-"] ||
            [versionID hasPrefix:@"c0."] || [versionID hasPrefix:@"inf-"] ||
            [versionID hasPrefix:@"indev-"] || [versionID hasPrefix:@"in-"];
        BOOL isEarlyAlpha = [versionType isEqualToString:@"old_alpha"] ||
            [versionID hasPrefix:@"a1."];
        BOOL isLegacyBeta = [versionType isEqualToString:@"old_beta"] ||
            [versionID hasPrefix:@"b1."];
        if (isClassic || isEarlyAlpha || isLegacyBeta) {
            isLegacyCompatibilityRuntime = YES;
            // These releases need very little Java heap, while HotSpot, GL and
            // the iOS JIT mapping still consume native address space. Keeping
            // a 1 GiB heap left too little room for the Java 8 code cache.
            int compatibilityLimit = 192;
            if (allocmem > compatibilityLimit) {
                NSLog(@"[Legacy Compatibility] Capping %@ from %d MB to %d MB",
                    versionID, allocmem, compatibilityLimit);
                allocmem = compatibilityLimit;
            }
        }
    }
    BOOL isLoaderInstaller = launchJar &&
        [NSUserDefaults.standardUserDefaults stringForKey:@"PocketJPendingLoaderKind"].length > 0;
    if (isLoaderInstaller && allocmem > 768) {
        NSLog(@"[Loader Installer] Capping installer heap from %d MB to 768 MB",
            allocmem);
        allocmem = 768;
    }
    NSLog(@"[JavaLauncher] Max RAM allocation is set to %d MB", allocmem);
    if (!validateVirtualMemorySpace(allocmem)) {
        UIKit_returnToSplitView();
        if (getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")) {
            showDialog(localize(@"Error", nil), localize(@"localization.error.virtual_memory_low", nil));
        } else {
            showDialog(localize(@"Error", nil), localize(@"localization.error.memory_entitlement_missing", nil));
        }
        return 1;
    }

    // Setup options.txt
    [MinecraftOptionUtils setupOptionsAtGameDir:gameDir];
    
    int margc = -1;
    const char *margv[1000];

    margv[++margc] = [NSString stringWithFormat:@"%@/bin/java", javaHome].UTF8String;
    margv[++margc] = "-XstartOnFirstThread";
    if (!launchJar) {
        margv[++margc] = "-Djava.system.class.loader=net.kdt.pojavlaunch.PojavClassLoader";
    }
    margv[++margc] = isLegacyCompatibilityRuntime ? "-Xms64M" : "-Xms128M";
    margv[++margc] = [NSString stringWithFormat:@"-Xmx%dM", allocmem].UTF8String;
    if (isLegacyCompatibilityRuntime) {
        // Java 8 otherwise reserves a contiguous 128 MB compiler code heap.
        // Very old Minecraft uses only a few MB of compiled code, while that
        // large native reservation can fail on iOS even after -Xmx is capped.
        margv[++margc] = "-XX:InitialCodeCacheSize=2M";
        margv[++margc] = "-XX:ReservedCodeCacheSize=16M";
    }
    if (isLoaderInstaller) {
        // Forge processors need heap, but a 128 MB HotSpot code heap can starve
        // iOS native address space during binary patching. Installers do not
        // need a game-sized code cache.
        margv[++margc] = "-XX:ReservedCodeCacheSize=64M";
    }
    margv[++margc] = [NSString stringWithFormat:@"-Djava.library.path=%@/Frameworks", NSBundle.mainBundle.bundlePath].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.dir=%@", gameDir].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.home=%s", getenv("POJAV_HOME")].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-Duser.timezone=%@", NSTimeZone.localTimeZone.name].UTF8String;
    margv[++margc] = [NSString stringWithFormat:@"-DUIScreen.maximumFramesPerSecond=%d", (int)UIScreen.mainScreen.maximumFramesPerSecond].UTF8String;
    margv[++margc] = "-Dorg.lwjgl.glfw.checkThread0=false";
    margv[++margc] = "-Dorg.lwjgl.system.allocator=system";
    // Minecraft 26.2 loads LWJGL SPVC. Reuse the SPIRV-Cross C library already
    // signed and embedded in the app instead of extracting desktop natives.
    margv[++margc] = "-Dorg.lwjgl.spvc.libname=spirv-cross-c-shared.0";
    //margv[++margc] = "-Dorg.lwjgl.util.NoChecks=true";
    margv[++margc] = "-Dlog4j2.formatMsgNoLookups=true";

    // Preset OpenGL libname
    const char *glLibName = getenv("POJAV_RENDERER");
    if (glLibName) {
        if (!strcmp(glLibName, "auto")) {
            // workaround only applies to 1.20.2+
            glLibName = RENDERER_NAME_MTL_ANGLE;
        }
        margv[++margc] = [NSString stringWithFormat:@"-Dorg.lwjgl.opengl.libname=%s", glLibName].UTF8String;
    }

    NSString *librariesPath = [NSString stringWithFormat:@"%@/libs", NSBundle.mainBundle.bundlePath];
    margv[++margc] = [NSString stringWithFormat:@"-javaagent:%@/patchjna_agent.jar=", librariesPath].UTF8String;
    if(getPrefBool(@"general.cosmetica")) {
        margv[++margc] = [NSString stringWithFormat:@"-javaagent:%@/arc_dns_injector.jar=23.95.137.176", librariesPath].UTF8String;
    }

    // Workaround random stack guard allocation crashes
    margv[++margc] = "-XX:+UnlockExperimentalVMOptions";
    margv[++margc] = "-XX:+DisablePrimordialThreadGuardPages";

    // On iOS 26, use mirror mapped JIT by default
    if (@available(iOS 26.0, *)) {
        margv[++margc] = "-XX:+MirrorMappedCodeCache";
    }

    // Disable Forge 1.16.x early progress window
    margv[++margc] = "-Dfml.earlyprogresswindow=false";

    // Load java
    NSString *libjlipath8 = [NSString stringWithFormat:@"%@/lib/jli/libjli.dylib", javaHome]; // java 8
    NSString *libjlipath11 = [NSString stringWithFormat:@"%@/lib/libjli.dylib", javaHome]; // java 11+
    BOOL isJava8 = [fm fileExistsAtPath:libjlipath8];
    setenv("INTERNAL_JLI_PATH", (isJava8 ? libjlipath8 : libjlipath11).UTF8String, 1);
    void* libjli = dlopen(getenv("INTERNAL_JLI_PATH"), RTLD_GLOBAL);

    if (!libjli) {
        const char *error = dlerror();
        NSLog(@"[Init] JLI lib = NULL: %s", error);
        UIKit_returnToSplitView();
        showDialog(localize(@"Error", nil), @(error));
        return 1;
    }

    // Setup Caciocavallo
    margv[++margc] = "-Djava.awt.headless=false";
    margv[++margc] = "-Dcacio.font.fontmanager=sun.awt.X11FontManager";
    margv[++margc] = "-Dcacio.font.fontscaler=sun.font.FreetypeFontScaler";
    margv[++margc] = [NSString stringWithFormat:@"-Dcacio.managed.screensize=%dx%d", width, height].UTF8String;
    margv[++margc] = "-Dswing.defaultlaf=javax.swing.plaf.metal.MetalLookAndFeel";
    if (isJava8) {
        // Setup Caciocavallo
        margv[++margc] = "-Dawt.toolkit=net.java.openjdk.cacio.ctc.CTCToolkit";
        margv[++margc] = "-Djava.awt.graphicsenv=net.java.openjdk.cacio.ctc.CTCGraphicsEnvironment";
    } else {
        // Required by Cosmetica to inject DNS
        margv[++margc] = "--add-opens=java.base/java.net=ALL-UNNAMED";

        // Setup Caciocavallo
        margv[++margc] = "-Dawt.toolkit=com.github.caciocavallosilano.cacio.ctc.CTCToolkit";
        margv[++margc] = "-Djava.awt.graphicsenv=com.github.caciocavallosilano.cacio.ctc.CTCGraphicsEnvironment";

        // Required by Caciocavallo17 to access internal API
        margv[++margc] = "--add-exports=java.desktop/java.awt=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/java.awt.peer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.image=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.java2d=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/java.awt.dnd.peer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.event=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.awt.datatransfer=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.desktop/sun.font=ALL-UNNAMED";
        margv[++margc] = "--add-exports=java.base/sun.security.action=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.base/java.util=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/java.awt=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/sun.font=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.desktop/sun.java2d=ALL-UNNAMED";
        margv[++margc] = "--add-opens=java.base/java.lang.reflect=ALL-UNNAMED";

        // TODO: workaround, will be removed once the startup part works without PLaunchApp
        margv[++margc] = "--add-exports=cpw.mods.bootstraplauncher/cpw.mods.bootstraplauncher=ALL-UNNAMED";
    }

    // Add Caciocavallo bootclasspath
    NSString *cacio_classpath = [NSString stringWithFormat:@"-Xbootclasspath/%s", isJava8 ? "p" : "a"];
    NSString *cacio_libs_path = [NSString stringWithFormat:@"%@/libs_caciocavallo%s", NSBundle.mainBundle.bundlePath, isJava8 ? "" : "17"];
    NSArray *files = [fm contentsOfDirectoryAtPath:cacio_libs_path error:nil];
    for(NSString *file in files) {
        if ([file hasSuffix:@".jar"]) {
            cacio_classpath = [NSString stringWithFormat:@"%@:%@/%@", cacio_classpath, cacio_libs_path, file];
        }
    }
    margv[++margc] = cacio_classpath.UTF8String;

    BOOL hasExtendedVirtualAddressing = getEntitlementValue(@"com.apple.developer.kernel.extended-virtual-addressing");
    BOOL needsIOS27CompressedClassSpaceWorkaround = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27;
    if (!hasExtendedVirtualAddressing || needsIOS27CompressedClassSpaceWorkaround) {
        // iOS 27 rejects HotSpot's default 1 GiB compressed class-space reservation
        // even when the extended virtual addressing entitlement is present. Disabling
        // compressed class pointers lets the JVM continue through initialization.
        if (needsIOS27CompressedClassSpaceWorkaround) {
            NSLog(@"[iOS 27 Compatibility] Disabling compressed class pointers before JVM startup");
        }
        margv[++margc] = "-XX:-UseCompressedClassPointers";
    }

    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        for (NSString *arg in launchTarget[@"arguments"][@"jvm_processed"]) {
            margv[++margc] = arg.UTF8String;
        }
    }

    init_loadCustomJvmFlags(&margc, (const char **)margv);
    NSLog(@"[Init] Found JLI lib");

    NSMutableArray<NSString *> *classpathEntries = [NSMutableArray array];
    NSArray<NSString *> *bundledLibraries = [[NSFileManager.defaultManager
        contentsOfDirectoryAtPath:librariesPath error:nil]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    BOOL useModernLWJGL = !launchJar && minVersion >= 25;
    for (NSString *library in bundledLibraries) {
        if (![library.pathExtension.lowercaseString isEqualToString:@"jar"]) continue;
        if ([library isEqualToString:@"lwjgl.jar"] && useModernLWJGL) continue;
        if ([library isEqualToString:@"lwjgl341.jar"] && !useModernLWJGL) continue;
        [classpathEntries addObject:[librariesPath stringByAppendingPathComponent:library]];
    }
    NSString *classpath = [classpathEntries componentsJoinedByString:@":"];
    if (launchJar) {
        classpath = [classpath stringByAppendingFormat:@":%@", launchTarget];
    }
    margv[++margc] = "-cp";
    margv[++margc] = classpath.UTF8String;
    margv[++margc] = "net.kdt.pojavlaunch.PojavLauncher";

    if (launchJar) {
        margv[++margc] = "-jar";
    } else {
        margv[++margc] = username.UTF8String;
    }

    if ([launchTarget isKindOfClass:NSDictionary.class]) {
        margv[++margc] = [launchTarget[@"id"] UTF8String];
    } else {
        margv[++margc] = [launchTarget UTF8String];
    }
    //margv[++margc] = "ghidra.GhidraRun";

    pJLI_Launch = (JLI_Launch_func *)dlsym(libjli, "JLI_Launch");

    if (NULL == pJLI_Launch) {
        NSLog(@"[Init] JLI_Launch = NULL");
        return -2;
    }

    NSLog(@"[Init] Calling JLI_Launch");

    // Cr4shed known issue: exit after crash dump,
    // reset signal handler so that JVM can catch them
    signal(SIGSEGV, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGFPE, SIG_DFL);

    // Free split VC
    tmpRootVC = nil;

    return pJLI_Launch(++margc, margv,
                   0, NULL, // sizeof(const_jargs) / sizeof(char *), const_jargs,
                   0, NULL, // sizeof(const_appclasspath) / sizeof(char *), const_appclasspath,
                   // These values are ignored in Java 17, so keep it anyways
                   "1.8.0-internal",
                   "1.8",

                   "java", "openjdk",
                   /* (const_jargs != NULL) ? JNI_TRUE : */ JNI_FALSE,
                   JNI_TRUE, JNI_FALSE, JNI_TRUE);
}
