package net.kdt.patchjna;

import java.io.*;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.InvocationTargetException;
import java.security.ProtectionDomain;

public class PatchJNAAgent implements ClassFileTransformer {
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
    ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
        byte[] transformeredByteCode = classfileBuffer;
        if (className.equals("com/mojang/blaze3d/vertex/UberGpuBuffer$UberGpuBufferHeap") &&
            "1".equals(System.getenv("POCKETJ_ANGLE_26_TEXTURE_BUFFER_WORKAROUND"))) {
            try {
                transformeredByteCode = reduceModernGpuHeap(classfileBuffer);
                System.out.println("[PocketJ 26.x] Reduced desktop 128 MB GPU heap to 16 MB for iOS Metal");
            } catch (Exception e) {
                System.err.println("[PocketJ 26.x] GPU heap transformer failed: " + e);
                e.printStackTrace();
            }
        }
        if ((className.equals("org/lwjgl/opengl/GL31C") ||
             className.equals("org/lwjgl/opengl/GL43C") ||
             className.equals("org/lwjgl/opengl/GL45C")) &&
            "1".equals(System.getenv("POCKETJ_ANGLE_26_TEXTURE_BUFFER_WORKAROUND"))) {
            try {
                transformeredByteCode = disableTextureBufferNatives(className, classfileBuffer);
                System.out.println("[PocketJ 26.x] Disabled unused texture-buffer bindings in " + className);
            } catch (Exception e) {
                System.err.println("[PocketJ 26.x] Texture-buffer transformer failed for " + className + ": " + e);
                e.printStackTrace();
            }
        }
        if (className.equals("com/sun/jna/Platform")) {
            System.out.println("PatchJNAAgent: Replacing class");
            try {
                InputStream inputStream = PatchJNAAgent.class.getClassLoader().getResourceAsStream("com/sun/jna/Platform.class.patch");
                transformeredByteCode = new byte[inputStream.available()];
                DataInputStream dataInputStream = new DataInputStream(inputStream);
                dataInputStream.readFully(transformeredByteCode);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        if (className.equals("com/mojang/blaze3d/platform/MacosUtil")) {
            try {
                transformeredByteCode = disableMacosWindowMenuJNA(classfileBuffer);
                System.out.println("[PocketJ iOS] Skipped desktop macOS window-menu integration");
            } catch (Exception e) {
                System.err.println("[PocketJ iOS] MacosUtil patch failed: " + e);
                e.printStackTrace();
            }
        }
        if (className.equals("org/lwjgl/util/shaderc/Shaderc$Functions")) {
            try {
                transformeredByteCode = aliasUnavailableShadercFunction(classfileBuffer);
                System.out.println("[PocketJ 26.3] Using compatible shaderc function table for older bundled shaderc");
            } catch (Exception e) {
                System.err.println("[PocketJ 26.3] shaderc function-table patch failed: " + e);
                e.printStackTrace();
            }
        }
        if (className.equals("org/lwjgl/util/shaderc/Shaderc")) {
            try {
                transformeredByteCode = disableUnavailableShadercMaxIdBound(classfileBuffer);
                System.out.println("[PocketJ 26.3] Skipped max-id-bound option unsupported by bundled shaderc");
            } catch (Exception e) {
                System.err.println("[PocketJ 26.3] shaderc max-id-bound patch failed: " + e);
                e.printStackTrace();
            }
        }
        return transformeredByteCode;
    }

    /**
     * LWJGL 3.4.1 added this shaderc entry point, while PocketJ's bundled
     * shaderc predates it. Keep LWJGL's function table initialization alive by
     * resolving that field to the existing preserve-bindings entry point; the
     * public max-id-bound wrapper is separately replaced with a no-op, so this
     * compatibility address is never invoked with the wrong signature.
     */
    private static byte[] aliasUnavailableShadercFunction(byte[] source) throws IOException {
        if ((int)u4(source, 0) != 0xCAFEBABE) return source;
        int constantCount = u2(source, 8);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(source.length + 16);
        DataOutputStream out = new DataOutputStream(bytes);
        out.write(source, 0, 8);
        writeU2(out, constantCount);
        int offset = 10;
        boolean changed = false;
        for (int i = 1; i < constantCount; i++) {
            int start = offset;
            int tag = source[offset++] & 0xff;
            if (tag == 1) {
                int length = u2(source, offset);
                offset += 2;
                String value = new String(source, offset, length, "UTF-8");
                offset += length;
                if ("shaderc_compile_options_set_max_id_bound".equals(value)) {
                    byte[] replacement = "shaderc_compile_options_set_preserve_bindings".getBytes("UTF-8");
                    out.writeByte(1);
                    writeU2(out, replacement.length);
                    out.write(replacement);
                    changed = true;
                } else {
                    out.write(source, start, offset - start);
                }
            } else {
                switch (tag) {
                    case 3: case 4: offset += 4; break;
                    case 5: case 6: offset += 8; i++; break;
                    case 7: case 8: case 16: case 19: case 20: offset += 2; break;
                    case 9: case 10: case 11: case 12: case 17: case 18: offset += 4; break;
                    case 15: offset += 3; break;
                    default: throw new IOException("Unknown class constant " + tag);
                }
                out.write(source, start, offset - start);
            }
        }
        if (!changed) throw new IOException("Missing max-id-bound shaderc function name");
        out.write(source, offset, source.length - offset);
        out.flush();
        return bytes.toByteArray();
    }

    /** The old bundled shaderc has no implementation for this newer LWJGL option. */
    private static byte[] disableUnavailableShadercMaxIdBound(byte[] source) throws IOException {
        if ((int)u4(source, 0) != 0xCAFEBABE) return source;
        int constantCount = u2(source, 8);
        String[] utf8 = new String[constantCount];
        int offset = 10;
        for (int i = 1; i < constantCount; i++) {
            int tag = source[offset++] & 0xff;
            switch (tag) {
                case 1: {
                    int length = u2(source, offset);
                    offset += 2;
                    utf8[i] = new String(source, offset, length, "UTF-8");
                    offset += length;
                    break;
                }
                case 3: case 4: offset += 4; break;
                case 5: case 6: offset += 8; i++; break;
                case 7: case 8: case 16: case 19: case 20: offset += 2; break;
                case 9: case 10: case 11: case 12: case 17: case 18: offset += 4; break;
                case 15: offset += 3; break;
                default: throw new IOException("Unknown class constant " + tag);
            }
        }
        int codeIndex = 0;
        for (int i = 1; i < utf8.length; i++) if ("Code".equals(utf8[i])) { codeIndex = i; break; }
        if (codeIndex == 0) throw new IOException("Code constant missing");

        offset += 6;
        int interfaces = u2(source, offset);
        offset += 2 + interfaces * 2;
        int fields = u2(source, offset);
        offset += 2;
        for (int i = 0; i < fields; i++) offset = skipMember(source, offset);

        int methods = u2(source, offset);
        offset += 2;
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(source.length);
        DataOutputStream out = new DataOutputStream(bytes);
        out.write(source, 0, offset);
        boolean changed = false;
        for (int i = 0; i < methods; i++) {
            int start = offset;
            int nameIndex = u2(source, offset + 2);
            int descriptorIndex = u2(source, offset + 4);
            int attributeCount = u2(source, offset + 6);
            int attributeOffset = offset + 8;
            int end = skipAttributes(source, attributeOffset, attributeCount);
            if ("shaderc_compile_options_set_max_id_bound".equals(utf8[nameIndex]) && "(JI)V".equals(utf8[descriptorIndex])) {
                out.write(source, start, 8);
                for (int a = 0; a < attributeCount; a++) {
                    int name = u2(source, attributeOffset);
                    int length = (int)u4(source, attributeOffset + 2);
                    if (name == codeIndex) {
                        writeU2(out, name);
                        out.writeInt(13);
                        writeU2(out, 0); // max_stack
                        writeU2(out, 3); // long options + int max bound
                        out.writeInt(1);
                        out.writeByte(0xb1); // return
                        writeU2(out, 0); // exception_table_length
                        writeU2(out, 0); // code attributes_count
                    } else {
                        out.write(source, attributeOffset, length + 6);
                    }
                    attributeOffset += length + 6;
                }
                changed = true;
            } else {
                out.write(source, start, end - start);
            }
            offset = end;
        }
        out.write(source, offset, source.length - offset);
        out.flush();
        if (!changed) throw new IOException("max-id-bound wrapper not found");
        return bytes.toByteArray();
    }

    private static int u2(byte[] data, int offset) {
        return ((data[offset] & 0xff) << 8) | (data[offset + 1] & 0xff);
    }

    private static long u4(byte[] data, int offset) {
        return ((long)u2(data, offset) << 16) | u2(data, offset + 2);
    }

    private static void writeU2(DataOutputStream out, int value) throws IOException {
        out.writeShort(value & 0xffff);
    }

    private static int skipAttributes(byte[] data, int offset, int count) {
        for (int i = 0; i < count; i++) {
            offset += 2;
            int length = (int)u4(data, offset);
            offset += 4 + length;
        }
        return offset;
    }

    private static int skipMember(byte[] data, int offset) {
        int attributes = u2(data, offset + 6);
        return skipAttributes(data, offset + 8, attributes);
    }

    private static byte[] reduceModernGpuHeap(byte[] source) throws IOException {
        if ((int)u4(source, 0) != 0xCAFEBABE) return source;
        byte[] patched = source.clone();
        int constantCount = u2(patched, 8);
        int offset = 10;
        int changed = 0;
        for (int i = 1; i < constantCount; i++) {
            int tag = patched[offset++] & 0xff;
            switch (tag) {
                case 1: {
                    int length = u2(patched, offset);
                    offset += 2 + length;
                    break;
                }
                case 3: {
                    if (u4(patched, offset) == 134217728L) {
                        patched[offset] = 0x01;
                        patched[offset + 1] = 0x00;
                        patched[offset + 2] = 0x00;
                        patched[offset + 3] = 0x00;
                        changed++;
                    }
                    offset += 4;
                    break;
                }
                case 4: offset += 4; break;
                case 5: case 6: offset += 8; i++; break;
                case 7: case 8: case 16: case 19: case 20: offset += 2; break;
                case 9: case 10: case 11: case 12: case 17: case 18: offset += 4; break;
                case 15: offset += 3; break;
                default: throw new IOException("Unknown class constant " + tag);
            }
        }
        if (changed == 0) throw new IOException("128 MB GPU heap constant not found");
        return patched;
    }

    private static byte[] disableTextureBufferNatives(String className, byte[] source) throws IOException {
        if ((int)u4(source, 0) != 0xCAFEBABE) return source;
        int constantCount = u2(source, 8);
        String[] utf8 = new String[constantCount];
        int offset = 10;
        for (int i = 1; i < constantCount; i++) {
            int tag = source[offset++] & 0xff;
            switch (tag) {
                case 1: {
                    int length = u2(source, offset);
                    offset += 2;
                    utf8[i] = new String(source, offset, length, "UTF-8");
                    offset += length;
                    break;
                }
                case 3: case 4: offset += 4; break;
                case 5: case 6: offset += 8; i++; break;
                case 7: case 8: case 16: case 19: case 20: offset += 2; break;
                case 9: case 10: case 11: case 12: case 17: case 18: offset += 4; break;
                case 15: offset += 3; break;
                default: throw new IOException("Unknown class constant " + tag);
            }
        }
        int codeIndex = 0;
        for (int i = 1; i < utf8.length; i++) {
            if ("Code".equals(utf8[i])) { codeIndex = i; break; }
        }
        if (codeIndex == 0) throw new IOException("Code constant missing");

        offset += 6;
        int interfaces = u2(source, offset);
        offset += 2 + interfaces * 2;
        int fields = u2(source, offset);
        offset += 2;
        for (int i = 0; i < fields; i++) offset = skipMember(source, offset);

        int methodCountOffset = offset;
        int methods = u2(source, offset);
        offset += 2;
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(source.length + 64);
        DataOutputStream out = new DataOutputStream(bytes);
        out.write(source, 0, offset);
        int changed = 0;
        for (int i = 0; i < methods; i++) {
            int start = offset;
            int access = u2(source, offset);
            int nameIndex = u2(source, offset + 2);
            int descriptorIndex = u2(source, offset + 4);
            int attributeCount = u2(source, offset + 6);
            int end = skipAttributes(source, offset + 8, attributeCount);
            String name = utf8[nameIndex];
            String descriptor = utf8[descriptorIndex];
            boolean target;
            if (className.endsWith("/GL31C")) {
                target = "glTexBuffer".equals(name) && "(III)V".equals(descriptor);
            } else if (className.endsWith("/GL43C")) {
                target = "glTexBufferRange".equals(name) && "(IIIJJ)V".equals(descriptor);
            } else {
                target = ("glTextureBuffer".equals(name) && "(III)V".equals(descriptor)) ||
                    ("glTextureBufferRange".equals(name) && "(IIIJJ)V".equals(descriptor));
            }
            if (!target) {
                out.write(source, start, end - start);
            } else {
                writeU2(out, access & ~0x0100); // remove ACC_NATIVE
                writeU2(out, nameIndex);
                writeU2(out, descriptorIndex);
                writeU2(out, attributeCount + 1);
                out.write(source, offset + 8, end - (offset + 8));
                writeU2(out, codeIndex);
                out.writeInt(13);
                writeU2(out, 0); // max_stack
                writeU2(out, "(IIIJJ)V".equals(descriptor) ? 7 : 3); // max_locals
                out.writeInt(1);
                out.writeByte(0xb1); // return
                writeU2(out, 0);
                writeU2(out, 0);
                changed++;
            }
            offset = end;
        }
        out.write(source, offset, source.length - offset);
        out.flush();
        int expected = className.endsWith("/GL45C") ? 2 : 1;
        if (changed != expected) {
            throw new IOException("Expected " + expected + " texture-buffer method(s), changed " + changed);
        }
        return bytes.toByteArray();
    }

    /**
     * Minecraft 26.3 calls this desktop-only macOS menu routine while creating
     * the SDL window. On iOS, the Objective-C/JNA menu bridge is irrelevant;
     * JNA's extracted macOS dispatch library also cannot be loaded from the
     * writable game container. Replace only this no-argument void method with
     * a return, leaving the rest of MacosUtil and JNA untouched.
     */
    private static byte[] disableMacosWindowMenuJNA(byte[] source) throws IOException {
        if ((int)u4(source, 0) != 0xCAFEBABE) return source;
        int constantCount = u2(source, 8);
        String[] utf8 = new String[constantCount];
        int offset = 10;
        for (int i = 1; i < constantCount; i++) {
            int tag = source[offset++] & 0xff;
            switch (tag) {
                case 1: {
                    int length = u2(source, offset);
                    offset += 2;
                    utf8[i] = new String(source, offset, length, "UTF-8");
                    offset += length;
                    break;
                }
                case 3: case 4: offset += 4; break;
                case 5: case 6: offset += 8; i++; break;
                case 7: case 8: case 16: case 19: case 20: offset += 2; break;
                case 9: case 10: case 11: case 12: case 17: case 18: offset += 4; break;
                case 15: offset += 3; break;
                default: throw new IOException("Unknown class constant " + tag);
            }
        }
        int codeIndex = 0;
        for (int i = 1; i < utf8.length; i++) {
            if ("Code".equals(utf8[i])) { codeIndex = i; break; }
        }
        if (codeIndex == 0) throw new IOException("Code constant missing");

        offset += 6;
        int interfaces = u2(source, offset);
        offset += 2 + interfaces * 2;
        int fields = u2(source, offset);
        offset += 2;
        for (int i = 0; i < fields; i++) offset = skipMember(source, offset);

        int methods = u2(source, offset);
        offset += 2;
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(source.length);
        DataOutputStream out = new DataOutputStream(bytes);
        out.write(source, 0, offset);
        boolean changed = false;
        for (int i = 0; i < methods; i++) {
            int start = offset;
            int access = u2(source, offset);
            int nameIndex = u2(source, offset + 2);
            int descriptorIndex = u2(source, offset + 4);
            int attributeCount = u2(source, offset + 6);
            int attributesOffset = offset + 8;
            int end = skipAttributes(source, attributesOffset, attributeCount);
            boolean target = "disableCloseWindowMenuItem".equals(utf8[nameIndex]) &&
                "()V".equals(utf8[descriptorIndex]);
            if (!target) {
                out.write(source, start, end - start);
            } else {
                if (changed) throw new IOException("Duplicate MacosUtil target method");
                writeU2(out, access);
                writeU2(out, nameIndex);
                writeU2(out, descriptorIndex);
                int outputAttributes = 1;
                int attributeOffset = attributesOffset;
                for (int attribute = 0; attribute < attributeCount; attribute++) {
                    int attributeName = u2(source, attributeOffset);
                    int attributeLength = (int)u4(source, attributeOffset + 2);
                    if (attributeName != codeIndex) outputAttributes++;
                    attributeOffset += 6 + attributeLength;
                }
                writeU2(out, outputAttributes);
                attributeOffset = attributesOffset;
                for (int attribute = 0; attribute < attributeCount; attribute++) {
                    int attributeName = u2(source, attributeOffset);
                    int attributeLength = (int)u4(source, attributeOffset + 2);
                    if (attributeName != codeIndex) {
                        out.write(source, attributeOffset, 6 + attributeLength);
                    }
                    attributeOffset += 6 + attributeLength;
                }
                writeU2(out, codeIndex);
                out.writeInt(13);
                writeU2(out, 0); // max_stack
                writeU2(out, 0); // max_locals
                out.writeInt(1);
                out.writeByte(0xb1); // return
                writeU2(out, 0); // exception_table_length
                writeU2(out, 0); // code attributes_count
                changed = true;
            }
            offset = end;
        }
        out.write(source, offset, source.length - offset);
        out.flush();
        if (!changed) throw new IOException("MacosUtil target method not found");
        return bytes.toByteArray();
    }

    public static void premain(String args, Instrumentation instrumentation) {
        System.out.println("PatchJNAAgent: premain called");
        instrumentation.addTransformer(new PatchJNAAgent());
    }
}
