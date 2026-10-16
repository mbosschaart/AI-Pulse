# Development follow-ups

- [ ] **Automatically refresh native widgets after an app update.** During the update to 1.6, the widget extension process survived the app replacement and usage numbers/status LEDs stayed stale. Restarting the extension and widget host restored current readings; the user confirmed recovery. Investigate the supported Sparkle/WidgetKit update lifecycle and ensure the updated app republishes its snapshot and existing widgets load the new extension and readings without manual intervention. Do not treat restarting all of Notification Center as the production solution.
  - Verify an actual in-place upgrade with existing small, medium, and large widgets: fresh usage and LEDs appear, and provider selection, order, visibility, and widget placement remain intact.
  - Include an upgrade with the floating dashboard hidden and the app running in menu-bar-only mode.
