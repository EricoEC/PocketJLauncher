/*
 * Copyright LWJGL. All rights reserved.
 * License terms: https://www.lwjgl.org/license
 */
package org.lwjgl.system;

import org.lwjgl.PointerBuffer;
import org.lwjgl.system.libffi.FFICIF;
import org.lwjgl.system.libffi.FFIClosure;

import java.lang.reflect.Method;
import java.util.concurrent.ConcurrentHashMap;

import static org.lwjgl.system.APIUtil.apiLog;
import static org.lwjgl.system.MemoryStack.stackPush;
import static org.lwjgl.system.MemoryUtil.memGlobalRefToObject;
import static org.lwjgl.system.jni.JNINativeInterface.DeleteGlobalRef;
import static org.lwjgl.system.jni.JNINativeInterface.NewGlobalRef;
import static org.lwjgl.system.libffi.LibFFI.*;

/** LWJGL 3.4.1 upcalls adapted to the PocketJ iOS native ABI. */
final class Upcalls {
    static {
        System.loadLibrary("lwjgl341compat");
    }

    private static final boolean DEBUG_ALLOCATOR =
        Configuration.DEBUG_MEMORY_ALLOCATOR.get(false);

    // Upstream 3.4.1 asks libffi for this value through a new native method.
    // PocketJ's iOS libffi already exposes the exact generated struct size via
    // FFIClosure.SIZEOF, so use it directly and keep old releases untouched.
    private static final int CLOSURE_SIZE = FFIClosure.SIZEOF;

    private static final ClosureRegistry CLOSURE_REGISTRY;

    private interface ClosureRegistry {
        void put(long executableAddress, FFIClosure closure);
        FFIClosure get(long executableAddress);
        FFIClosure remove(long executableAddress);
    }

    static {
        try (MemoryStack stack = stackPush()) {
            PointerBuffer code = stack.mallocPointer(1);
            FFIClosure closure = ffi_closure_alloc(CLOSURE_SIZE, code);
            if (closure == null) throw new OutOfMemoryError();

            if (code.get(0) == closure.address()) {
                apiLog("Closure Registry: simple");
                CLOSURE_REGISTRY = new ClosureRegistry() {
                    public void put(long executableAddress, FFIClosure closure) { }
                    public FFIClosure get(long executableAddress) {
                        return FFIClosure.create(executableAddress);
                    }
                    public FFIClosure remove(long executableAddress) {
                        return get(executableAddress);
                    }
                };
            } else {
                apiLog("Closure Registry: ConcurrentHashMap");
                CLOSURE_REGISTRY = new ClosureRegistry() {
                    private final ConcurrentHashMap<Long, FFIClosure> map =
                        new ConcurrentHashMap<>();
                    public void put(long executableAddress, FFIClosure closure) {
                        map.put(executableAddress, closure);
                    }
                    public FFIClosure get(long executableAddress) {
                        return map.get(executableAddress);
                    }
                    public FFIClosure remove(long executableAddress) {
                        return map.remove(executableAddress);
                    }
                };
            }
            ffi_closure_free(closure);
        }
    }

    private static final long CALLBACK_HANDLER;
    static {
        try {
            CALLBACK_HANDLER = getCallbackHandler(
                CallbackI.class.getDeclaredMethod("callback", long.class, long.class));
        } catch (Exception e) {
            throw new IllegalStateException(
                "Failed to initialize the native callback handler.", e);
        }
        MemoryUtil.getAllocator();
    }

    private Upcalls() { }
    private static native long getCallbackHandler(Method callback);

    static long upcallCreate(Callback.Descriptor descriptor, Object instance) {
        FFIClosure closure;
        long executableAddress;
        try (MemoryStack stack = stackPush()) {
            PointerBuffer code = stack.mallocPointer(1);
            closure = ffi_closure_alloc(CLOSURE_SIZE, code);
            if (closure == null) throw new OutOfMemoryError();
            executableAddress = code.get(0);
            if (DEBUG_ALLOCATOR) {
                MemoryManage.DebugAllocator.track(executableAddress, CLOSURE_SIZE);
            }
        }

        long userData = NewGlobalRef(instance);
        int result = ffi_prep_closure_loc(closure, descriptor.cif,
            CALLBACK_HANDLER, userData, executableAddress);
        if (result != FFI_OK) {
            DeleteGlobalRef(userData);
            ffi_closure_free(closure);
            throw new RuntimeException("Failed to prepare the libffi closure");
        }
        CLOSURE_REGISTRY.put(executableAddress, closure);
        return executableAddress;
    }

    static <T extends CallbackI> T upcallGet(long functionPointer) {
        return memGlobalRefToObject(
            CLOSURE_REGISTRY.get(functionPointer).user_data());
    }

    static void upcallFree(long functionPointer) {
        if (DEBUG_ALLOCATOR) MemoryManage.DebugAllocator.untrack(functionPointer);
        FFIClosure closure = CLOSURE_REGISTRY.remove(functionPointer);
        DeleteGlobalRef(closure.user_data());
        ffi_closure_free(closure);
    }
}
