#include "PocketJEnvironment.h"
#import "SurfaceViewController.h"

#include "jni.h"
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "PocketJRenderBridge.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"
#include "ZinkConfig.h"
#include "PocketJGameStartup.h"

int clientAPI;

void JNI_LWJGL_changeRenderer(const char* value_c) {
    JNIEnv *env;
    (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);
    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");
    jstring value = (*env)->NewStringUTF(env, value_c);
    jclass clazz = (*env)->FindClass(env, "java/lang/System");
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
}

void pocketjTerminate() {
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pocketjGetCurrentContext() {
    return br_get_current();
}

int pocketjInit(BOOL useStackQueue) {
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    isUseStackQueueCall = useStackQueue;
    return JNI_TRUE;
}

int pocketjInitOpenGL() {
    const char *rendererValue = PocketJGetEnv("POCKETJ_RENDERER");
    NSString *renderer = rendererValue ? @(rendererValue) : nil;
    PocketJGameStartupRendering(![renderer hasPrefix:@"libOSMesa"]);
    BOOL isAuto = [renderer isEqualToString:@"auto"];
    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // At this point, if renderer is still auto (unspecified major version), pick gl4es
        renderer = @ RENDERER_NAME_GL4ES;
        PocketJSetEnv("POCKETJ_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        PocketJSetEnv("POCKETJ_RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();
    } else if ([renderer hasPrefix:@"libOSMesa"]) {
        setenv("GALLIUM_DRIVER","zink",1);
        [ZinkConfig applyZinkEnvironmentFromPreferences];
        // This exact Mesa build resolves Vulkan through MoltenVK at runtime.
        // Load it globally before OSMesa so every vk* entry point is available.
        NSString *moltenVKPath = [NSBundle.mainBundle.privateFrameworksPath
            stringByAppendingPathComponent:@ RENDERER_NAME_VULKAN];
        void *moltenVK = dlopen(moltenVKPath.UTF8String, RTLD_NOW | RTLD_GLOBAL);
        if (!moltenVK) {
            NSLog(@"[PocketJ Zink] Failed to preload MoltenVK: %s", dlerror());
        }
        set_osm_bridge_tbl();
    }
    JNI_LWJGL_changeRenderer(renderer.UTF8String);
    // Preload renderer library
    dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);

    return !br_init();
    //return 0;
}

void pocketjSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
    } else if (strcmp(PocketJGetEnv("POCKETJ_RENDERER"), "auto")==0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                PocketJSetEnv("POCKETJ_RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;
            // case 4: use Zink?
            default:
                PocketJSetEnv("POCKETJ_RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pocketjSwapBuffers() {
    br_swap_buffers();
}

void pocketjMakeCurrent(basic_render_window_t* window) {
    br_make_current(window);
}

void* pocketjCreateContext(basic_render_window_t* contextSrc) {
    if (clientAPI == GLFW_NO_API) {
        // Game has selected Vulkan API to render
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    static BOOL inited = NO;
    if (!inited) {
        inited = YES;
        pocketjInitOpenGL();
    }

    return br_init_context(contextSrc);
}

void pocketjSwapInterval(int interval) {
    if (!br_swap_interval) return;
    br_swap_interval(interval);
}
