# DRM / Widevine / Netflix on Helium Linux

This bundle enables the Chromium-side plumbing needed for Widevine/EME on Linux:

- `enable_widevine=true`
- `enable_library_cdms=true`
- proprietary codecs are already enabled through `ffmpeg_branding="Chrome"` and `proprietary_codecs=true`
- the runtime wrappers register an existing `WidevineCdm` directory through Chromium's Linux hint file

Helium **does not ship Google's proprietary Widevine CDM** in this source bundle. You must obtain Widevine from a legitimate system package or browser installation such as Google Chrome, a distro package, or a local CDM payload you are licensed to use.

## Expected Widevine layout

A valid Linux x86_64 Widevine payload looks like this:

```text
WidevineCdm/
├── manifest.json
└── _platform_specific/
    └── linux_x64/
        └── libwidevinecdm.so
```

## Automatic runtime registration

The packaged `helium-wrapper` and AppImage `AppRun` source `helium-widevine.sh` at startup. If a valid `WidevineCdm` directory is found, the wrapper writes Chromium's Linux hint file:

```text
<User Data Dir>/WidevineCdm/latest-component-updated-widevine-cdm
```

with this JSON payload:

```json
{"Path":"/absolute/path/to/WidevineCdm"}
```

The wrapper searches common locations including:

- `/opt/google/chrome/WidevineCdm`
- `/opt/brave.com/brave/WidevineCdm`
- `/opt/vivaldi/WidevineCdm`
- `/usr/lib/chromium/WidevineCdm`
- `/usr/lib/ungoogled-chromium/WidevineCdm`
- `$XDG_DATA_HOME/helium/WidevineCdm`

You can override the path manually:

```bash
HELIUM_WIDEVINE_DIR=/path/to/WidevineCdm helium-wrapper
```

Debug the wrapper registration:

```bash
HELIUM_WIDEVINE_DEBUG=1 helium-wrapper
```

Disable automatic registration:

```bash
HELIUM_WIDEVINE_DISABLE=1 helium-wrapper
```

## Manual registration script

From the source tree:

```bash
scripts/install-widevine.sh --from /opt/google/chrome/WidevineCdm
```

For a custom profile/user-data directory:

```bash
scripts/install-widevine.sh \
  --from /opt/google/chrome/WidevineCdm \
  --user-data-dir "$HOME/.config/helium"
```

For a writable unpacked Helium install directory:

```bash
scripts/install-widevine.sh \
  --from /opt/google/chrome/WidevineCdm \
  --install-dir /opt/helium
```

## Arch Linux notes

Install a legitimate Widevine provider first. Common choices are Google Chrome or an AUR package that provides a valid `WidevineCdm` directory. Then run:

```bash
scripts/install-widevine.sh --from /opt/google/chrome/WidevineCdm
```

or point `--from` at the package-provided `WidevineCdm` directory.

## Optional local bundling

If you are building a private package and you have redistribution rights for the CDM, you can opt in to Chromium's bundled Widevine path:

```bash
HELIUM_BUNDLE_WIDEVINE=1 scripts/build.sh
```

If needed, provide a Chromium-compatible `widevine_root` path:

```bash
HELIUM_BUNDLE_WIDEVINE=1 \
HELIUM_WIDEVINE_ROOT=/absolute/path/relative-layout \
scripts/build.sh
```

The packaging script also copies `out/Default/WidevineCdm` into the tarball/AppImage when that directory exists.

## Testing

After restarting Helium completely:

1. Open `chrome://components` and check for `Widevine Content Decryption Module`.
2. Test a DRM stream with a public DRM test page.
3. Open Netflix.

On Linux, Netflix support is more limited than on Windows/macOS/ChromeOS. Even with Widevine working, maximum resolution and availability depend on Netflix, CDM level, browser fingerprinting, codecs, and the service's current policy.
