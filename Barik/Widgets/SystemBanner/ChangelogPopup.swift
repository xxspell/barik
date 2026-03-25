import MarkdownUI
import SwiftUI

struct ChangelogPopup: View {
    @Environment(\.dismiss) private var dismiss
    @State private var changelogText = "Loading..."
    @State private var availableVersions: [String] = []
    @State private var selectedVersion: String?
    @State private var fullChangelog = ""

    private let popupWidth: CGFloat = 760
    private let popupHeight: CGFloat = 720

    private var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            ScrollView {
                Markdown(changelogText)
                    .markdownTheme(.barik)
                    .markdownImageProvider(WebImageProvider())
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 22)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: popupWidth, height: popupHeight)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task {
            await loadChangelog()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Changelog")
                    .font(.system(size: 20, weight: .semibold))

                if availableVersions.isEmpty {
                    Text("Version \(bundleVersion)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    Picker("Version", selection: Binding(
                        get: { selectedVersion ?? bundleVersion },
                        set: { newValue in
                            selectedVersion = newValue
                            updateDisplayedVersion(newValue)
                        }
                    )) {
                        ForEach(availableVersions, id: \.self) { version in
                            Text(version).tag(version)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.white)
                }
            }

            Spacer()

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func close() {
        dismiss()
        MenuBarPopup.hide()
    }

    private func loadChangelog() async {
        guard
            let url = URL(
                string:
                    "https://raw.githubusercontent.com/xxspell/barik/main/CHANGELOG.md"
            )
        else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let fullChangelog = String(data: data, encoding: .utf8) else {
                await updateChangelogText("Failed to load CHANGELOG.")
                return
            }

            await MainActor.run {
                self.fullChangelog = fullChangelog
                self.availableVersions = extractVersions(from: fullChangelog)

                let initialVersion: String
                if availableVersions.contains(bundleVersion) {
                    initialVersion = bundleVersion
                } else {
                    initialVersion = availableVersions.first ?? bundleVersion
                }

                self.selectedVersion = initialVersion
                updateDisplayedVersion(initialVersion)
            }
        } catch {
            await updateChangelogText("Failed to load CHANGELOG.")
        }
    }

    @MainActor
    private func updateChangelogText(_ text: String) {
        changelogText = text
    }

    @MainActor
    private func updateDisplayedVersion(_ version: String) {
        let extractedSection = extractSection(
            forVersion: version,
            from: fullChangelog
        )
        changelogText = extractedSection.isEmpty
            ? "Changelog for v\(version) not found"
            : extractedSection
    }

    private func extractVersions(from changelog: String) -> [String] {
        changelog
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.hasPrefix("## ") else { return nil }
                return String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private func extractSection(
        forVersion version: String,
        from changelog: String
    ) -> String {
        let lines = changelog.components(separatedBy: .newlines)

        guard
            let versionIndex = lines.firstIndex(where: {
                $0.contains("## \(version)")
            })
        else {
            return ""
        }

        var sectionLines: [String] = []
        for i in versionIndex..<lines.count {
            let line = lines[i]

            if i == versionIndex, line.hasPrefix("## ") {
                continue
            }

            if i != versionIndex && line.hasPrefix("## ") {
                break
            }

            if line == "<br>" {
                sectionLines.append("### ")
            } else {
                sectionLines.append(line)
            }
        }

        return sectionLines.joined(separator: "\n")
    }
}

struct ChangelogPopup_Previews: PreviewProvider {
    static var previews: some View {
        ChangelogPopup()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
