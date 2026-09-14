package io.github.madeye.mandroid.proxy;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.ProxyInfo;
import android.net.VpnService;
import android.os.ParcelFileDescriptor;
import android.system.OsConstants;
import android.util.Base64;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import org.json.JSONObject;

/** VPN-scoped HTTP proxy recommendation, with upstream selection by connection owner UID.
 * No IP routes are captured: apps that ignore Android HTTP proxy settings remain direct.
 * HTTP requests and HTTPS CONNECT tunnels pass through unchanged; TLS is never intercepted.
 */
public final class ProxyService extends VpnService {
    private Session current;

    static JSONObject decode(String config) throws Exception {
        return new JSONObject(new String(Base64.decode(config, Base64.DEFAULT), StandardCharsets.UTF_8));
    }

    static void report(Context context, String config, String error, boolean active) {
        try {
            JSONObject status = new JSONObject();
            status.put("revision", config == null ? "" : decode(config).optString("revision"));
            status.put("error", error == null ? "" : error);
            status.put("active", active);
            context.getSharedPreferences("proxy", 0).edit().putString("status", status.toString()).commit();
        } catch (Exception ignored) { }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String config = intent == null ? null : intent.getStringExtra("config");
        NotificationManager notifications = getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(new NotificationChannel("proxy", "App HTTP proxies", NotificationManager.IMPORTANCE_LOW));
        startForeground(1, new Notification.Builder(this, "proxy")
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle("Mandroid app HTTP proxies").setOngoing(true).build());
        Session next = null;
        try {
            JSONObject entries = decode(config).getJSONObject("apps");
            if (entries.length() == 0) {
                if (current != null) current.close();
                current = null;
                report(this, config, null, false);
                stopSelf();
                return START_NOT_STICKY;
            }
            next = new Session(entries);
            next.establish();
            Session previous = current;
            current = next;
            if (previous != null) previous.close();
            next.start();
            report(this, config, null, true);
        } catch (Exception error) {
            if (next != null) next.close();
            report(this, config, error.getMessage(), current != null);
            if (current == null) stopSelf();
        }
        // The host reapplies saved settings after each emulator startup.
        return START_NOT_STICKY;
    }

    @Override public void onRevoke() { if (current != null) current.close(); current = null; stopSelf(); }
    @Override public void onDestroy() { if (current != null) current.close(); current = null; super.onDestroy(); }

    private final class Session {
        final Map<Integer, InetSocketAddress> endpoints = new HashMap<>();
        final Set<Socket> sockets = ConcurrentHashMap.newKeySet();
        final Semaphore capacity = new Semaphore(32);
        final JSONObject entries;
        ServerSocket listener;
        ParcelFileDescriptor tunnel;
        volatile boolean closed;

        Session(JSONObject entries) throws Exception {
            this.entries = entries;
            for (java.util.Iterator<String> keys = entries.keys(); keys.hasNext();) {
                String pkg = keys.next();
                JSONObject item = entries.getJSONObject(pkg);
                String host = item.getString("host");
                int port = item.getInt("port");
                if (host.isEmpty() || port < 1 || port > 65535) throw new IllegalArgumentException("Invalid HTTP proxy endpoint");
                if (pkg.equals(getPackageName())) throw new IllegalArgumentException("Cannot proxy the proxy helper");
                int uid = getPackageManager().getApplicationInfo(pkg, 0).uid;
                InetSocketAddress endpoint = InetSocketAddress.createUnresolved(host, port);
                InetSocketAddress previous = endpoints.put(uid, endpoint);
                if (previous != null && !previous.equals(endpoint)) {
                    throw new IllegalArgumentException("Apps sharing an Android UID must use the same HTTP proxy");
                }
            }
        }

        void establish() throws Exception {
            listener = new ServerSocket(0, 32, InetAddress.getByName("127.0.0.1"));
            Builder builder = new Builder().setSession("Mandroid app HTTP proxies")
                    .addAddress("192.0.2.1", 32).allowFamily(OsConstants.AF_INET).allowFamily(OsConstants.AF_INET6)
                    .setHttpProxy(ProxyInfo.buildDirectProxy("127.0.0.1", listener.getLocalPort()));
            for (java.util.Iterator<String> keys = entries.keys(); keys.hasNext();) builder.addAllowedApplication(keys.next());
            tunnel = builder.establish();
            if (tunnel == null) throw new IllegalStateException("Android VPN permission was revoked");
        }

        void start() {
            new Thread(() -> {
                while (!closed) {
                    try {
                        Socket client = listener.accept();
                        if (!capacity.tryAcquire()) { client.close(); continue; }
                        sockets.add(client);
                        if (closed) { client.close(); sockets.remove(client); capacity.release(); break; }
                        new Thread(() -> relay(client), "mandroid-http-client").start();
                    } catch (Exception error) { if (!closed) close(); }
                }
            }, "mandroid-http-listener").start();
        }

        void relay(Socket client) {
            Socket upstream = new Socket();
            sockets.add(upstream);
            try {
                if (closed) return;
                int uid = getSystemService(ConnectivityManager.class).getConnectionOwnerUid(OsConstants.IPPROTO_TCP,
                        (InetSocketAddress) client.getRemoteSocketAddress(), (InetSocketAddress) client.getLocalSocketAddress());
                InetSocketAddress endpoint = endpoints.get(uid);
                if (endpoint == null) throw new SecurityException("Unconfigured app tried to use the proxy");
                // Binding creates the file descriptor that VpnService.protect requires.
                upstream.bind(new InetSocketAddress(0));
                if (!protect(upstream)) throw new IllegalStateException("Could not protect proxy connection");
                upstream.connect(new InetSocketAddress(endpoint.getHostString(), endpoint.getPort()), 10000);
                upstream.setSoTimeout(120000);
                client.setSoTimeout(120000);
                Thread response = new Thread(() -> {
                    try { copy(upstream.getInputStream(), client.getOutputStream()); client.shutdownOutput(); }
                    catch (Exception error) { closeSocket(client); closeSocket(upstream); }
                }, "mandroid-http-response");
                response.start();
                try { copy(client.getInputStream(), upstream.getOutputStream()); upstream.shutdownOutput(); }
                catch (Exception error) { closeSocket(client); closeSocket(upstream); }
                response.join(125000);
            } catch (Exception error) {
                android.util.Log.w("MandroidProxy", "Proxy connection failed: " + error);
                // Never fall back to a different app's proxy or a direct destination.
            } finally {
                closeSocket(client); closeSocket(upstream);
                sockets.remove(client); sockets.remove(upstream);
                capacity.release();
            }
        }

        void close() {
            closed = true;
            try { if (listener != null) listener.close(); } catch (Exception ignored) { }
            try { if (tunnel != null) tunnel.close(); } catch (Exception ignored) { }
            for (Socket socket : sockets) closeSocket(socket);
        }
    }

    static void closeSocket(Socket socket) { try { socket.close(); } catch (Exception ignored) { } }
    static void copy(InputStream input, OutputStream output) throws Exception {
        byte[] buffer = new byte[16384];
        int count;
        while ((count = input.read(buffer)) != -1) { output.write(buffer, 0, count); output.flush(); }
    }
}
