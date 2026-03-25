import SwiftUI

/// Window displaying detailed network status information.
struct NetworkPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var viewModel = NetworkStatusViewModel.shared
    @State private var controlsHovered = false

    private var popupConfig: ConfigData {
        configProvider.config["popup"]?.dictionaryValue ?? [:]
    }

    private var showSignalStrength: Bool { popupConfig["show-signal-strength"]?.boolValue ?? true }
    private var showRSSI: Bool { popupConfig["show-rssi"]?.boolValue ?? true }
    private var showNoise: Bool { popupConfig["show-noise"]?.boolValue ?? true }
    private var showChannel: Bool { popupConfig["show-channel"]?.boolValue ?? true }
    private var showEthernetSection: Bool { popupConfig["show-ethernet-section"]?.boolValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.wifiState != .notSupported {
                HStack(spacing: 8) {
                    wifiIcon
                    Text(viewModel.ssid)
                        .foregroundColor(.white)
                        .font(.headline)
                }

                if viewModel.ssid != "Not connected"
                    && viewModel.ssid != "No interface"
                {
                    VStack(alignment: .leading, spacing: 4) {
                        if showSignalStrength {
                            Text("Signal strength: \(viewModel.wifiSignalStrength.rawValue)")
                        }
                        if showRSSI {
                            Text("RSSI: \(viewModel.rssi)")
                        }
                        if showNoise {
                            Text("Noise: \(viewModel.noise)")
                        }
                        if showChannel {
                            Text("Channel: \(viewModel.channel)")
                        }
                    }
                    .font(.subheadline)
                }
            }

            // Ethernet section
            if showEthernetSection && viewModel.ethernetState != .notSupported {
                HStack(spacing: 8) {
                    ethernetIcon
                    Text("Ethernet: \(viewModel.ethernetState.rawValue)")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
        .padding(25)
        .background(Color.black)
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 3) {
                RoutedSettingsLink(section: .network) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 13, height: 10)
                }
                .buttonStyle(NetworkPopupControlButtonStyle())
            }
            .padding(.trailing, 12)
            .padding(.bottom, 10)
            .opacity(controlsHovered ? 1 : 0)
        }
        .onHover { hovering in
            withAnimation(.easeIn(duration: 0.2)) {
                controlsHovered = hovering
            }
        }
    }

    /// Chooses the Wi‑Fi icon based on the status and connection availability.
    private var wifiIcon: some View {
        if viewModel.ssid == "Not connected" {
            return Image(systemName: "wifi.slash")
                .padding(8)
                .background(Color.red.opacity(0.8))
                .clipShape(Circle())
                .foregroundStyle(.white)
        }
        switch viewModel.wifiState {
        case .connected:
            return Image(systemName: "wifi")
                .padding(8)
                .background(Color.blue.opacity(0.8))
                .clipShape(Circle())
                .foregroundStyle(.white)
        case .connecting:
            return Image(systemName: "wifi")
                .padding(8)
                .background(Color.yellow.opacity(0.8))
                .clipShape(Circle())
                .foregroundStyle(.white)
        case .connectedWithoutInternet:
            return Image(systemName: "wifi.exclamationmark")
                .padding(8)
                .background(Color.yellow.opacity(0.8))
                .clipShape(Circle())
                .foregroundStyle(.white)
        case .disconnected:
            return Image(systemName: "wifi.slash")
                .padding(8)
                .background(Color.gray.opacity(0.8))
                .clipShape(Circle())
                .foregroundStyle(.white)
        case .disabled:
            return Image(systemName: "wifi.slash")
                .padding(8)
                .background(Color.red.opacity(0.8))
                .clipShape(Circle())
                .foregroundStyle(.white)
        case .notSupported:
            return Image(systemName: "wifi.exclamationmark")
                .padding(8)
                .background(Color.gray.opacity(0.8))
                .clipShape(Circle())
                .foregroundStyle(.white)
        }
    }

    private var ethernetIcon: some View {
        switch viewModel.ethernetState {
        case .connected:
            return Image(systemName: "network")
                .padding(8)
                .background(Color.blue.opacity(0.8))
                .clipShape(Circle())
        case .connectedWithoutInternet:
            return Image(systemName: "network")
                .padding(8)
                .background(Color.yellow.opacity(0.8))
                .clipShape(Circle())
        case .connecting:
            return Image(systemName: "network.slash")
                .padding(8)
                .background(Color.yellow.opacity(0.8))
                .clipShape(Circle())
        case .disconnected:
            return Image(systemName: "network.slash")
                .padding(8)
                .background(Color.gray.opacity(0.8))
                .clipShape(Circle())
        case .disabled:
            return Image(systemName: "network.slash")
                .padding(8)
                .background(Color.red.opacity(0.8))
                .clipShape(Circle())
        case .notSupported:
            return Image(systemName: "questionmark.circle")
                .padding(8)
                .background(Color.gray.opacity(0.8))
                .clipShape(Circle())
        }
    }
}

private struct NetworkPopupControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                NetworkPopupControlButtonBody(configuration: configuration)
            )
    }
}

private struct NetworkPopupControlButtonBody: View {
    let configuration: NetworkPopupControlButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color.white.opacity(0.18)
                            : (isHovered ? Color.gray.opacity(0.4) : Color.clear)
                    )
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct NetworkPopup_Previews: PreviewProvider {
    static var previews: some View {
        NetworkPopup()
            .previewLayout(.sizeThatFits)
    }
}
