# Barik TUI Style — Design

**Date:** 2026-08-01
**Status:** Approved for planning

## Summary

Add a new, switchable visual style to Barik called **TUI** — a narrow, monochrome,
"almost terminal" look. It coexists with the current "glass" style: enabled via
`style = "tui"` in config, fully reversible, default behaviour unchanged.

The style is: monospaced font everywhere, monochrome base with a single
configurable accent, brightness-based contrast (bright / dim), hybrid content
(text + minimal glyphs, no colorful SF-symbol soup), a soft rounded background
chip under each widget, and a shorter/denser bar. It is "almost TUI" — the
*content* reads terminal-like, but the *form* stays soft and macOS-native
(rounded corners, subtle chip).

## Goals

- A cohesive TUI look that applies to **all** widgets, not just a hand-picked few.
- Zero regression to the existing default style — it stays byte-for-byte the same
  when `style` is unset or `"default"`.
- Minimal, isolated per-widget changes: a centralized layer does the heavy lifting;
  per-widget work is small additive branches.

## Non-Goals

- Restyling popups in the first pass (they remain functional in their current look).
- A literal terminal emulator (box-drawing cells, brackets). Content is bare
  monochrome text separated by whitespace; no `[ ]` / `│` chrome.
- Remapping the asset color catalog globally.

## Aesthetic Decisions (locked)

| Dimension    | Decision                                                                 |
|--------------|--------------------------------------------------------------------------|
| Coexistence  | Separate switchable theme (`style = "tui"`), default stays untouched     |
| Vocabulary   | Bare monochrome text, no brackets/boxes; separation by whitespace (opt `·`) |
| Color        | Monochrome + one configurable accent for active/important                |
| Contrast     | Brightness only: `bright` (primary) vs `dim` (secondary)                 |
| Icons        | Hybrid: text/numbers where clearer, minimal glyphs (`↑↓`, `▰`, `♪`) elsewhere |
| Form         | Soft rounded chip under each widget; shorter height; tighter density     |
| Font         | Monospaced everywhere (system `.monospaced`; custom `font-family` respected) |
| Coverage     | Core widgets hand-tuned first; all others cohesive immediately via central layer |

## Configuration Surface

New top-level `style` field (sibling of `theme`) and a new `[tui]` section. All
fields have defaults; the section can be omitted entirely.

```toml
style = "tui"          # "default" (default) | "tui"

[tui]
accent = "#7dd3fc"     # accent color for active / important elements
dim = 0.5              # opacity of secondary (dim) text
separator = ""         # "" = whitespace only, "·" = dot separator
chip = true            # soft rounded background under each widget
chip-opacity = 0.06    # how visible the chip fill is
```

- `height` and `font-family` are read from the existing
  `[experimental.foreground]` section. When `style = "tui"` and the user has not
  overridden height (`height = "barik-default"`), Barik uses a smaller TUI default
  (~34) instead of 55.
- Accent parsing: hex string → `Color`. On parse failure, fall back to a sane
  default (system accent or the documented default).

## Architecture

### The `BarikStyle` layer

A lightweight value type `BarikStyle` is the single source of truth for the
active style. It is derived from `ConfigManager.shared.config` and exposes
semantic tokens:

- `isTUI: Bool`
- `fontDesign: Font.Design` — `.monospaced` when TUI, else `.default`
- `foreground: Color`, `dim: Color` (foreground at `dim` opacity)
- `accent: Color`
- `chip`: whether shown, fill color/opacity, corner radius, padding, stroke
- density/height tokens

Exposure:

- SwiftUI `Environment` key `\.barikStyle` for views.
- A static accessor on `ConfigManager` / `BarikStyle` for non-view code.

New file: `Barik/Utils/BarikStyle.swift`.

### Config model changes

In `Barik/Config/ConfigModels.swift`:

- `RootToml`: add `style: String?` and `tui: TuiStyleConfig?`.
- `Config`: add `style: String` (default `"default"`) and `tui: TuiStyleConfig`
  accessors.
- New `TuiStyleConfig: Decodable` with `accent`, `dim`, `separator`, `chip`,
  `chipOpacity` and their defaults + `CodingKeys` (kebab-case).
- `ForegroundConfig.resolveHeight()` gains awareness of TUI to return the smaller
  default when height is unset and style is TUI. (Style is read from
  `ConfigManager.shared` or threaded in — implementation detail for the plan.)

