import SwiftUI

struct TickTickWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = TickTickManager.shared

    @State private var widgetFrame: CGRect = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("TickTickIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.foregroundOutside)
                .opacity(manager.isAuthenticated ? 1.0 : 0.6)

            // Badge with count
            if manager.isAuthenticated && manager.totalPendingCount > 0 {
                Text("\(min(manager.totalPendingCount, 99))")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .offset(x: 6, y: -5)
            }
        }
        .frame(width: 28, height: 20)
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { widgetFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "ticktick") {
                TickTickPopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            manager.startUpdating(config: configProvider.config)
        }
    }
}
