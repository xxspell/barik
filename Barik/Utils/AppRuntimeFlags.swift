import Foundation

/// Flags derived from how the current process was launched.
/// These never change during the process lifetime.
enum AppRuntimeFlags {
    /// Set via `--dev-export` on the command line. Gates the dev-only
    /// "Widget Export" settings section — invisible otherwise.
    static let isWidgetExportEnabled = CommandLine.arguments.contains("--dev-export")
}
