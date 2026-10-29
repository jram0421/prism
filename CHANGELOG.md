# Changelog

## 1.0.0

- Bar widget and panel for ARGB/RGB control of everything OpenRGB can see
  (motherboard headers, RAM, GPU, strips, fans).
- Effects: Static, Breathing, Flashing, Spectrum Cycle, Rainbow, Wave. Effects run
  in software from one clock, so every device stays in lockstep.
- Color swatches (including the theme accent, boosted 50% for LED contrast and with greens kept from drifting toward blue), custom hex color, effect speed,
  brightness, and smooth fades when toggling power.
- Settings: match the theme accent on theme change, turn off while the screen is
  locked or the screensaver runs, and per-header LED counts for addressable
  headers (auto-detected, any board).
- `omarchy-prism` CLI with `setup`, `doctor` and `uninstall`.
- Playful rotating status phrases in the panel header, matching the Bluetooth and Network panels.
- Lighting is restored automatically at login and after the OpenRGB server restarts, and the engine picks up devices the server discovers late.
