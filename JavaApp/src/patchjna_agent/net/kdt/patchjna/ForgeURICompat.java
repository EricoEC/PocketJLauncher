package net.kdt.patchjna;

import java.net.URI;
import java.nio.file.Path;
import java.nio.file.Paths;

public final class ForgeURICompat {
    private ForgeURICompat() {}

    public static Path pathOf(URI uri) {
        try {
            return Paths.get(uri);
        } catch (IllegalArgumentException original) {
            String value = uri.toASCIIString();
            StringBuilder repaired = new StringBuilder(value.length() + 8);
            for (int i = 0; i < value.length(); i++) {
                char character = value.charAt(i);
                if (character == '%' &&
                    (i + 2 >= value.length() || !isHex(value.charAt(i + 1)) || !isHex(value.charAt(i + 2)))) {
                    repaired.append("%25");
                } else {
                    repaired.append(character);
                }
            }
            URI fixed = URI.create(repaired.toString());
            System.out.println("[PocketJ Forge] Repaired invalid SecureJar URI: " + value + " -> " + fixed);
            return Paths.get(fixed);
        }
    }

    private static boolean isHex(char value) {
        return (value >= '0' && value <= '9') ||
            (value >= 'a' && value <= 'f') ||
            (value >= 'A' && value <= 'F');
    }
}
