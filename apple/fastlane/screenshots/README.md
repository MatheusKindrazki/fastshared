# App Store screenshots

Do not capture these manually. Generate the full launch set from the repo root:

```bash
make appstore-screenshots
```

The lane captures the same five deterministic scenes for iPhone, iPad, and
macOS:

1. Share Extension flow.
2. Retention picker.
3. Upload progress / Live Activity.
4. History with countdown.
5. Pro paywall.

Output folders:

- `ios/en-US/` for iPhone and iPad screenshots.
- `macos/en-US/` for Mac screenshots.
- `iap/en-US/` for the generated IAP review screenshot.

Current Apple-required anchors verified 2026-04-24:

- iPhone 6.9 inch: `1260x2736`, `1290x2796`, or `1320x2868` portrait.
- iPad 13 inch: `2064x2752` or `2048x2732` portrait.
- Mac: `1280x800`, `1440x900`, `2560x1600`, or `2880x1800`.
- IAP review screenshots: use an accepted iPhone screenshot size, preferably
  1290x2796 or 1242x2688.

Filename order is the App Store order. The generator writes names like:

- `ios/en-US/01_APP_IPHONE_67_share.png`
- `ios/en-US/02_APP_IPAD_PRO_3GEN_129_history.png`
- `macos/en-US/01_APP_DESKTOP_drop.png`

For `2048x2732` iPad screenshots, include `APP_IPAD_PRO_3GEN_129` in the
filename so fastlane maps the image to the 13 inch iPad set.
