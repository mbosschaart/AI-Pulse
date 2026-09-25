# AI Pulse 1.3

OpenRouter joins AI Pulse, and Settings now clearly separates app-wide preferences from provider connections.

- **OpenRouter:** track account-wide Activity spend in USD for the current UTC month. Connect with an OpenRouter Management API key, stored in macOS Keychain. Organization keys report organization-wide spend; regular inference keys are not substituted for account-wide analytics.
- **Settings dropdown:** choose General · All providers for refresh rate, status LEDs, appearance, launch-at-login, and software updates. Choose a provider for connection details, visibility, and last-updated time.
- Card shortcuts still open the matching provider directly. Existing accounts, layout, and preferences are preserved.
- OpenRouter supports Cards, Compact, the menu-bar overview, and desktop widgets. Large widgets use a readable list when five providers are enabled.
- Check connection now explicitly checks a newly configured account immediately.

## Install

Download **AI-Pulse-1.3.dmg** and drag AI Pulse to Applications, or use **AI-Pulse-macOS.zip**. Both contain the Developer ID signed, Apple-notarized app with a stapled ticket. SHA256SUMS.txt includes checksums.

Existing users: Settings → General · All providers → Check for updates. Requires macOS 14 or later; native Liquid Glass requires macOS 26 or later.
