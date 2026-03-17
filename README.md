
[//]: # (<p align="center" dir="auto">)

[//]: # (  <img src="resources/header-image.png" alt="Barik"">)

[//]: # (  <p align="center" dir="auto">)

[//]: # (    <a href="LICENSE">)

[//]: # (      <img alt="License Badge" src="https://img.shields.io/github/license/mocki-toki/barik.svg?color=green" style="max-width: 100%;">)

[//]: # (    </a>)

[//]: # (    <a href="https://github.com/mocki-toki/barik/issues">)

[//]: # (      <img alt="Issues Badge" src="https://img.shields.io/github/issues/mocki-toki/barik.svg?color=green" style="max-width: 100%;">)

[//]: # (    </a>)

[//]: # (    <a href="CHANGELOG.md">)

[//]: # (      <img alt="Changelog Badge" src="https://img.shields.io/badge/view-changelog-green.svg" style="max-width: 100%;">)

[//]: # (    </a>)

[//]: # (    <a href="https://github.com/mocki-toki/barik/releases">)

[//]: # (      <img alt="GitHub Downloads &#40;all assets, all releases&#41;" src="https://img.shields.io/github/downloads/mocki-toki/barik/total">)

[//]: # (    </a>)

[//]: # (  </p>)

[//]: # (</p>)

**barik** is a lightweight macOS menu bar replacement. If you use [**yabai**](https://github.com/koekeishiya/yabai) or [**AeroSpace**](https://github.com/nikitabobko/AeroSpace) for tiling WM, you can display the current space in a sleek macOS-style panel with smooth animations. This makes it easy to see which number to press to switch spaces.

It also supports compact usage widgets for **Claude Code** and **Codex**:

- **Claude Usage** reads your Claude Code credentials from Keychain, shows current 5-hour usage as a ring in the menu bar, and exposes 5-hour plus weekly usage in the popup.
- **Codex Usage** reads local `~/.codex/auth.json` and recent session snapshots, shows the current rate-limit window in the menu bar, and exposes the active window details in the popup.

<br>

<div align="center">
  <h3>Screenshots</h3>
  <img src="resources/preview-image-light.png" alt="Barik Light Theme">
  <img src="resources/preview-image-dark.png" alt="Barik Dark Theme">
</div>
<br>
<div align="center">
  <h3>Video</h3>
  <video src="https://github.com/user-attachments/assets/33cfd2c2-e961-4d04-8012-664db0113d4f">
</div>
    
https://github.com/user-attachments/assets/d3799e24-c077-4c6a-a7da-a1f2eee1a07f

<br>

## Requirements

- macOS 14.6+

## Quick Start

1. Install **barik** via [Homebrew](https://brew.sh/)

```sh
brew install --cask mocki-toki/formulae/barik
```

Or you can download from [Releases](https://github.com/mocki-toki/barik/releases), unzip it, and move it to your Applications folder.

2. _(Optional)_ To display open applications and spaces, install [**yabai**](https://github.com/koekeishiya/yabai) or [**AeroSpace**](https://github.com/nikitabobko/AeroSpace) and set up hotkeys. For **yabai**, you'll need **skhd** or **Raycast scripts**. Don't forget to configure **top padding** — [here's an example for **yabai**](https://github.com/mocki-toki/barik/blob/main/example/.yabairc).

3. Hide the system menu bar in **System Settings** and uncheck **Desktop & Dock → Show items → On Desktop**.

4. Launch **barik** from the Applications folder.

5. Add **barik** to your login items for automatic startup.

**That's it!** Try switching spaces and see the panel in action.

## Configuration

When you launch **barik** for the first time, it will create a `~/.barik-config.toml` file with an example customization for your new menu bar.

```toml
# If you installed yabai or aerospace without using Homebrew,
# manually set the path to the binary. For example:
#
# yabai.path = "/run/current-system/sw/bin/yabai"
# aerospace.path = ...

theme = "system" # system, light, dark

[widgets]
displayed = [ # widgets on menu bar
    "default.spaces",
    "spacer",
    "default.homebrew",
    "default.claude-usage",
    "default.codex-usage",
    "default.system-monitor",
    "default.nowplaying",
    "default.network",
    "default.battery",
    "divider",
    "default.weather",
    # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
    "default.time",
]

[widgets.default.spaces]
space.show-key = true        # show space number (or character, if you use AeroSpace)
window.show-title = true
window.title.max-length = 50

[widgets.default.claude-usage]
# plan = "Max" # optional manual badge override

[widgets.default.codex-usage]
# plan = "Pro" # optional manual badge override

[widgets.default.system-monitor]
show-icon = false
use-metric-icons = false
show-usage-bars = true
metrics-per-column = 2
layout = "rows" # rows, stacked
dividers = "none" # none, horizontal, vertical, both
metrics = ["cpu", "ram", "disk", "gpu", "network"] # order controls display order

cpu-warning-level = 70   # CPU warning threshold (%)
cpu-critical-level = 90  # CPU critical threshold (%)

ram-warning-level = 70   # RAM warning threshold (%)
ram-critical-level = 90  # RAM critical threshold (%)

disk-warning-level = 80  # Disk warning threshold (%)
disk-critical-level = 90 # Disk critical threshold (%)

gpu-warning-level = 70   # GPU warning threshold (%)
gpu-critical-level = 90  # GPU critical threshold (%)

# A list of applications that will always be displayed by application name.
# Other applications will show the window title if there is more than one window.
window.title.always-display-app-name-for = ["Mail", "Chrome", "Arc"]

[widgets.default.nowplaying.popup]
view-variant = "horizontal"

[widgets.default.battery]
show-percentage = true
warning-level = 30
critical-level = 10

[widgets.default.time]
format = "E d, J:mm"
calendar.format = "J:mm"

calendar.show-events = true
# calendar.allow-list = ["Home", "Personal"] # show only these calendars
# calendar.deny-list = ["Work", "Boss"] # show all calendars except these

[widgets.default.time.popup]
view-variant = "box"

[widgets.default.weather]
unit = "celsius"      # Options: "celsius" or "fahrenheit" (default: "fahrenheit")
latitude = "40.7128"  # Custom latitude (optional, uses device location if not set)
longitude = "-74.0060" # Custom longitude (optional, uses device location if not set)

[widgets.default.homebrew]
display-mode = "label" # label, icon, badge

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

## Usage Widgets

Two usage widgets are available out of the box:

- `default.claude-usage` tracks Claude Code usage from the `Claude Code-credentials` Keychain item. The popup shows the rolling 5-hour window and weekly usage.
- `default.codex-usage` tracks Codex usage from local auth and session data in `~/.codex`. The popup shows the active rate-limit window, reset time, and recent activity.

If you already have an existing `~/.barik-config.toml`, add these widget IDs manually to `widgets.displayed` to make them appear.

## System Monitor

`default.system-monitor` is a configurable multi-metric widget for system health.

- Supported metrics: `cpu`, `ram`, `disk`, `gpu`, `network`
- The `metrics` array controls both which metrics are shown and the order they appear in the widget and popup
- `use-metric-icons` replaces text labels with SF Symbols in the menu bar widget
- `show-usage-bars` hides the mini progress bars when disabled, leaving only the label or icon and the value
- `metrics-per-column` controls how many metrics are stacked vertically before the widget starts a new column
- `layout = "stacked"` switches the menu bar widget to a Stats-style layout with the title on top and the value below
- `dividers` adds separators between rows, columns, or both in the menu bar widget
- GPU usage is best-effort and may be unavailable on some systems or macOS configurations

## Weather Widget

`default.weather` displays current weather conditions in the menu bar and provides a detailed popup.

- Shows current temperature with SF Symbols for conditions
- Supports `celsius` and `fahrenheit`
- Uses device location by default or custom `latitude`/`longitude` (If coordinates are not provided, the widget will automatically use the device location).
- Popup includes hourly forecast, daily high/low, and precipitation probability
- Weather data is fetched from the Open-Meteo API

## Homebrew Widget

`default.homebrew` displays Homebrew package updates in the menu bar and provides a detailed popup with package management tools.

- Shows the number of outdated packages directly in the menu bar
- Supports multiple display modes: `label`, `icon`, and `badge`
- Popup lists outdated formulae and casks with version information
- Displays Homebrew version, installed package count, and last update time
- Includes built-in actions to run `brew update` and `brew upgrade`
- Streams live progress output during updates
- Detects packages that require `sudo` for upgrade and highlights them
- Uses caching to avoid frequent Homebrew calls and reduce CPU usage



```toml
[widgets.default.system-monitor]
show-icon = false
use-metric-icons = false
show-usage-bars = true
metrics-per-column = 2
layout = "rows"
dividers = "none"
metrics = ["cpu", "ram", "disk", "gpu", "network"]
```

Currently, you can customize the order of widgets (time, indicators, etc.) and adjust some of their settings. Soon, you’ll also be able to add custom widgets and completely change **barik**'s appearance—making it almost unrecognizable (hello, r/unixporn!).

## Future Plans

I'm not planning to stick to minimal functionality—exciting new features are coming soon! The roadmap includes full style customization, the ability to create custom widgets or extend existing ones, and a public **Store** where you can share your styles and widgets.

Soon, you'll also be able to place widgets not just at the top, but at the bottom, left, and right as well. This means you can replace not only the menu bar but also the Dock! 🚀

## What to do if the currently playing song is not displayed in the Now Playing widget?

Unfortunately, macOS does not support access to its API that allows music control. Fortunately, there is a workaround using Apple Script or a service API, but this requires additional work to integrate each service. Currently, the Now Playing widget supports the following services:

1. Spotify (requires the desktop application)
2. Apple Music (requires the desktop application)

Create an issue so we can add your favorite music service: https://github.com/mocki-toki/barik/issues/new

## Where Are the Menu Items?

[#5](https://github.com/mocki-toki/barik/issues/5), [#1](https://github.com/mocki-toki/barik/issues/1)

Menu items (such as File, Edit, View, etc.) are not currently supported, but they are planned for future releases. However, you can use [Raycast](https://www.raycast.com/), which supports menu items through an interface similar to Spotlight. I personally use it with the `option + tab` shortcut, and it works very well.

If you’re accustomed to using menu items from the system menu bar, simply move your mouse to the top of the screen to reveal the system menu bar, where they will be available.

<img src="resources/raycast-menu-items.jpeg" alt="Raycast Menu Items">

## Contributing

Contributions are welcome! Please feel free to submit a PR.

## License

[MIT](LICENSE)

## Trademarks

Apple and macOS are trademarks of Apple Inc. This project is not connected to Apple Inc. and does not have their approval or support.

## Stars

[![Stargazers over time](https://starchart.cc/mocki-toki/barik.svg?variant=adaptive)](https://starchart.cc/mocki-toki/barik)
