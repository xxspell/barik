import SwiftUI

struct ScreenRecordingWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject var manager: ScreenRecordingManager
    
    private var showLabel: Bool {
        if let explicit = configProvider.config["show-label"]?.boolValue {
            return explicit
        }
        if let explicit = configProvider.config["show_label"]?.boolValue {
            return explicit
        }
        if let explicit = configProvider.config["show-text"]?.boolValue {
            return explicit
        }
        if let explicit = configProvider.config["show_text"]?.boolValue {
            return explicit
        }

        return true
    }

    var body: some View {
        Group {
            if ScreenRecordingManager.shouldShowStopWidget(isRecording: manager.isRecording) {
                Button(action: manager.stopRecording) {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8, weight: .bold))
                        if showLabel {
                            Text("REC")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, showLabel ? 8 : 6)
                    .frame(height: 18)
                    .background(.red.gradient)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Stop screen recording")
            }
        }
    }
}

#Preview {
    ScreenRecordingWidget(manager: ScreenRecordingManager.shared)
}
