#include <jni.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <math.h>

static JavaVM *PocketJLWJGLVM;
static jmethodID PocketJLWJGLCallback;

typedef void (*PocketJFFICallback)(void *, void *, void **, void *);

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    PocketJLWJGLVM = vm;
    return JNI_VERSION_1_6;
}

static JNIEnv *PocketJLWJGLEnvironment(jboolean *attached) {
    JNIEnv *environment = NULL;
    *attached = JNI_FALSE;
    if (!PocketJLWJGLVM) return NULL;
    jint result = (*PocketJLWJGLVM)->GetEnv(
        PocketJLWJGLVM, (void **)&environment, JNI_VERSION_1_6);
    if (result == JNI_EDETACHED) {
        if ((*PocketJLWJGLVM)->AttachCurrentThread(
                PocketJLWJGLVM, &environment, NULL) != JNI_OK) {
            return NULL;
        }
        *attached = JNI_TRUE;
    } else if (result != JNI_OK) {
        return NULL;
    }
    return environment;
}

static void PocketJLWJGLCallbackHandler(
    void *cif, void *result, void **arguments, void *userData) {
    (void)cif;
    jboolean attached;
    JNIEnv *environment = PocketJLWJGLEnvironment(&attached);
    if (!environment || !PocketJLWJGLCallback) return;
    (*environment)->CallVoidMethod(environment, (jobject)userData,
        PocketJLWJGLCallback, (jlong)(uintptr_t)result,
        (jlong)(uintptr_t)arguments);
    if ((*environment)->ExceptionCheck(environment) && attached) {
        fprintf(stderr,
            "[LWJGL] Exception in callback invoked from a native thread.\n");
        (*environment)->ExceptionDescribe(environment);
        (*environment)->ExceptionClear(environment);
    }
}

JNIEXPORT jlong JNICALL
Java_org_lwjgl_system_Upcalls_getCallbackHandler(
    JNIEnv *environment, jclass clazz, jobject method) {
    (void)clazz;
    PocketJLWJGLCallback =
        (*environment)->FromReflectedMethod(environment, method);
    return (jlong)(uintptr_t)(PocketJFFICallback)&PocketJLWJGLCallbackHandler;
}

/*
 * LWJGL 3.4 renamed ThreadLocalUtil.nsetupEnvData(int) to
 * ThreadLocalUtil.setupEnvData(int). The iOS LWJGL native library still
 * exports the former JNI entry point. Forward the new ABI to the proven iOS
 * implementation instead of duplicating its JNIEnv table-copying logic here.
 */
JNIEXPORT jlong JNICALL
Java_org_lwjgl_system_ThreadLocalUtil_setupEnvData(
    JNIEnv *environment, jclass clazz, jint functionCount) {
    typedef jlong (*PocketJSetupEnvData)(JNIEnv *, jclass, jint);
    PocketJSetupEnvData implementation = (PocketJSetupEnvData)dlsym(
        RTLD_DEFAULT,
        "Java_org_lwjgl_system_ThreadLocalUtil_nsetupEnvData");
    if (!implementation) {
        fprintf(stderr,
            "[LWJGL] Missing legacy ThreadLocalUtil.nsetupEnvData bridge.\n");
        return 0;
    }
    return implementation(environment, clazz, functionCount);
}

/*
 * LWJGL 3.4 calls these GL32C entry points as class-owned JNI natives. The
 * bundled iOS LWJGL bridge predates those symbols, although every renderer
 * already exports the underlying OpenGL ES sync operations. Resolve the whole
 * sync family together so a successful fence is not followed by a missing
 * delete/wait/query native on the next frame.
 */
static void *PocketJGLFunction(const char *name) {
    void *function = dlsym(RTLD_DEFAULT, name);
    if (!function) fprintf(stderr, "[LWJGL] Missing renderer function %s.\n", name);
    return function;
}

JNIEXPORT jlong JNICALL Java_org_lwjgl_opengl_GL32C_glFenceSync(
    JNIEnv *environment, jclass clazz, jint condition, jint flags) {
    (void)environment; (void)clazz;
    typedef void *(*Function)(uint32_t, uint32_t);
    Function function = (Function)PocketJGLFunction("glFenceSync");
    return function ? (jlong)(uintptr_t)function((uint32_t)condition, (uint32_t)flags) : 0;
}

