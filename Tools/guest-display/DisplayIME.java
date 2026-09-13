/** Tiny app_process entry point: use the guest framework's versioned Binder
 * proxy instead of hard-coding IWindowManager transaction numbers on the host.
 * No APK, installed service, root access, or third-party dependency is needed.
 */
public final class DisplayIME {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("expected display id");
        int displayId = Integer.parseInt(args[0]);
        if (displayId <= 0) throw new IllegalArgumentException("expected secondary display");
        Object binder = Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "window");
        Object manager = Class.forName("android.view.IWindowManager$Stub")
                .getMethod("asInterface", Class.forName("android.os.IBinder"))
                .invoke(null, binder);
        Class<?> api = Class.forName("android.view.IWindowManager");
        // DISPLAY_IME_POLICY_LOCAL: bind the IME to the editor's display.
        api.getMethod("setDisplayImePolicy", int.class, int.class).invoke(manager, displayId, 0);
        int policy = (Integer) api.getMethod("getDisplayImePolicy", int.class).invoke(manager, displayId);
        if (policy != 0) throw new IllegalStateException("local IME policy was not applied");
        System.out.println("local-ime-ready");
    }
}
