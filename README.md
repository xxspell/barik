
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

It also supports compact usage widgets for **Claude Code**, **Codex**, and **CLIProxy**, plus practical widgets for **System Monitor**, **Focus**, **Weather**, **Homebrew**, **TickTick**, **Now Playing**, and a native macOS **screen recording stop** control:

- **Claude Usage** reads your Claude Code credentials from Keychain, shows current 5-hour usage as a ring in the menu bar, and exposes 5-hour plus weekly usage in the popup.
- **Codex Usage** reads local `~/.codex/auth.json` and recent session snapshots, shows the current rate-limit window in the menu bar, and exposes the active window details in the popup.
- **CLIProxy Usage** connects to the local Management API, shows quota percentage in the menu bar, and exposes overview and account tabs with token stats, provider filters, time-range aware top API keys, and quota switching settings in the popup.
- **System Monitor** shows configurable CPU, RAM, disk, GPU, and network metrics in the menu bar with a detailed popup.
- **Focus** shows the active macOS Focus mode as a compact badge and lists available Focus modes in a read-only popup.
- **Keyboard Layout** shows the current macOS input source in the menu bar and lets you switch layouts from a popup list.
- **Weather** displays current conditions with location-aware forecasts and a popup powered by Open-Meteo.
- **Homebrew** shows outdated package counts in the menu bar and exposes update and upgrade actions in the popup.
- **TickTick** shows pending task counts in the menu bar and provides tasks, habits, and an Eisenhower matrix in the popup.
- **Pomodoro** provides a local/offline focus timer with notes, overtime adjustment, history, stats, and optional TickTick private API sync.
- **Shortcuts** shows a compact Apple Shortcuts launcher in the menu bar with grouped popup execution and folder filtering.
- **Now Playing** shows the currently playing song with album art and media state in the menu bar.
- **Screen Recording Stop** appears only while a native macOS screen recording is active and stops it from the menu bar.

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
    "default.screen-recording-stop",
    "default.homebrew",
    "default.claude-usage",
    "default.codex-usage",
    "default.system-monitor",
    "default.nowplaying",
    "default.network",
    # "default.focus",
    # "default.shortcuts",
    "default.keyboard-layout",
    "default.battery",
    "divider",
    "default.weather",
    # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
    "default.time",
]

[widgets.default.spaces]
space.show-key = true        # show space number (or character, if you use AeroSpace)
space.show-inactive = true
space.show-empty = true
space.show-delete-button = true
window.show-title = true
window.show-hidden = false
window.icon-desaturation = 0
window.show-hover-tooltip = false
window.hover-tooltip = "{app} ({pid})"
window.title.max-length = 50

# Hidden yabai windows can stay visible in the Spaces widget with a small minus badge
# on the app icon when `window.show-hidden = true`.
# Inactive and empty spaces are shown by default and can be hidden separately.
# Empty yabai spaces can show a hover delete button that destroys the space.
# Window icons can be desaturated from `0` to `100`, where `100` is fully grayscale.
# Hover tooltips can be enabled and customized with placeholders like
# `{app}`, `{title}`, `{pid}`, `{id}`, and `{state}`.

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
metrics = ["cpu", "temperature", "ram", "disk", "gpu", "network"] # order controls display order

cpu-warning-level = 70   # CPU warning threshold (%)
cpu-critical-level = 90  # CPU critical threshold (%)

temperature-warning-level = 80   # Temperature warning threshold (°C)
temperature-critical-level = 95  # Temperature critical threshold (°C)

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

[widgets.default.keyboard-layout]
show-text = true     # show current layout label in the widget
show-outline = true  # draw a capsule outline around the label

[widgets.default.focus]
show-name = false
tint-with-focus-color = true

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

[widgets.default.pomodoro]
mode = "auto" # local, ticktick, auto
display-mode = "timer" # timer, today-pomodoros
focus-duration = 25
short-break-duration = 5
long-break-duration = 15
long-break-interval = 4
show-seconds = false
play-sound-on-focus-end = true
play-sound-on-break-end = true
focus-finished-sound = "pomo-v1.mp3"
break-finished-sound = "pomo-v2.wav"
repeat-break-finished-sound-until-popup-opened = false
break-finished-sound-repeat-interval-seconds = 12
history-window-days = 180

[widgets.default.shortcuts]
# include-folders = ["Work", "Personal"] # show only these folders; use "none" for uncategorized shortcuts
# exclude-folders = ["Archive"] # ignored when include-folders is set
# exclude-shortcuts = ["Debug Shortcut", "Temporary Shortcut"]

