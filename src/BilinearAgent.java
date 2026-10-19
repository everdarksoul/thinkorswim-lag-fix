import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;

/**
 * In-memory bytecode patch for thinkorswim's chart renderer.
 *
 * com.devexperts.toschart.GraphicsUtils.enableAntialiasing() hardcodes
 * RenderingHints.VALUE_INTERPOLATION_BICUBIC, which forces Java2D to do a
 * full-screen software resample on the AWT-EventQueue on every chart repaint
 * (the GPU pipelines cannot accelerate bicubic). We rewrite that one constant
 * to VALUE_INTERPOLATION_BILINEAR as the class is loaded, so:
 *   - no jar is modified (vendor signatures stay valid), and
 *   - the change survives app updates (it is applied at load time).
 */
public class BilinearAgent {

    private static final String TARGET = "com/devexperts/toschart/GraphicsUtils";
    private static final byte[] OLD = "VALUE_INTERPOLATION_BICUBIC".getBytes();
    private static final byte[] NEW = "VALUE_INTERPOLATION_BILINEAR".getBytes();

    public static void premain(String args, Instrumentation inst) {
        inst.addTransformer(new ClassFileTransformer() {
            @Override
            public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                                    ProtectionDomain protectionDomain, byte[] classfileBuffer)
                    throws IllegalClassFormatException {
                if (!TARGET.equals(className)) {
                    return null;
                }
                byte[] patched = patchUtf8Constant(classfileBuffer, OLD, NEW);
                if (patched != null) {
                    System.err.println("[BilinearAgent] patched " + TARGET
                        + ": INTERPOLATION_BICUBIC -> INTERPOLATION_BILINEAR");
                } else {
                    System.err.println("[BilinearAgent] WARN: " + TARGET
                        + " already patched or pattern not found (maybe TOS updated)");
                }
                return patched;
            }
        }, false);
        System.err.println("[BilinearAgent] loaded");
    }

    /**
     * Class-file constant pool: CONSTANT_Utf8 is u2 length + bytes.
     * Find the exact length-prefixed entry and replace, growing the entry
     * by (newLen - oldLen). Class files have no absolute offsets, so the
     * shift is safe.
     */
    private static byte[] patchUtf8Constant(byte[] cf, byte[] oldBytes, byte[] newBytes) {
        for (int i = 0; i <= cf.length - oldBytes.length - 2; i++) {
            int len = ((cf[i] & 0xff) << 8) | (cf[i + 1] & 0xff);
            if (len != oldBytes.length) {
                continue;
            }
            boolean match = true;
            for (int j = 0; j < oldBytes.length; j++) {
                if (cf[i + 2 + j] != oldBytes[j]) {
                    match = false;
                    break;
                }
            }
            if (!match) {
                continue;
            }
            byte[] out = new byte[cf.length + (newBytes.length - oldBytes.length)];
            System.arraycopy(cf, 0, out, 0, i);
            out[i] = (byte) (newBytes.length >> 8);
            out[i + 1] = (byte) newBytes.length;
            System.arraycopy(newBytes, 0, out, i + 2, newBytes.length);
            System.arraycopy(cf, i + 2 + oldBytes.length, out,
                    i + 2 + newBytes.length, cf.length - (i + 2 + oldBytes.length));
            return out;
        }
        return null;
    }
}