JNIEXPORT jboolean JNICALL Java_org_lwjgl_opengl_GL32C_nglIsSync(
    JNIEnv *environment, jclass clazz, jlong sync) {
    (void)environment; (void)clazz;
    typedef uint8_t (*Function)(void *);
    Function function = (Function)PocketJGLFunction("glIsSync");
    return function ? (function((void *)(uintptr_t)sync) ? JNI_TRUE : JNI_FALSE) : JNI_FALSE;
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_GL32C_glDeleteSync(
    JNIEnv *environment, jclass clazz, jlong sync) {
    (void)environment; (void)clazz;
    typedef void (*Function)(void *);
    Function function = (Function)PocketJGLFunction("glDeleteSync");
    if (function) function((void *)(uintptr_t)sync);
}

JNIEXPORT jint JNICALL Java_org_lwjgl_opengl_GL32C_nglClientWaitSync(
    JNIEnv *environment, jclass clazz, jlong sync, jint flags, jlong timeout) {
    (void)environment; (void)clazz;
    typedef uint32_t (*Function)(void *, uint32_t, uint64_t);
    Function function = (Function)PocketJGLFunction("glClientWaitSync");
    return function ? (jint)function((void *)(uintptr_t)sync, (uint32_t)flags,
        (uint64_t)timeout) : 0;
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_GL32C_nglWaitSync(
    JNIEnv *environment, jclass clazz, jlong sync, jint flags, jlong timeout) {
    (void)environment; (void)clazz;
    typedef void (*Function)(void *, uint32_t, uint64_t);
    Function function = (Function)PocketJGLFunction("glWaitSync");
    if (function) function((void *)(uintptr_t)sync, (uint32_t)flags, (uint64_t)timeout);
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_GL32C_nglGetSynciv(
    JNIEnv *environment, jclass clazz, jlong sync, jint pname, jint count,
    jlong lengthAddress, jlong valuesAddress) {
    (void)environment; (void)clazz;
    typedef void (*Function)(void *, uint32_t, int32_t, int32_t *, int32_t *);
    Function function = (Function)PocketJGLFunction("glGetSynciv");
    if (function) function((void *)(uintptr_t)sync, (uint32_t)pname, (int32_t)count,
        (int32_t *)(uintptr_t)lengthAddress, (int32_t *)(uintptr_t)valuesAddress);
}

/*
 * LWJGL 3.4.1 moved Minecraft's automatic world-preview resize to the newer
 * stb_image_resize2 ABI.  The bundled iOS liblwjgl_stb predates that symbol.
 * Supply the exact JNI entry point with a small bilinear UINT8 implementation
 * so entering a world can finish and the preview remains valid.
 */
static int PocketJSTBChannels(jint layout) {
    if (layout == 1) return 1;
    if (layout == 2 || layout == 9 || layout == 10 || layout == 15 || layout == 16) return 2;
    if (layout == 0 || layout == 3) return 3;
    if (layout >= 4 && layout <= 14) return 4;
    return 0;
}

JNIEXPORT jlong JNICALL
Java_org_lwjgl_stb_STBImageResize_nstbir_1resize_1uint8_1linear(
    JNIEnv *environment, jclass clazz, jlong inputAddress,
    jint inputWidth, jint inputHeight, jint inputStride,
    jlong outputAddress, jint outputWidth, jint outputHeight,
    jint outputStride, jint pixelLayout) {
    (void)environment; (void)clazz;
    uint8_t *input = (uint8_t *)(uintptr_t)inputAddress;
    uint8_t *output = (uint8_t *)(uintptr_t)outputAddress;
    int channels = PocketJSTBChannels(pixelLayout);
    if (!input || !output || channels == 0 || inputWidth <= 0 || inputHeight <= 0 ||
        outputWidth <= 0 || outputHeight <= 0) return 0;
    if (inputStride == 0) inputStride = inputWidth * channels;
    if (outputStride == 0) outputStride = outputWidth * channels;

    for (int y = 0; y < outputHeight; y++) {
        double sourceY = ((y + 0.5) * inputHeight / outputHeight) - 0.5;
        int y0 = (int)floor(sourceY);
        double fy = sourceY - y0;
        if (y0 < 0) { y0 = 0; fy = 0.0; }
        int y1 = y0 + 1;
        if (y1 >= inputHeight) y1 = inputHeight - 1;
        for (int x = 0; x < outputWidth; x++) {
            double sourceX = ((x + 0.5) * inputWidth / outputWidth) - 0.5;
            int x0 = (int)floor(sourceX);
            double fx = sourceX - x0;
            if (x0 < 0) { x0 = 0; fx = 0.0; }
            int x1 = x0 + 1;
            if (x1 >= inputWidth) x1 = inputWidth - 1;
            for (int channel = 0; channel < channels; channel++) {
                double top = input[y0 * inputStride + x0 * channels + channel] * (1.0 - fx) +
                    input[y0 * inputStride + x1 * channels + channel] * fx;
                double bottom = input[y1 * inputStride + x0 * channels + channel] * (1.0 - fx) +
                    input[y1 * inputStride + x1 * channels + channel] * fx;
                double value = top * (1.0 - fy) + bottom * fy;
                output[y * outputStride + x * channels + channel] =
                    (uint8_t)(value < 0.0 ? 0.0 : (value > 255.0 ? 255.0 : value + 0.5));
            }
        }
    }
    fprintf(stderr, "[PocketJ 26.x] Used iOS STB image-resize compatibility path.\n");
    return outputAddress;
}
