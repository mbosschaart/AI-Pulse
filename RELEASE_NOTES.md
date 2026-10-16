# AI Pulse 1.7

Track ElevenLabs alongside your other AI providers.

- ElevenLabs displays the percentage of included subscription allowance remaining and its provider-reported reset date. Add an API key with User → Read access in Settings; credentials stay in macOS Keychain.
- Available in Cards, Compact, the menu bar, and native macOS widgets. Small widgets can select ElevenLabs; medium and large widgets now offer six configurable rows.
- Provider arrangement accommodates six providers. Existing provider selections and saved arrangements are preserved.
- Exhausted included allowance shows 0%. Overage charges and invoice totals are excluded; missing reset dates are not estimated.
- The full setup guide is in [README.md](https://github.com/mbosschaart/AI-Pulse#readme).

57 tests pass, app and widget builds pass, and minimum-size widget layouts were visually checked. A live ElevenLabs account refresh was verified in Settings.

Requires macOS 14 or later. ZIP and DMG contain the universal Developer ID signed, Apple-notarized app with a stapled ticket. SHA256SUMS.txt contains package checksums.

Known issue: native widgets can retain stale readings after an in-place update. Automatic post-update widget recovery remains queued; it is not fixed in this release.
