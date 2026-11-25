import AppIntents
import WidgetKit

struct LikeDisplayedSong: AppIntent {
    static let title: LocalizedStringResource = "Like displayed Three D song"
    @Parameter(title:"Recording") var recording: String
    init() {}
    init(_ id: String) { recording=id }
    func perform() async throws -> some IntentResult {
        _ = try await DriveClient.shared.like(recording)
        WidgetCenter.shared.reloadTimelines(ofKind:"ThreeDHeart")
        return .result()
    }
}
struct LikeLiveSong: AppIntent {
    static let title: LocalizedStringResource = "Like live Three D song"
    func perform() async throws -> some IntentResult {
        let reply = try await DriveClient.shared.request("like_current")
        guard reply.accepted == true else { throw DriveError.message(reply.message ?? "Waiting for a fresh match.") }
        WidgetCenter.shared.reloadTimelines(ofKind:"ThreeDHeart")
        return .result()
    }
}

struct StartThreeDDrive: AppIntent {
    static let title: LocalizedStringResource = "Start Three D Drive"
    func perform() async throws -> some IntentResult {
        try await DriveClient.shared.command("start")
        WidgetCenter.shared.reloadTimelines(ofKind:"ThreeDHeart")
        return .result()
    }
}

struct EndThreeDDrive: AppIntent {
    static let title: LocalizedStringResource = "End Three D Drive"
    static let description = IntentDescription("Stop the car session when CarPlay disconnects. Kiosks continue independently.")
    func perform() async throws -> some IntentResult {
        try await DriveClient.shared.command("end")
        WidgetCenter.shared.reloadTimelines(ofKind:"ThreeDHeart")
        return .result()
    }
}
struct RefreshDrive: AppIntent {
    static let title: LocalizedStringResource = "Refresh Three D song"
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind:"ThreeDHeart"); return .result()
    }
}
