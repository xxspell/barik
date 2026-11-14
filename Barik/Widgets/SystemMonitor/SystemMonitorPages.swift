import SwiftUI

// Page implementations are fleshed out page by page; each fills the content
// area next to the sidebar and scrolls vertically.

private struct SMPageScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
        }
    }
}

struct SMOverviewPage: View {
    var body: some View {
        SMPageScroll {
            Text("Overview")
        }
    }
}

struct SMCPUPage: View {
    var body: some View {
        SMPageScroll {
            Text("CPU")
        }
    }
}

struct SMGPUPage: View {
    var body: some View {
        SMPageScroll {
            Text("GPU")
        }
    }
}

struct SMRAMPage: View {
    var body: some View {
        SMPageScroll {
            Text("RAM")
        }
    }
}

struct SMDiskPage: View {
    var body: some View {
        SMPageScroll {
            Text("Disk")
        }
    }
}

struct SMNetworkPage: View {
    var body: some View {
        SMPageScroll {
            Text("Network")
        }
    }
}
