# AI Pulse 1.6

Native macOS widgets now provide one provider card, minimal Compact rows, or a single column of provider tiles, with configurable provider selection and order.

- Reorder providers by dragging in Settings → Arrange providers, or select a custom order per widget. Hidden rows are excluded with either ordering mode.
- Medium widgets show only provider, connection status, and usage. Rows stay compact; macOS retains the fixed widget footprint.
- Native widget appearance follows macOS. Floating dashboard Liquid Glass and glass-style controls remain independent.
- Adaptive transparent provider logos improve contrast; current connections retain green status LEDs in accented mode.
- Gallery snapshots use sample readings with transparent backgrounds.
- Widget app-opening routes lead to Settings; the provider arrangement window stays compact.
- The complete setup tutorial, screenshots, and dashboard-versus-widget comparison are in [README.md](README.md).

51 core tests pass. Layouts were rendered in light and dark appearances. Actual gallery readability after refreshing stale macOS registrations still awaits confirmation.
