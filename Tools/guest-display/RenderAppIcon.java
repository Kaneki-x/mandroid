import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.os.Looper;
import android.util.Base64;
import java.io.ByteArrayOutputStream;

/** Resolve resources in Android, including adaptive/vector icons and split APKs. */
public final class RenderAppIcon {
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("expected package name");
        Looper.prepareMainLooper();
        Class<?> activityThread = Class.forName("android.app.ActivityThread");
        Object thread = activityThread.getMethod("systemMain").invoke(null);
        Context context = (Context) activityThread.getMethod("getSystemContext").invoke(thread);
        PackageManager pm = context.getPackageManager();
        Intent launch = pm.getLaunchIntentForPackage(args[0]);
        Drawable icon = launch != null && launch.getComponent() != null
                ? pm.getActivityIcon(launch.getComponent()) : pm.getApplicationIcon(args[0]);
        Bitmap bitmap = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888);
        icon.setBounds(0, 0, 256, 256);
        icon.draw(new Canvas(bitmap));
        ByteArrayOutputStream png = new ByteArrayOutputStream();
        if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, png)) {
            throw new IllegalStateException("PNG encoding failed");
        }
        System.out.println(Base64.encodeToString(png.toByteArray(), Base64.NO_WRAP));
        System.exit(0);
    }
}
