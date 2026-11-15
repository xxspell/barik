import Foundation

/// Display frame rate from the IOReport "DCP*/swap" channels (display core
/// packet swap counter), following exelban/Stats. Subscription is created once;
/// each read yields frames per second since the previous read.
final class FPSReader {
    private var channels: CFMutableDictionary?
    private var subscription: IOReportSubscriptionRef?
    private var previousCount: Int64 = 0
    private var previousTime: CFAbsoluteTime = 0

    init() {
        setup()
    }

    // The subscription is process-lifetime (kept like Stats); no teardown.

    var isAvailable: Bool { subscription != nil }

    private func setup() {
        let groups = ["DCP", "DCP0", "DCPEXT0", "DCPEXT1", "DCPEXT2", "DCPEXT3"]
        var merged: CFMutableDictionary?
        for group in groups {
            guard let channel = IOReportCopyChannelsInGroup(group as CFString, "swap" as CFString, 0, 0, 0)?
                .takeRetainedValue() else { continue }
            if merged == nil {
                merged = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channel)
            } else {
                IOReportMergeChannels(merged, channel, nil)
            }
        }
        guard let merged, let dict = merged as? [String: Any], dict["IOReportChannels"] != nil else { return }

        channels = merged
        var sub: Unmanaged<CFMutableDictionary>?
        subscription = IOReportCreateSubscription(nil, merged, &sub, 0, nil)
        sub?.release()
    }

    /// Frames per second, nil until two samples exist or IOReport is absent.
    func read() -> Double? {
        guard let subscription, let channels,
              let sample = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue(),
              let dict = sample as? [String: Any],
              let channelsList = dict["IOReportChannels"] as? NSArray else { return nil }
        let items = channelsList as CFArray

        var total: Int64 = 0
        for i in 0..<CFArrayGetCount(items) {
            let item = unsafeBitCast(CFArrayGetValueAtIndex(items, i), to: CFDictionary.self)
            guard let group = IOReportChannelGetGroup(item)?.takeUnretainedValue() as? String,
                  group.hasPrefix("DCP"),
                  let subGroup = IOReportChannelGetSubGroup(item)?.takeUnretainedValue() as? String,
                  subGroup == "swap" else { continue }
            total += IOReportSimpleGetIntegerValue(item, 0)
        }

        let now = CFAbsoluteTimeGetCurrent()
        defer {
            previousCount = total
            previousTime = now
        }
        guard previousTime != 0, now > previousTime else { return nil }
        let delta = total - previousCount
        guard delta >= 0 else { return nil }
        return Double(delta) / (now - previousTime)
    }
}
