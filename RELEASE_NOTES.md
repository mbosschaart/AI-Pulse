# AI Pulse 1.5

Choose your Cursor workspace or see combined personal usage, keep the dashboard where you placed it, and recover more smoothly from temporary network failures.

- **Cursor teams:** Settings → Cursor → Load teams lets you select a workspace or All teams · combined personal cost. The selection is remembered and shown on the dashboard.
- Combined Cursor usage includes only your personal costs across teams with matching billing periods. Other members’ spending and fixed subscription fees are excluded. Missing totals or different periods prompt you to select an individual team.
- **Remembered dashboard position:** Cards and Compact restore their top-left position between runs. Content resizing no longer shifts Compact downward, and restoration keeps the dashboard reachable after display changes.
- **Network recovery:** temporary transport failures receive up to three short retries without changing your regular refresh schedule. API requests can wait briefly for connectivity. Failed browser page loads are no longer mistaken for expired logins.
- Existing accounts and preferences are preserved.

## Install

Download **AI-Pulse-1.5.dmg** and drag AI Pulse to Applications, or use **AI-Pulse-macOS.zip**. Both contain the Developer ID signed, Apple-notarized app with a stapled ticket. SHA256SUMS.txt includes checksums.

Existing users: Settings → General · All providers → Check for updates. Requires macOS 14 or later; native Liquid Glass requires macOS 26 or later.

## Validation

46 core tests pass. Cursor team selection and combined usage were compared with the live dashboard, and the selection survived restart. An isolated AppKit check verified repeated window restoration and resize anchoring. Full reboot validation remains pending.
