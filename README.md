# MacOS Ultrabright

Free brightness control for the Liquid Retina XDR display in a MacBook Pro.
Use one slider or the brightness keys to move from SDR into XDR.

[Download for Apple silicon](https://github.com/sam-xz/macos-ultrabright/releases/latest/download/MacOS-Ultrabright-arm64.dmg)

This is a personal fork of [xdr-boost](https://github.com/levelsio/xdr-boost)
by Pieter Levels. It adds smooth brightness changes, a nits display and a macOS app.

I wanted free, simple brightness control. I did not want to pay for Vivid,
and I did not need BetterDisplay's extra options or paid features.
The original project also appeared unmaintained, so I continued development in this fork.

## Install

1. Download the disk image. Quit other brightness utilities.
2. Drag **MacOS Ultrabright.app** to **Applications**.
3. Eject the disk image. Open **MacOS Ultrabright**.
4. Select the sun icon, then **Enable brightness keys…**.
5. Allow **MacOS Ultrabright** in **System Settings → Privacy & Security → Accessibility**.

The download is for an Apple silicon MacBook Pro with a built-in Liquid Retina
XDR display. This version was developed on macOS 27.0 beta.

The app uses a local signature and has no Apple notarisation. If macOS blocks
it, follow [Apple's Open Anyway instructions](https://support.apple.com/en-gb/guide/mac-help/mh40616/mac).

## Use

- **0–100%:** normal SDR brightness.
- **100–140%:** XDR brightness, up to an estimated **1400 nits**.
- Press brightness up past 100% to enter XDR. Press down to return to SDR.
- Hold **Shift+Option** for smaller steps.
- Press **Ctrl+Option+Cmd+V** to switch XDR on or return to SDR.

XDR changes follow the display refresh rate. A short pop-up shows the level and
estimated nits. Nits are estimates; available brightness depends on the display.
The app keeps your current brightness when it starts. Select **Quit** in the
sun menu to close it and restore the display settings saved on entry to XDR.
Normal SDR changes remain in effect.

To start at login, add the app in **System Settings → General → Login Items**.
If brightness keys stop working after an update, quit the app, remove its
Accessibility entry, open it again and allow access.

## Build

Install Apple's Command Line Tools, then run:

```sh
git clone https://github.com/sam-xz/macos-ultrabright.git
cd macos-ultrabright
make dmg
```

The outputs are `.build/MacOS Ultrabright.app` and `.build/MacOS-Ultrabright-arm64.dmg`.
Use `make app` to build only the app. Builds target Apple silicon by default.

## Licence

[MIT](LICENSE).
