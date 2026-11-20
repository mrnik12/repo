# ShazamX

ShazamX restores song recognition in Shazam 5.5.1 on iOS 6. It displays the recognized title, artist, and available cover art in Shazam's original results screen. Tested on iPhone 4S running iOS 6.1.3. Other iOS 6 devices may work.

## Install

1. Install Shazam 5.5.1 (build 572) first.
2. Add `https://mrnik12.github.io/repo/` under **Cydia → Sources → Edit → Add**, then install **ShazamX**. For manual installation, get the [.deb from GitHub Releases](https://github.com/mrnik12/repo/releases/latest) or [download v0.3.7 directly](https://mrnik12.github.io/repo/debs/org.legacyshazam.smoke_0.3.7_iphoneos-arm.deb).
3. Open Shazam and tap the blue dial. The tweak can be switched off under **Settings → ShazamX**.

The hosted build uses your internet connection and has the relay address built in. When you tap the dial, it records a short clip and sends it to the hosted relay for recognition. The free relay can take about a minute to wake after being idle.

## Source

- [Tweak](source/tweak) — Objective-C and Logos for Shazam 5.5.1.
- [Relay](source/relay) — FastAPI recognition and cover art selection.
- [MIT license](source/LICENSE) — Applies to the original project source. Shazam itself is distributed separately.

To build the tweak on Linux or WSL, install Theos with an ARMv7-capable toolchain and the iOS 6.1 SDK. From the repository root:

```bash
bash source/tweak/build-hosted.sh https://legacy-shazam-relay.onrender.com
```

To self-host, deploy the [relay directory](source/relay) as a Docker web service, enable `LEGACY_SHAZAM_PUBLIC=1` for clients built without a token, and build the tweak with your own HTTPS origin. The relay exposes `/health` and `/recognize`.