[widgets.default.screen-recording-stop]
show-label = true

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

## Pomodoro Widget

The Pomodoro widget supports two operating modes:

- `local`: fully offline mode with cached history and statistics.
- `ticktick`: uses TickTick private API for preferences, history, statistics, completed pomodoro sync, task binding, and overtime adjustment.
- `auto`: uses TickTick when a private TickTick session is available, otherwise falls back to local mode.

The menu bar widget can render in two styles:

- `display-mode = "timer"` shows the current timer state.
- `display-mode = "today-pomodoros"` shows one tomato icon per completed pomodoro today and expands in width as the count grows.

The popup supports:

- task selection from TickTick tasks
- free-text task context
- focus notes stored with the pomodoro record
- overtime adjustment after the timer completes
- history and summary statistics

Important note: TickTick pomodoro is only available through the private TickTick API. The public OAuth/OpenAPI integration does not expose pomodoro endpoints, so TickTick sync requires a private email/password TickTick sign-in inside the widget.

## Shortcuts Widget

`default.shortcuts` adds a compact Apple Shortcuts launcher to Barik.

- Clicking the widget opens a popup with your Shortcuts grouped by folder
- Shortcuts can be run directly from the popup
- While a shortcut is running, the popup row shows a loading state and the menu bar icon switches to a spinner
- `include-folders` acts as an allow-list and takes precedence over `exclude-folders`
- `exclude-shortcuts` hides individual shortcuts by name
- Use `"none"` inside `include-folders` or `exclude-folders` to control uncategorized shortcuts

Example config:

```toml
[widgets]
displayed = [
    "default.shortcuts",
]

[widgets.default.shortcuts]
include-folders = ["Menu Bar", "Work"]
exclude-shortcuts = ["Dangerous Shortcut"]
```

Three usage widgets are available out of the box:

- `default.claude-usage` tracks Claude Code usage from the `Claude Code-credentials` Keychain item. The popup shows the rolling 5-hour window and weekly usage.
- `default.codex-usage` tracks Codex usage from local auth and session data in `~/.codex`. The popup shows the active rate-limit window, reset time, and recent activity.
- `default.cliproxy-usage` tracks your CLIProxy Management API. The popup shows provider quota percentage, an overview tab with token usage filters and time-range aware top API keys, an accounts tab with Codex/Qwen account availability and remaining quota, and the current `quota-exceeded` behavior.

If you already have an existing `~/.barik-config.toml`, add these widget IDs manually to `widgets.displayed` to make them appear.

Example config:

```toml
[widgets.default.cliproxy-usage]
base-url = "http://localhost:8317"
api-key = "your-management-key"
show-ring = true
ring-logic = "failed"
warning-level = 90
critical-level = 80
show-label = true
refresh-interval = 300
```

The widget accepts either the server root URL like `http://localhost:8317` or the full Management API path like `http://localhost:8317/v0/management`.
`refresh-interval` is optional and is measured in seconds. The minimum supported value is `15`.
`warning-level` and `critical-level` are based on remaining quota percentage. Older `ring-warning-level` and `ring-critical-level` keys are still supported for compatibility.

## Focus Widget

`default.focus` adds a compact macOS Focus indicator to Barik.

- The widget appears only while a Focus mode is active
- It shows the active Focus mode icon using the system tint color when available
- The popup lists all detected Focus modes and highlights the currently active one
- The popup is currently read-only and does not switch Focus modes yet

Example config:

```toml
[widgets]
displayed = [
    "default.focus",
]

[widgets.default.focus]
show-name = false
tint-with-focus-color = true
```

## Screen Recording Stop Widget

`default.screen-recording-stop` adds a native macOS screen recording stop control to Barik.

- The widget is hidden by default and only appears while a native macOS screen recording is active
- Clicking the widget triggers the same stop control exposed by macOS in the menu bar
- The widget needs **Accessibility** permission to press the native stop control
- Barik can detect an active recording and prompt for Accessibility automatically when the widget is enabled
- `show-label = true` shows the `REC` text next to the stop icon
- `show-label = false` keeps the widget in a compact icon-only mode

Example config:

```toml
[widgets]
displayed = [
    "default.screen-recording-stop",
]

[widgets.default.screen-recording-stop]
show-label = true
```

## System Monitor

`default.system-monitor` is a configurable multi-metric widget for system health.

