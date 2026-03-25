# Changelog

## 0.11.0

### Added
- Add a unified settings window with routed sections, live TOML-backed updates, and widget popup links that jump directly to the matching settings pane
- Add broader settings coverage for display layouts, weather, network, system monitor, TickTick, shortcuts, Pomodoro, and usage widgets
- Add appearance controls for theme, spacing, blur, widget capsule backgrounds, and background bar styling in the settings window
- Add appearance height controls with Default, Menu Bar, and Custom modes, plus reset actions for experimental appearance cards
- Add per-display bar layouts with monitor-specific widget overrides, drag-to-reorder layout editing, and notch-aware spacing controls
- Add English and Russian localization for the expanded settings UI, including section labels, field copy, and display-layout widget catalog text

### Fixed
- Fix experimental appearance writes so GUI edits update existing commented TOML sections without creating duplicate tables that break parsing
- Fix Apple Silicon CPU temperature sampling by filtering implausible sensor readings and preserving the last valid value when bad samples appear

### Changed
- Improve popup anchoring so popups open on the clicked display and clamp more naturally around the active widget
- Improve weather and settings config handling to avoid stale GUI writes, late callback rollbacks, and leftover values when clearing coordinates or display overrides
- Clarify that per-display layout overrides fully replace the global widget list for the selected monitor
- Note that settings edits can normalize touched TOML sections to the canonical table and hyphenated-key format

## 0.10.0

### Added
- Add Apple Shortcuts widget with popup folder navigation, search, direct execution, and configurable filtering
- Add Spaces hover cards for app icons with anchored positioning, screen-bound layout, and optional PID details
- Add configurable Spaces window icon desaturation for softer inactive window rendering
- Add richer CLIProxy usage popup details with overview and accounts tabs, provider-aware account cards, and filtered top API keys
- Add Russian localization for the Apple Shortcuts widget interface

### Fixed
- Fix Spaces handling for hidden and minimized yabai windows to avoid duplicate updates and restore correct visibility state
- Fix rendering of inactive and empty yabai spaces, including active-space highlighting and nonfocused window visibility
- Fix System Monitor dual-line network labels wrapping by allowing smoother width expansion for larger values

## 0.9.0

### Added
- Add CLIProxy usage widget with quota tracking, token stats, provider filters, and popup details
- Add CLIProxy quota refresh controls, threshold configuration, top API keys, and improved quota rendering
- Add native macOS screen recording stop widget with accessibility-first recording detection
- Add keyboard layout widget with a popup for available system layouts and switching support
- Add CPU and GPU temperature support to the System Monitor widget and popup
- Add a richer System Monitor popup with configurable sections, dual-line network rendering, and refined metric presentation
- Add read-only Focus widget with active mode display and popup details
- Add Pomodoro widget with local timer mode, TickTick private API sync, bundled sounds, and popup history
- Add rotating TickTick menu bar mode for tasks and habits with configurable filters and width
- Add Russian localization for CLIProxy, screen recording, Focus, Pomodoro, and supporting widget updates

### Fixed
- Fix TickTick private task completion flow with improved metadata handling, debug logging, and undo support
- Fix TickTick matrix quadrant mapping, stable sorting, and layout consistency

### Changed
- Improve README TickTick documentation and configuration examples
- Expand the widget overview in the README with additional built-in widgets
- Refine TickTick rotating item layout, spacing, random rotation, and popup deep-link highlighting

## 0.8.0

### Added
- Add TickTick widget with tasks, habits and Eisenhower matrix support
- Add Homebrew widget with update monitoring and popup functionality
- Integrate TickTick tasks into calendar popup for combined task and event view
- Add localization for TickTick widget and related UI elements
- Add restoration and reorganization of localization strings
- Add calendar integration labels (today, overdue, etc.) for TickTick tasks

### Changed
- Improve localization consistency across widgets
- Enhance calendar popup with TickTick task visualization (highlight rings, priority colors)
- Add filter tabs in calendar popup to show only TickTick tasks
- Add task visualization in calendar grid with priority-based coloring
- Add overdue and important task highlighting in daily view

## 0.7.0

### Added
- Add weather widget with current conditions and forecast that integrates with Open-Meteo API
- Add Qwen Proxy usage widget for monitoring proxy health and account status
- Add stacked time and date layout option for the time widget with configurable formats
- Add Russian localization for Qwen Proxy widget and system monitor popup
- Add localization for weather conditions and improve forecast formatting
- Add repository reference updates from mocki-toki to xxspell