### Tier 0 — centralized wins (cover ALL widgets automatically)

1. **Font** — `Barik/Utils/BarikFont.swift`: `BarikFontModifier` forces
   `.monospaced` design when `isTUI`, overriding the passed `design`. Every
   `barikFont` / `barikTextStyle` call across the app becomes monospaced.
2. **Chip chrome** — `Barik/Utils/ExperimentalConfigurationModifier.swift`: when
   `isTUI`, `experimentalConfiguration` renders the TUI chip (thin rounded
   rectangle, subtle fill at `chip-opacity`, tighter padding, smaller height)
   instead of the current capsule/blur. Nearly every widget already calls this
   modifier, so all chips restyle at once.
3. **Density** — `Barik/Views/MenuBarView.swift`: smaller default height and
   spacing in TUI; inject `\.barikStyle` into the panel root.
4. **Monochrome safety net** — in TUI, every widget is wrapped by default in a
   desaturation modifier (`.saturation(0)` + slight contrast). This neutralizes
   colorful SF symbols, album art, and status colors so untouched widgets read
   monochrome and cohesive immediately.

### Accent rule (net vs hand-tuned)

- A widget **with** a hand-tuned TUI branch renders its own controlled palette
  (mono + accent) and **opts out** of the safety net.
- A widget **without** a TUI branch passes through the net → pure monochrome, no
  accent.

This guarantees "everything is in-style" while accent appears only where we
deliberately placed it, with no grayscale-vs-accent conflict.

### Where the net is applied

The wrap happens at the widget-composition point in `MenuBarView.buildView` (or a
shared `.barikWidgetChrome()` modifier), keyed off `isTUI` and a per-widget
"hand-tuned" flag. `divider` and `spacer` get TUI-appropriate rendering here too.

## Widget Coverage

Nothing is left out. After Tier 0 the whole bar already looks cohesive
(monospaced + chip + monochrome); Tiers 1–2 are content/glyph/accent polish.

### Tier 0 — all widgets (centralized)

Monospaced font, TUI chip, density, monochrome net, `divider`/`spacer` styling.

### Tier 1 — hand-tuned now (accent + glyphs), first pass

Each gets an additive TUI branch; the default branch is untouched.

- **spaces** — space numbers in a row; active = accent (bright), others dim;
  focused window title dim + truncated; no colorful app icons in TUI.
- **time** — monospaced `HH:MM`, date dim.
- **battery** — `▰ 62%` + charge glyph; accent/red on low.
- **network** — `↑↓` + speed/SSID, dim.
- **nowplaying** — `♪ Title — Artist`, truncated, dim; no album art (or tiny).
- **system-monitor** — text metrics `CPU 12% RAM 40%`, accent over threshold.

### Tier 2 — hand-tuned next (small text branches), second pass

`keyboard-layout`, `focus`, `weather`, `homebrew`, `claude-usage`,
`codex-usage`, `qwen-proxy-usage`, `cliproxy-usage`, `shortcuts`,
`screen-recording`, `pomodoro`, `ticktick`, `system-banner`.

## Scope of Implementation

- **First implementation pass:** Tier 0 + Tier 1.
- **Second pass:** Tier 2.
- **Later / out of this design:** popup restyling, Settings-UI style picker
  (config-only is sufficient to start; a picker in `SettingsView` is a nice-to-have).

## What Stays Unchanged

- The default "glass" style — no visual or behavioral change when style is unset.
- Core-widget popups in the first pass.
- The asset color catalog (no global remap).

## Testing / Verification

Barik has no unit tests; verification is manual (build + run, per CLAUDE.md).

- Toggle `style` between unset/`"default"` and `"tui"` and confirm live reload.
- Verify default style is visually identical to before (no regression).
- Verify TUI: monospaced font, monochrome bar, accent only on active/important,
  chips render, height is smaller, all widgets look cohesive (incl. un-tuned ones
  via the net).
- Verify accent hex parsing, including a malformed value falling back cleanly.
- Verify custom `font-family` still overrides the monospaced default in TUI.

## Open Questions / Risks

- Threading style into `ForegroundConfig.resolveHeight()` (a value type) cleanly —
  may read `ConfigManager.shared` or take a parameter; decide in the plan.
- Desaturation net interaction with widgets that also set explicit foreground
  colors — confirm the wrap order yields monochrome without washing out contrast.
