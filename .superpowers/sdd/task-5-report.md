# Task 5 Report: GitHubPopup (sign-in + stats view)

## Status: DONE

## Summary
Created `Barik/Widgets/GitHub/GitHubPopup.swift`, consumed by `GitHubWidget` (Task 4) as
the popup shown when the menu bar widget is clicked. Implements the three states driven
by `GitHubManager.shared.authState`:

- **Sign-in screen** (`.signedOut`): shows a GitHub icon, title, an error banner when
  `manager.errorMessage` is set, and a "Sign in with GitHub" button that calls
  `manager.startSignIn()`.
- **Device-code screen** (`.deviceFlowPending`): shows the verification URL, a
  copy-to-clipboard user code (with a transient "copied" confirmation), an "Open in
  Browser" button via `NSWorkspace.shared.open`, and a waiting/progress indicator while
  polling continues in the background.
- **Stats view** (`.signedIn`): header with login name and a last-updated/error indicator,
  a contribution heatmap (weeks x days grid colored by contribution intensity, built from
  `manager.data.contributionDays`), a "Quick Stats" metrics list (streak, commits today,
  open issues, open PRs, unread notifications, total stars), and Refresh / Sign Out
  actions.

Consumes `GitHubManager.shared` (`.authState`, `.data`, `.fetchFailed`, `.errorMessage`,
`.startSignIn()`, `.refresh()`, `.signOut()`) and `ConfigProvider` via
`@EnvironmentObject`, matching the interfaces from Tasks 1/3. Uses `RoutedSettingsLink(section: .github)`
in the header controls overlay, identical in pattern to `QwenProxyUsagePopup.swift:57`.

As documented in the brief, this reference requires `SettingsSection.github`, which does
not exist until Task 6 runs. This file was expected to fail to build on that one
reference at the time Task 5 was completed.

## Verification

### Build Command and Output (at Task 5 completion, commit 6644a4c)
```
xcodebuild -project Barik.xcodeproj -scheme Barik -configuration Debug build
```

**Expected failure (as per brief):**
```
/Users/xxspell/Code/barik/.claude/worktrees/github-widget/Barik/Widgets/GitHub/GitHubPopup.swift:25:46: error: type 'SettingsSection' has no member 'github'
** BUILD FAILED **
```

**Result:** Build failed with exactly this single error, matching the brief's expectation.
No other errors were present. Task 6 resolves this by adding the `.github` case to
`SettingsSection`.

## Commit
- `6644a4c` — `feat(github): add GitHubPopup with sign-in, device flow, and stats views`
  (on branch `worktree-github-widget`)

## Concerns (at time of Task 5)
None recorded. The forward reference to `SettingsSection.github` is intentional and
documented in the brief as resolved by Task 6.

---

## Fix: popup width, streak coloring, missing report

This section documents corrective work applied after Task 5 review found two deviations
from the brief and a missing report file (this file).

### Finding 1 — popup width was 340pt instead of 300pt
`GitHubPopup.swift` used `.frame(width: 340)`, inconsistent with every other popup in the
codebase (`QwenProxyUsagePopup.swift:42`, `NowPlayingPopup.swift:111`,
`HomebrewPopup.swift:20`, `FocusPopup.swift:30` all use `300`), and inconsistent with the
brief's own reference implementation. Changed to `.frame(width: 300)`. Reviewed the
sign-in view, device-code view, contribution heatmap, and metrics-grid layout for
assumptions tied to the wider frame — all use flexible (`maxWidth: .infinity`) or
fixed-size-but-narrow elements (8-9pt heatmap cells, wrapped text), so no overflow or
cramping resulted from the width change and no further layout adjustment was needed.

### Finding 2 — streak metric color was hardcoded to `.orange`
The "Quick Stats" streak row called `metricRow(..., color: .orange)` unconditionally,
never reflecting actual streak risk. Added the missing risk logic (matching the pattern
already present in `GitHubWidget.swift:13-19` for the bar icon, and matching the brief's
own `streakBadge` reference implementation):

```swift
private var streakWarningHour: Int {
    configProvider.config["streak-warning-hour"]?.intValue ?? 18
}

private var isPastWarningHour: Bool {
    Calendar.current.component(.hour, from: Date()) >= streakWarningHour
}

private var streakColor: Color {
    if manager.data.streakDays == 0 { return .red }
    if manager.data.commitsToday == 0 && isPastWarningHour { return .orange }
    return .green
}
```

The streak `metricRow` call now passes `color: streakColor` instead of the hardcoded
`.orange`. Kept the existing "Quick Stats" row-list structure rather than reverting to
the brief's separate `streakSection`/`streakBadge` layout, per instructions — only the
color-computation logic needed to be correct, not the visual structure.

Note on duplication: `streakWarningHour`/`isPastWarningHour` now exist in both
`GitHubWidget.swift` and `GitHubPopup.swift` with identical logic. This duplication
matches the brief's own reference implementation (which also duplicated this logic
between the widget and popup) and was left as-is rather than introducing a shared
location, since that would be a larger refactor than this fix warrants. If desired, a
follow-up could hoist both properties onto `GitHubManager` or a small shared helper.

### Build Command and Output (after fix)
```
xcodebuild -project Barik.xcodeproj -scheme Barik -configuration Debug build
```

**Result:**
```
/Users/xxspell/Code/barik/.claude/worktrees/github-widget/Barik/Widgets/GitHub/GitHubPopup.swift:25:46: error: type 'SettingsSection' has no member 'github'
** BUILD FAILED **
```

Confirmed this is the only error in the build output (checked via `grep -E "error:|BUILD (FAILED|SUCCEEDED)"` over the full log) — no regressions introduced by the width or streak-color changes. This is the same expected single error described above, still pending Task 6.

### Concerns
None. Both findings were narrow, targeted fixes consistent with existing patterns
elsewhere in the codebase (other popups' widths, `GitHubWidget`'s streak-risk logic).
