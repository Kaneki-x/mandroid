/** Sets native media volume as the shell package that owns this app_process.
 * Android's media_session command uses com.android.server.media instead,
 * which can cause AudioService to silently reject the change.
 */
public final class SetMediaVolume {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("expected volume index");
        int level = Integer.parseInt(args[0]);
        Object binder = Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "audio");
        Object service = Class.forName("android.media.IAudioService$Stub")
                .getMethod("asInterface", Class.forName("android.os.IBinder"))
                .invoke(null, binder);
        Class<?> api = Class.forName("android.media.IAudioService");
        int min = (Integer) api.getMethod("getStreamMinVolume", int.class).invoke(service, 3);
        int max = (Integer) api.getMethod("getStreamMaxVolume", int.class).invoke(service, 3);
        if (level < min || level > max) throw new IllegalArgumentException("volume out of range");
        api.getMethod("setStreamVolume", int.class, int.class, int.class, String.class)
                .invoke(service, 3, level, 0, "com.android.shell");
        int actual = (Integer) api.getMethod("getStreamVolume", int.class).invoke(service, 3);
        if (actual != level) throw new IllegalStateException("media volume was not applied");
        System.out.println("media-volume-ready");
        System.exit(0);
    }
}
