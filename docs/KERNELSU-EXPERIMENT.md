# KernelSU emulator experiment

Date: 2026-09-17. Experimental, not a supported Play Integrity workaround.

This is the historical manual experiment. For the implemented, opt-in Settings
feature, supported image, and stock recovery steps, see [KernelSU settings](KERNELSU.md).
The feature does not enable this experiment's shell-root diagnostic option.

## Environment and isolation

- Google Play ARM64 system image: Android 36.1, revision 4.
- Guest kernel: `6.12.38-android16-5-gbb9513914902-ab13996879-4k`.
- KernelSU: official v3.3.0, kernel version code 32601.
- Disposable data root: `~/Library/Caches/Mandroid-kernelsu-experiment`.
- Fresh `lab` AVD; console port 5580; private ADB server port 15081.
- Network for the comparison: emulator `-http-proxy http://127.0.0.1:7880`
  plus Android global HTTP proxy `10.0.2.2:7880`, both referring to the
  user-specified host proxy. Initial unproxied requests had connectivity
  failures and are not used as a clean integrity comparison.
- System-image files were cloned with APFS copy-on-write. The normal AVD's
  userdata and Google account were not copied. Emulator and platform-tools
  binaries are shared read-only through symlinks.
- Original and cloned kernel, ramdisk, system, and vendor image SHA-256 hashes
  matched after the rooted boot. Hashes are retained in
  `stock-image-hashes.json` under the disposable root.

## Confirmed root result

The current KernelSU release supplies an `android16-6.12` ARM64 module but no
replacement GKI kernel. Its macOS `ksud boot-patch --ramdisk` explicitly
supports AVD ramdisks. This worked with the stock emulator kernel, using:

```sh
./ksud-aarch64-apple-darwin boot-patch --ramdisk \
  -b sdk/system-images/android-36.1/google_apis_playstore/arm64-v8a/ramdisk.img \
  -m lkm-aarch64-android16-6.12_kernelsu.ko \
  -i ksuinit-aarch64 --kmi android16-6.12 --allow-shell \
  -o . --out-name ramdisk-kernelsu.img
```

Commands above run inside the disposable root. The emulator receives
`-ramdisk <absolute-path>/ramdisk-kernelsu.img`, `-no-snapshot`, and the
isolated SDK/AVD/home environment. `--allow-shell` is for this local diagnostic
environment; it grants the ADB shell root access.

The module was compiled with vermagic `6.12.76-4k`, but successfully loaded
on this specific `6.12.38` guest. This is measured compatibility for these
artifacts, not a guarantee for other kernel releases.

After installing and opening the official KernelSU Manager APK:

- `sys.boot_completed` was `1`.
- Manager displayed **Working**, **LKM**, and version **32601-2**.
- `su -c id` returned `uid=0(root) ... context=u:r:ksu:s0`.
- `getenforce` returned **Enforcing**.

All downloaded KernelSU artifacts and the TrickyStore ZIP were checked against
the release API's published SHA-256 digests before use.

## Evidence

Logs, screenshots, release metadata, and downloaded artifacts are retained
under the disposable root. Initial evidence includes `stock-guest.txt`,
`stock-boot.log`, `patch.log`, `kernelsu-boot.log`,
`root-verification.txt`, and `kernelsu-manager.png`.

## Integrity checks

Checker: official GitHub release `spic-v1.4.0.apk`, package
`com.henrikherzig.playintegritychecker`. It was sideloaded into the fresh
AVD, without a Google account. SPIC used its default local nonce creation
and local verdict verification: it requests a Google Play Integrity token,
then decrypts and verifies the signed response locally. No independent
application backend was configured. This is a device-verdict experiment,
not proof that a banking or DRM app will accept the environment.

The original unproxied KernelSU request returned `-17`
(`CLIENT_TRANSIENT_ERROR`) and had accompanying network/key-attestation
errors. After using the user-supplied proxy, actual verdicts were obtained:

| Configuration | SPIC device result | App recognition |
| --- | --- | --- |
| Stock kernel and stock ramdisk | `NO_INTEGRITY` | `UNEVALUATED` |
| Stock kernel and KernelSU ramdisk, no modules | `NO_INTEGRITY` | `UNEVALUATED` |
| KernelSU + TrickyStore 1.4.1, default software keybox/targets | `NO_INTEGRITY` | `UNEVALUATED` |

Corresponding captures are `spic-stock-proxy.{xml,png,txt}` and
`spic-kernelsu-proxy.{xml,png,txt}`. The stock control used the same disposable
userdata after the KernelSU Manager had been installed, but no KernelSU
module was loaded and the shell was unprivileged. It is not a pristine
userdata control.

TrickyStore installation succeeded. KernelSU reported the module enabled,
and its runtime log confirmed `hook success!` and `Registered for Keystore2!`.
It reported `teeBroken=true`, no StrongBox security level, and a failed
attestation-key request due to missing
`com.android.rkpdapp.IRemoteProvisioning` service. These observations do not
identify every reason Google rejected the environment; they establish that
the module ran and the default configuration did not produce a passing
device verdict. No hardware keybox, fingerprint spoofing, security-patch
spoofing, or changes to the system/vendor images were used.

TrickyStore captures: `trickystore-install.log`, `trickystore-state.txt`,
`trickystore-logcat.txt`, `spic-trickystore-proxy.{xml,png,txt}`, and
`spic-trickystore-details.{xml,png,txt}`. The details capture also showed
account licensing `UNEVALUATED` and a fresh request timestamp.

A subsequent control cleared only the disposable guest's Play services and
Play Store data, then cold-booted again with TrickyStore. Its first request
returned API error `-12` (`GOOGLE_SERVER_UNAVAILABLE`), not an integrity
verdict. It is retained separately as `spic-trickystore-fresh.*`.
The delayed retry returned **`NO_INTEGRITY` / `UNEVALUATED`** again, with
the hook confirmed active after that cold boot. Evidence is retained as
`spic-trickystore-fresh-retry.*` and `trickystore-fresh-logcat.txt`.

## Outcome and retained setup

KernelSU root works on this Play image with the stock kernel and a patched
ramdisk. KernelSU plus TrickyStore's default configuration did **not** pass
Play Integrity, including after resetting Play services state. This does not
establish that every other configuration is impossible.

The disposable emulator and its private ADB server were stopped after testing.
The patched ramdisk, fresh AVD, downloaded releases, hashes, screenshots,
logs, and local `lab.py` reproduction helper remain in the disposable root.
The helper can boot `stock` or `root`; the retained userdata now has
TrickyStore installed, so disable the module before reusing it as a
KernelSU-only control. `artifact-sha256.json` records the seven principal
downloaded/generated artifact hashes. `original-images-final-check.json`
records the final original-image verification.

Only this report was added to the application repository, on branch
`feature/kernelsu-emulator-experiment`. No application code or default
emulator launch settings were changed, and nothing was committed or pushed.
Validation consisted of the runtime experiment, artifact verification, and
`git diff --check`; the application build/test suite was not run for this
documentation-only change.

## References

- https://github.com/tiann/KernelSU/releases/tag/v3.3.0
- https://github.com/tiann/KernelSU/blob/v3.3.0/userspace/ksud/src/boot_patch.rs
- https://github.com/5ec1cff/TrickyStore
- https://github.com/herzhenr/spic-android

Root access and successful module installation do not establish a passing
Play Integrity verdict. Checker results must be recorded separately.
