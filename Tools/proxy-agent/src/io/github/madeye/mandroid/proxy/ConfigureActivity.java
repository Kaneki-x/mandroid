package io.github.madeye.mandroid.proxy;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.os.Bundle;

/** The shell-only entry point used by the macOS host. */
public final class ConfigureActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        String config = getIntent().getStringExtra("config");
        try {
            if (config == null) throw new IllegalArgumentException("Missing proxy configuration");
            if (ProxyService.decode(config).getJSONObject("apps").length() > 0 && VpnService.prepare(this) != null) throw new IllegalStateException("Android VPN permission is not available");
            startForegroundService(new Intent(this, ProxyService.class).putExtra("config", config));
        } catch (Exception error) {
            ProxyService.report(this, config, error.getMessage(), false);
        }
        finish();
    }
}
