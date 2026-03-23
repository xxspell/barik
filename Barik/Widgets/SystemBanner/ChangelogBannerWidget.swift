import SwiftUI

struct ChangelogBannerWidget: View {
    @State private var rect: CGRect = .zero

    var body: some View {

        Button(action: {
            MenuBarPopup.show(rect: rect, id: "changelog") {
                ChangelogPopup()
            }
        }) {
            HStack(alignment: .center) {
                Text("What's new")
                    .fontWeight(.semibold)
                Image(systemName: "xmark.circle.fill")
                    .onTapGesture {
                        NotificationCenter.default.post(name: Notification.Name("HideWhatsNewBanner"), object: nil)
                    }
            }
        }
        .captureScreenRect(into: $rect)
        .buttonStyle(BannerButtonStyle(color: .green.opacity(0.8)))
        .transition(.blurReplace)

    }
}

struct ChangelogBannerWidget_Previews: PreviewProvider {
    static var previews: some View {
        ChangelogBannerWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
