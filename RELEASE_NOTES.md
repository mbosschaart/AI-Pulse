# AI Pulse 1.4

Use AI Pulse entirely from the menu bar, with improved launch-at-login initialization.

- **Menu-bar-only mode:** turn off Show desktop widget in General Settings, or choose Hide Widget from the menu-bar context menu. The choice persists across restarts and automatic usage refresh continues.
- AI Pulse now runs without a Dock icon. Settings and provider connections remain accessible while the dashboard is hidden.
- Initialize the menu bar and dashboard directly during app launch, fixing the startup path that could leave the app running without its interface after login.
- Launch-at-login registration now requires an installed copy in Applications. Settings refreshes its status and shows approval or registration errors.
- Existing provider connections, usage, layout, and preferences are retained.

## Install

Download **AI-Pulse-1.4.dmg** and drag AI Pulse to Applications, or use **AI-Pulse-macOS.zip**. Both contain the Developer ID signed, Apple-notarized app with a stapled ticket. SHA256SUMS.txt includes checksums.

Existing users: Settings → General · All providers → Check for updates. Requires macOS 14 or later; native Liquid Glass requires macOS 26 or later.

## Validation

Core tests and release signing/notarization are checked for this release. Full reboot validation of launch at login remains pending.