### Changed
- Localize weather conditions using translation keys instead of hardcoded strings
- Improve weather popup and hourly forecast formatting with locale-aware hour display
- Update high/low temperature display to use ↑ ↓ format in weather widget

## 0.6.0

### Added
- Added Claude usage widget that reads Claude Code credentials from Keychain and shows current 5-hour usage as a ring in the menu bar
- Added Codex usage widget that reads local ~/.codex/auth.json and shows current rate-limit window in the menu bar
- Added configurable system monitor widget with support for CPU, RAM, disk, GPU, and network metrics
- Added system monitor popup strings for internationalization

### Fixed
- Fixed popup positioning on the correct screen for multi-monitor setups
- Fixed Now Playing artwork handling with improved MediaRemote Adapter for cross-platform support
- Fixed popup anchor positioning to properly attach to widget frames
- Adapted popup playback state to mediaremote adapter updates and reduced widget height

### Performance
- Reduced session parsing overhead in Codex usage widget
- Improved yabai state refresh from signals for better performance
- Optimized NowPlaying artwork handling with in-memory storage

### Changed
- Refactored logging system to replace print debugging with structured OSLog output
- Implemented MediaRemote Adapter for cross-platform now playing support
- Refactored display system to support multiple screens with dynamic panel creation and cleanup


## 0.5.1

> This release was supported by **ALinuxPerson** _(help with the appearance configuration, 1 issue)_, **bake** _(1 issue)_ and **Oery** _(1 issue)_

- Added yabai.path and aerospace.path config properties
- Fixed popup design
- Fixed Apple Music integration in Now Playing widget
- Added experimental appearance configuration:

```toml
### EXPERIMENTAL, WILL BE REPLACED BY STYLE API IN THE FUTURE
[experimental.background] # settings for blurred background
displayed = true          # display blurred background
height = "default"        # available values: default (stretch to full screen), menu-bar (height like system menu bar), <float> (e.g., 40, 33.5)
blur = 3                  # background type: from 1 to 6 for blur intensity, 7 for black color

[experimental.foreground] # settings for menu bar
height = "default"        # available values: default (55.0), menu-bar (height like system menu bar), <float> (e.g., 40, 33.5)
horizontal-padding = 25   # padding on the left and right corners
spacing = 15              # spacing between widgets

[experimental.foreground.widgets-background] # settings for widgets background
displayed = false                            # wrap widgets in their own background
blur = 3                                     # background type: from 1 to 6 for blur intensity
```

## 0.5.0

![Header](https://github.com/user-attachments/assets/182e7930-feb8-4e46-a691-7a54028d21a1)

> This release was supported by **AltaCursor** _([2 cups of coffee](https://ko-fi.com/mocki_toki), 3 issues)_ and **farhanmansurii** _(help with Spotify player)_

**Popup** — a new feature that allows opening an extended and interactive view of a widget (e.g., the battery charge indicator widget) by clicking on it. Currently, popups are available for the following **barik** widgets: Now Playing, Network, Battery, and Time (Calendar).

We want to make **barik** more useful, powerful, and convenient, so feel free to share your ideas in [Issues](https://github.com/mocki-toki/barik/issues/new), and contribute your work through [Pull Requests](https://github.com/mocki-toki/barik/pulls). We’ll definitely review everything!

Other changes:

- Added a new **Now Playing** widget — allowing control of music in desktop applications like Apple Music and Spotify. We welcome your suggestions for supporting other music services: https://github.com/mocki-toki/barik/issues/new
- More customization: Space key and title visibility, as well as a list of applications that will always be displayed by application name.
- Added the ability to switch windows and spaces by mouse click.
- Fixed the `calendar.show-events` config property functionality.
- Fixed screen resolution readjust
- Added auto update functionality, what's new popup

## 0.4.1

> This release was supported by **Oery** _(1 issue)_

- Fixed a display issue with the Notch.

## 0.4.0

> This release was supported by **AltaCursor** _(2 issues)_

- Added support for the `~/.barik-config.toml` configuration file.
- Added AeroSpace support 🎉.
- Fixed 24-hour time format.
- Fixed a desktop icon display issue.

## 0.3.0

- Added a network widget (Wi-Fi/Ethernet status).
- Fixed an incorrect color in the events indicator.
- Prioritized displaying events that are not all-day events.
- Added a maximum length for the focused window title.
- Updated the application icon.
- Added power plug battery status.

## 0.2.0

- Added support for a light theme.
- Added the application icon.

## 0.1.0

- Initial release.
