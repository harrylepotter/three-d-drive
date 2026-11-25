import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let state: Snapshot?
    var cover: UIImage?
    var relevance: TimelineEntryRelevance? {
        state?.active == true ? TimelineEntryRelevance(score: 50, duration: 150) : nil
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, state: Snapshot(active: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await fetch()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            async let registration: Void = registerIfNeeded()
            let entry = await fetch()
            await registration
            var entries = [entry]
            if let track = entry.state?.track {
                let expires = Date(timeIntervalSince1970: track.seen + 150)
                if expires > entry.date {
                    var last = entry.state
                    last?.track = nil
                    last?.lastTrack = track
                    entries.append(Entry(date: expires, state: last, cover: entry.cover))
                }
            }
            if let shown = entry.state?.track ?? entry.state?.lastTrack {
                let heartExpires = Date(timeIntervalSince1970: shown.seen + 300)
                if heartExpires > entry.date, let last = entries.last {
                    entries.append(Entry(date: heartExpires, state: last.state, cover: last.cover))
                }
            }
            if let end = entry.state?.endsAt, end > entry.date.timeIntervalSince1970 {
                let endDate = Date(timeIntervalSince1970: end)
                entries.removeAll { $0.date >= endDate }
                entries.append(Entry(date: endDate, state: Snapshot(active: false)))
            }
            let interval: TimeInterval = entry.state?.active == false ? 15 * 60 : 65
            completion(Timeline(entries: entries, policy: .after(entry.date.addingTimeInterval(interval))))
        }
    }

    private func registerIfNeeded() async {
        if let info = await WidgetCenter.shared.currentPushInfo {
            try? await DriveClient.shared.registerWidget(token: info.token)
        }
    }

    private func fetch() async -> Entry {
        do {
            let state = try await DriveClient.shared.request("status")
            var cover: UIImage?
            if let track = state.track ?? state.lastTrack, let bytes = await DriveClient.shared.cover(track, timeout: 5),
               let image = UIImage(data: bytes) {
                cover = await image.byPreparingThumbnail(ofSize: CGSize(width: 256, height: 256))
            }
            // Date the entry after I/O so a match expiring mid-fetch never gets a live heart.
            var display = state
            if let track = state.track, Date.now.timeIntervalSince1970 >= track.seen + 150 {
                display.lastTrack = track
                display.track = nil
            }
            if let end = state.endsAt, end <= Date.now.timeIntervalSince1970 {
                display = Snapshot(active: false)
            }
            return Entry(date: .now, state: display, cover: display.active ? cover : nil)
        } catch {
            return Entry(date: .now, state: nil)
        }
    }
}

struct DrivePushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        guard widgets.contains(where: { $0.kind == "ThreeDHeart" }) else { return }
        Task { try? await DriveClient.shared.registerWidget(token: pushInfo.token) }
    }
}

struct DialArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.23, green: 0.24, blue: 0.26), Color(white: 0.075)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<15) { mark in
                        Rectangle()
                            .fill(mark == 9 ? Color.orange : Color.white.opacity(0.68))
                            .frame(width: mark == 9 ? 2 : 1, height: mark == 9 ? 17 : (mark.isMultiple(of: 3) ? 12 : 7))
                    }
                }
                Text("93.7").font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.69, blue: 0.39))
            }
        }
    }
}

struct DriveWidgetView: View {
    let entry: Entry
    private var track: Track? { entry.state?.track ?? entry.state?.lastTrack }
    private var subtitle: String {
        if let track { return track.artist }
        if let active = entry.state?.active { return active ? "Listening for a match" : "Drive is off" }
        return "Home Assistant offline"
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width * 0.57, geometry.size.height * 0.52)
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image = entry.cover {
                            Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                        } else {
                            DialArtwork()
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottom) {
                        if entry.state?.lastTrack != nil {
                            Text("Last heard").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.black.opacity(0.85), in: Capsule()).padding(3)
                        }
                    }
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)

                    if let track, entry.date.timeIntervalSince1970 < track.seen + 300 {
                        let liked = entry.state?.liked == true
                        Button(intent: LikeDisplayedSong(track.id)) {
                            Image(systemName: liked ? "heart.fill" : "heart")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(liked ? Color.pink : .white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.82), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(liked)
                        .accessibilityLabel(liked ? "Liked " + track.title : "Like " + track.title)
                    }
                }
                Text(track?.title ?? "Three D Radio")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(2).minimumScaleFactor(0.83)
                    .accessibilityLabel((entry.state?.lastTrack == nil ? "" : "Last heard: ") + (track?.title ?? "Three D Radio"))
                Text(subtitle).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.82)
                if entry.state?.active == false {
                    Button(intent: StartThreeDDrive()) {
                        Text("Start drive").font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 25)
                    }.buttonStyle(.bordered)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .containerBackground(for: .widget) {
            ZStack {
                Color(white: 0.095)
                if let image = entry.cover {
                    Image(uiImage: image).resizable().scaledToFill().blur(radius: 20).opacity(0.30)
                }
            }
        }
    }
}

@main struct DriveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ThreeDHeart", provider: Provider()) { DriveWidgetView(entry: $0) }
            .configurationDisplayName("Three D • Like this song")
            .description("See the latest Three D Radio match and save it to liked from 3d radio.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
            .pushHandler(DrivePushHandler.self)
    }
}
