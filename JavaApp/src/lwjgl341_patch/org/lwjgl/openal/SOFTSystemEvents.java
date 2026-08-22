package org.lwjgl.openal;

import java.nio.IntBuffer;

import static org.lwjgl.system.Checks.lengthSafe;
import static org.lwjgl.system.Checks.remainingSafe;
import static org.lwjgl.system.JNI.invokeI;
import static org.lwjgl.system.JNI.invokePPV;
import static org.lwjgl.system.JNI.invokePZ;
import static org.lwjgl.system.MemoryUtil.memAddressSafe;

/** iOS-safe LWJGL 3.4 binding for the optional ALC_SOFT_system_events API. */
public class SOFTSystemEvents {
    public static final int ALC_EVENT_TYPE_DEFAULT_DEVICE_CHANGED_SOFT = 6614;
    public static final int ALC_EVENT_TYPE_DEVICE_ADDED_SOFT = 6615;
    public static final int ALC_EVENT_TYPE_DEVICE_REMOVED_SOFT = 6616;
    public static final int ALC_PLAYBACK_DEVICE_SOFT = 6612;
    public static final int ALC_CAPTURE_DEVICE_SOFT = 6613;
    public static final int ALC_EVENT_SUPPORTED_SOFT = 6617;
    public static final int ALC_EVENT_NOT_SUPPORTED_SOFT = 6618;

    protected SOFTSystemEvents() { throw new UnsupportedOperationException(); }

    public static int alcEventIsSupportedSOFT(int eventType, int deviceType) {
        long function = ALC.getICD().alcEventIsSupportedSOFT;
        return function == 0L
            ? ALC_EVENT_NOT_SUPPORTED_SOFT
            : invokeI(eventType, deviceType, function);
    }

    public static boolean nalcEventControlSOFT(int count, long types, boolean enable) {
        long function = ALC.getICD().alcEventControlSOFT;
        return function != 0L && invokePZ(count, types, enable, function);
    }

    public static boolean alcEventControlSOFT(IntBuffer types, boolean enable) {
        return nalcEventControlSOFT(remainingSafe(types), memAddressSafe(types), enable);
    }

    public static void nalcEventCallbackSOFT(long callback, long userParam) {
        long function = ALC.getICD().alcEventCallbackSOFT;
        if (function != 0L) invokePPV(callback, userParam, function);
    }

    public static void alcEventCallbackSOFT(SOFTSystemEventProcI callback, long userParam) {
        nalcEventCallbackSOFT(memAddressSafe(callback), userParam);
    }

    public static boolean alcEventControlSOFT(int[] types, boolean enable) {
        long function = ALC.getICD().alcEventControlSOFT;
        return function != 0L && invokePZ(lengthSafe(types), types, enable, function);
    }
}