- Supported metrics: `cpu`, `temperature`, `ram`, `disk`, `gpu`, `network`
- The `metrics` array controls both which metrics are shown and the order they appear in the widget and popup
- `use-metric-icons` replaces text labels with SF Symbols in the menu bar widget
- `show-usage-bars` hides the mini progress bars when disabled, leaving only the label or icon and the value
- `metrics-per-column` controls how many metrics are stacked vertically before the widget starts a new column
- `layout = "stacked"` switches the menu bar widget to a Stats-style layout with the title on top and the value below
- `dividers` adds separators between rows, columns, or both in the menu bar widget
- CPU temperature is read from SMC sensor keys with Apple Silicon fallbacks inspired by Stats
- GPU usage and temperature are best-effort and may be unavailable on some systems or macOS configurations
- The popup now has a detailed Stats-style view plus a built-in settings view for toggling sections and fields
- Popup section visibility can be configured independently from the compact menu bar widget

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
network-display-mode = "single" # single, dual-line
metrics-per-column = 2
layout = "rows"
dividers = "none"
metrics = ["cpu", "temperature", "ram", "disk", "gpu", "network"]
```

Detailed popup configuration:

```toml
[widgets.default.system-monitor.popup]
view-variant = "vertical"
metrics = ["cpu", "temperature", "ram", "disk", "gpu", "network"]
cpu-details = ["usage", "user", "system", "idle", "temperature", "cores", "load-average"]
temperature-details = ["cpu", "gpu"]
ram-details = ["used", "app", "free", "pressure"]
disk-details = ["used", "free", "total"]
gpu-details = ["utilization", "temperature"]
network-details = ["status", "download", "upload", "interface"]
```

- `network-display-mode = "dual-line"` turns the menu bar network metric into two stacked rows: upload on the first line and download on the second
- `popup.metrics` controls which sections appear in the detailed popup and in what order
- The popup now uses compact dashboard cards. Smaller sections such as temperature, GPU, and network can share a row, while larger sections stay full width for readability
- `cpu-details` lets you choose from `usage`, `user`, `system`, `idle`, `temperature`, `cores`, `load-average`
- `temperature-details` lets you choose from `cpu`, `gpu`
- `ram-details` lets you choose from `used`, `app`, `active`, `inactive`, `wired`, `compressed`, `cache`, `free`, `swap`, `pressure`, `total`
- RAM usage now follows the same broad model as Stats: inactive/speculative memory is counted, cache is separated, and swap plus pressure are available in the popup
- `disk-details` lets you choose from `volume`, `used`, `free`, `total`
- Disk free space prefers recoverable capacity and important-usage capacity, which makes it closer to what Stats reports for the system volume
- `gpu-details` lets you choose from `utilization`, `temperature`
- `network-details` lets you choose from `interface`, `status`, `download`, `upload`, `total-downloaded`, `total-uploaded`
- Network speeds and totals now track the current primary interface by default, which avoids inflated numbers from bridge or secondary interfaces
- You can also change these options directly from the popup gear view without editing TOML by hand

## TickTick Widget

`default.ticktick` integrates with TickTick to display tasks, habits, and priorities in the menu bar with a detailed popup for task management.

- Shows the number of pending tasks in the menu bar (with badge counter)
- Can rotate a single pending task or habit in the menu bar at a configurable interval
- Supports both OAuth2 and username/password authentication methods
- Integrates with calendar popup to show tasks alongside calendar events
- Provides full task management: create, update, complete, delete tasks
- Supports Eisenhower matrix for task prioritization (urgent/important)
- Includes habit tracking with streak calculation and daily check-ins
- Implements background refresh with retry and automatic re-authentication
- Securely stores credentials using Keychain
- Offers local caching for improved startup performance
- Popup view includes task filtering, priority indicators, and due dates


```toml
[widgets.default.ticktick]
display-mode = "badge" # badge, rotating-item
rotating-item-change-interval = 900 # seconds, minimum 5, default 15 minutes
rotating-item-max-width = 148 # px, minimum 60
rotating-item-sources = ["tasks", "habits"] # tasks, habits, all
tint-rotating-item-text = false

[widgets.default.ticktick.rotating-tasks]
overdue = true
today = true
important = true
tomorrow = true
normal = true
priorities = ["medium", "high"] # low, medium, high
```

When `display-mode = "rotating-item"`, the widget will show one unfinished task or unchecked habit at a time and rotate through the filtered set at random. Clicking the rotating item opens the TickTick popup, switches to the matching tab, scrolls to the related task or habit, and temporarily highlights it. Task rotation can be narrowed to overdue, today, important, tomorrow, or normal items, and the `priorities` list controls which priority levels count as `important`.

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
