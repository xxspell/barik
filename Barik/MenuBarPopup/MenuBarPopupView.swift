import SwiftUI

struct MenuBarPopupView<Content: View>: View {
    let content: Content
    let isPreview: Bool
    let widgetRect: CGRect
    let screenFrame: CGRect

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    private let horizontalMargin: CGFloat = 16

    @State private var contentSize: CGSize = .zero
    @State private var viewFrame: CGRect = .zero
    @State private var animationValue: Double = 0.01
    private var animated: Bool { isShowAnimation || isHideAnimation }
    @State private var isShowAnimation = false
    @State private var isHideAnimation = false

    private let willShowWindow = NotificationCenter.default.publisher(
        for: .willShowWindow)
    private let willHideWindow = NotificationCenter.default.publisher(
        for: .willHideWindow)
    private let willChangeContent = NotificationCenter.default.publisher(
        for: .willChangeContent)

    init(
        widgetRect: CGRect = .zero,
        screenFrame: CGRect = .zero,
        isPreview: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.widgetRect = widgetRect
        self.screenFrame = screenFrame
        self.content = content()
        self.isPreview = isPreview
        if isPreview {
            _animationValue = State(initialValue: 1.0)
        }
    }

    var popupTopPosition: CGFloat {
        foregroundHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .fixedSize(horizontal: true, vertical: true)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                DispatchQueue.main.async {
                                    contentSize = geometry.size
                                }
                            }
                            .onChange(of: geometry.size) { _, newSize in
                                contentSize = newSize
                            }
                    }
                )
                .background(Color.black)
                .cornerRadius(((1.0 - animationValue) * 1) + 40)
                .shadow(radius: 30)
                .blur(radius: (1.0 - (0.1 + 0.9 * animationValue)) * 20)
                .scaleEffect(
                    x: 0.2 + 0.8 * animationValue,
                    y: animationValue,
                    anchor: .top
                )
                .offset(x: computedOffset, y: popupTopPosition)
                .opacity(animationValue)
                .transaction { transaction in
                    if isHideAnimation {
                        transaction.animation = .linear(duration: 0.1)
                    }
                }
                .onReceive(willShowWindow) { _ in
                    isShowAnimation = true
                    withAnimation(
                        .smooth(
                            duration: Double(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            ) / 1000.0, extraBounce: 0.3)
                    ) {
                        animationValue = 1.0
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now()
                            + .milliseconds(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            )
                    ) {
                        isShowAnimation = false
                    }
                }
                .onReceive(willHideWindow) { _ in
                    isHideAnimation = true
                    withAnimation(
                        .interactiveSpring(
                            duration: Double(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            ) / 1000.0)
                    ) {
                        animationValue = 0.01
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now()
                            + .milliseconds(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            )
                    ) {
                        isHideAnimation = false
                    }
                }
                .onReceive(willChangeContent) { _ in
                    isHideAnimation = true
                    withAnimation(
                        .spring(
                            duration: Double(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            ) / 1000.0)
                    ) {
                        animationValue = 0.01
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now()
                            + .milliseconds(
                                Constants
                                    .menuBarPopupAnimationDurationInMilliseconds
                            )
                    ) {
                        isHideAnimation = false
                    }
                }
                .animation(
                    .smooth(duration: 0.3), value: animated ? 0 : computedOffset
                )
                .animation(
                    .smooth(duration: 0.3),
                    value: animated ? 0 : computedYOffset
                )
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        DispatchQueue.main.async {
                            viewFrame = geometry.frame(in: .global)
                        }
                    }
                    .onChange(of: geometry.size) { _, __ in
                        viewFrame = geometry.frame(in: .global)
                    }
            }
        )
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    var computedOffset: CGFloat {
        let contentWidth = contentSize.width > 0 ? contentSize.width : 200
        let localMidX = widgetRect.midX - screenFrame.minX
        let minOffset = horizontalMargin
        let maxOffset = screenFrame.width - contentWidth - horizontalMargin
        let centeredOffset = localMidX - contentWidth / 2
        let xOffset = maxOffset >= minOffset
            ? min(max(centeredOffset, minOffset), maxOffset)
            : minOffset

        return xOffset
    }

    var computedYOffset: CGFloat {
        return 0
    }
}

extension Notification.Name {
    static let willShowWindow = Notification.Name("willShowWindow")
    static let willHideWindow = Notification.Name("willHideWindow")
    static let willChangeContent = Notification.Name("willChangeContent")
}
