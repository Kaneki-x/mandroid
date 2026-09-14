package io.github.madeye.mandroid.proxy;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;
import java.nio.charset.StandardCharsets;

/** Shell-only acknowledgement; proxy configuration is never exposed to Android apps. */
public final class StatusProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }
    @Override public Bundle call(String method, String arg, Bundle extras) {
        if (!"status".equals(method)) throw new IllegalArgumentException("Unknown method");
        String status = getContext().getSharedPreferences("proxy", 0).getString("status", "{}");
        Bundle result = new Bundle();
        result.putString("status", Base64.encodeToString(status.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
        return result;
    }
    @Override public String getType(Uri uri) { return null; }
    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
