package com.mojang.text2speech;

import java.util.Locale;

/**
 * API-compatible platform descriptor retained by Mojang's text2speech jar.
 * PocketJ uses a silent narrator on iOS, but mods may still link this type.
 */
public enum OperatingSystem {
    LINUX("linux"),
    WINDOWS("win"),
    MAC_OS("mac"),
    UNSUPPORTED(null);

    private final String detectWith;

    OperatingSystem(String detectWith) {
        this.detectWith = detectWith;
    }

    public static OperatingSystem get() {
        String osName = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        for (OperatingSystem system : values()) {
            if (system.detectWith != null && osName.contains(system.detectWith)) {
                return system;
            }
        }
        return UNSUPPORTED;
    }
}
