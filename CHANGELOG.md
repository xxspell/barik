# Changelog

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
