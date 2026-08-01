import SwiftUI

/// Widget for the menu, displaying Wi‑Fi and Ethernet icons.
struct NetworkWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var viewModel = NetworkStatusViewModel.shared
    @State private var rect: CGRect = .zero

    private var showWiFi: Bool { configProvider.config["show-wifi"]?.boolValue ?? true }
    private var showEthernet: Bool { configProvider.config["show-ethernet"]?.boolValue ?? true }

    var body: some View {
        BarikStyle.current.isTUI ? AnyView(tuiBody) : AnyView(defaultBody)
    }

    private var defaultBody: some View {
        HStack(spacing: 15) {
            if showWiFi && viewModel.wifiState != .notSupported {
                wifiIcon
            }
            if showEthernet && viewModel.ethernetState != .notSupported {
                ethernetIcon
            }
        }
        .captureScreenRect(into: $rect)
        .contentShape(Rectangle())
        .barikFont(size: 15)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "network") {
                NetworkPopup().environmentObject(configProvider)
            }
        }
    }

    private var tuiBody: some View {
        let style = BarikStyle.current
        return HStack(spacing: 8) {
            if showWiFi && viewModel.wifiState != .notSupported {
                Image(systemName: tuiWifiSymbol)
                    .foregroundStyle(tuiWifiColor(style: style))
            }
            if showEthernet && viewModel.ethernetState != .notSupported {
                Image(systemName: tuiEthernetSymbol)
                    .foregroundStyle(tuiEthernetColor(style: style))
            }
        }
        .barikFont(size: 13)
        .captureScreenRect(into: $rect)
        .contentShape(Rectangle())
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "network") {
                NetworkPopup().environmentObject(configProvider)
            }
        }
    }

    private var tuiWifiSymbol: String {
        if viewModel.ssid == "Not connected" { return "wifi.slash" }
        switch viewModel.wifiState {
        case .connected: return "wifi"
        case .connecting, .connectedWithoutInternet: return "wifi.exclamationmark"
        case .disconnected, .disabled, .notSupported: return "wifi.slash"
        }
    }

    private func tuiWifiColor(style: BarikStyle) -> Color {
        if viewModel.ssid == "Not connected" { return style.dim }
        switch viewModel.wifiState {
        case .connected: return style.foreground
        case .connecting, .connectedWithoutInternet: return style.accent
        case .disconnected, .disabled, .notSupported: return style.dim
        }
    }

    private var tuiEthernetSymbol: String {
        switch viewModel.ethernetState {
        case .connected, .connectedWithoutInternet: return "network"
        case .connecting, .disconnected: return "network.slash"
        case .disabled, .notSupported: return "network.slash"
        }
    }

    private func tuiEthernetColor(style: BarikStyle) -> Color {
        switch viewModel.ethernetState {
        case .connected: return style.foreground
        case .connectedWithoutInternet, .connecting: return style.accent
        case .disconnected, .disabled, .notSupported: return style.dim
        }
    }

    private var wifiIcon: some View {
        if viewModel.ssid == "Not connected" {
            return Image(systemName: "wifi.slash")
                .foregroundColor(.red)
        }
        switch viewModel.wifiState {
        case .connected:
            return Image(systemName: "wifi")
                .foregroundColor(.foregroundOutside)
        case .connecting:
            return Image(systemName: "wifi")
                .foregroundColor(.yellow)
        case .connectedWithoutInternet:
            return Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.yellow)
        case .disconnected:
            return Image(systemName: "wifi.slash")
                .foregroundColor(.gray)
        case .disabled:
            return Image(systemName: "wifi.slash")
                .foregroundColor(.red)
        case .notSupported:
            return Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.gray)
        }
    }

    private var ethernetIcon: some View {
        switch viewModel.ethernetState {
        case .connected:
            return Image(systemName: "network")
                .foregroundColor(.primary)
        case .connectedWithoutInternet:
            return Image(systemName: "network")
                .foregroundColor(.yellow)
        case .connecting:
            return Image(systemName: "network.slash")
                .foregroundColor(.yellow)
        case .disconnected:
            return Image(systemName: "network.slash")
                .foregroundColor(.red)
        case .disabled, .notSupported:
            return Image(systemName: "questionmark.circle")
                .foregroundColor(.gray)
        }
    }
}

struct NetworkWidget_Previews: PreviewProvider {
    static var previews: some View {
        NetworkWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
