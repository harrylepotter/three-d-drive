import SwiftUI
import WidgetKit
import AppIntents

@main struct ThreeDDriveApp: App {
    var body: some Scene { WindowGroup { DriveView() } }
}
struct Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent:EndThreeDDrive(),phrases:["End my drive in \(.applicationName)"],shortTitle:"End drive",systemImageName:"stop.circle")
    }
}
struct DriveView: View {
    @Environment(\.scenePhase) var phase
    @Environment(\.verticalSizeClass) var verticalSize
    @State private var signedIn = (try? Vault.load()) != nil
    @State private var token = ""
    @State private var snapshot: Snapshot?
    @State private var busy = false
    @State private var warning = ""
    @State private var revision = 0
    private let accent = Color(red:1,green:0.64,blue:0.32)
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            HStack {
                Image(systemName:"dot.radiowaves.left.and.right").foregroundStyle(accent)
                Text("THREE D RADIO").font(.headline).tracking(2)
                Spacer()
                Text("93.7 FM").font(.system(.subheadline,design:.monospaced))
            }
            Spacer()
            if !signedIn {
                Text("Connect to Home Assistant").font(.largeTitle.bold())
                Text(DriveClient.server.absoluteString).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                SecureField("Home Assistant access token",text:$token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    .textFieldStyle(.roundedBorder).preferredColorScheme(.dark)
                Button("Connect") { run {
                    try await DriveClient.shared.connect(token:token)
                    token=""
                    signedIn = true
                } }.buttonStyle(.borderedProminent)
            } else if let s = snapshot {
                if s.active {
                    if let track=s.track {
                        DriveCover(track:track)
                            .frame(maxWidth:.infinity,alignment:.leading)
                            .frame(height:verticalSize == .compact ? 54 : 190)
                            .id(track.id + (track.artwork ?? ""))
                        Text(track.title).font(.system(size:42,weight:.bold)).minimumScaleFactor(0.7)
                        Text(track.artist).font(.title2).foregroundStyle(.secondary)
                        Button { run {
                            _ = try await DriveClient.shared.like(track.id)
                            if snapshot?.track?.id == track.id { snapshot?.liked=true }
                            WidgetCenter.shared.reloadTimelines(ofKind:"ThreeDHeart")
                        } } label: {
                            Label(s.liked == true ? "Liked" : "Like this song",systemImage:s.liked == true ? "heart.fill":"heart")
                                .font(.title3.bold()).frame(maxWidth:.infinity,minHeight:48)
                        }.buttonStyle(.borderedProminent).disabled(s.liked == true)
                        Text("liked from 3d radio").font(.caption).foregroundStyle(.secondary)
                    } else { Label("Listening for a match",systemImage:"waveform").font(.title2) }
                    Button("End drive") { change("end") }.buttonStyle(.bordered)
                } else {
                    Text("Tune your radio to 93.7 FM").font(.largeTitle.bold())
                    Button { change("start") } label:{ Label("Start Three D",systemImage:"radio").font(.title3.bold()).frame(maxWidth:.infinity,minHeight:48) }.buttonStyle(.borderedProminent)
                }
            } else if warning.isEmpty { ProgressView("Connecting to Home Assistant") }
            if !warning.isEmpty {
                Text(warning).font(.callout).accessibilityLabel("Status: "+warning)
                if signedIn { Button("Retry") { run {} } }
            }
            Spacer()
        }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.leading)
        .background(Color(red:0.075,green:0.08,blue:0.085)).tint(accent).preferredColorScheme(.dark)
        .disabled(busy)
        .task(id:"\(signedIn)-\(phase)") {
            guard signedIn,phase == .active else { return }
            var nextRegistration = Date.distantPast
            while !Task.isCancelled {
                if !busy { await refresh() }
                if Date.now >= nextRegistration {
                    // WidgetKit may still be generating the first token when the app opens.
                    nextRegistration = .now.addingTimeInterval(await registerWidget() ? 600 : 20)
                }
                do { try await Task.sleep(for:.seconds(8)) } catch { break }
            }
        }
    }
    private func registerWidget() async -> Bool {
        guard let push = await WidgetCenter.shared.currentPushInfo else {
            #if DEBUG
            let configurations = try? await WidgetCenter.shared.currentConfigurations()
            print("Three D awaiting WidgetKit token; configured widgets:", configurations?.count ?? 0)
            #endif
            return false
        }
        do {
            try await DriveClient.shared.registerWidget(token: push.token)
            return true
        } catch {
            #if DEBUG
            print("Three D widget registration deferred:", error.localizedDescription)
            #endif
            return false
        }
    }
    @MainActor private func refresh() async {
        let observed=revision
        do {
            let updated=try await DriveClient.shared.request("status")
            guard !Task.isCancelled, observed==revision else {return}
            if snapshot?.active != updated.active || snapshot?.track != updated.track || snapshot?.liked != updated.liked {
                WidgetCenter.shared.reloadTimelines(ofKind: "ThreeDHeart")
                #if DEBUG
                print("Three D widget reload requested:", updated.track?.title ?? (updated.active ? "listening" : "off"))
                #endif
            }
            snapshot=updated; warning=""
        } catch { if !Task.isCancelled && observed==revision { warning=error.localizedDescription; snapshot=nil } }
    }
    private func change(_ name:String) { run {
        try await DriveClient.shared.command(name)
        WidgetCenter.shared.reloadTimelines(ofKind:"ThreeDHeart")
    } }
    private func run(_ operation:@escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy=true;revision+=1
        Task { @MainActor in
            defer {busy=false}
            do { try await operation(); if signedIn {await refresh()} }
            catch { warning=error.localizedDescription }
        }
    }
}
struct DriveCover: View {
    let track: Track
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            if let image { Image(uiImage:image).resizable().scaledToFit() }
            else { RoundedRectangle(cornerRadius:10).fill(.quaternary).overlay { Image(systemName:"opticaldisc").font(.largeTitle).foregroundStyle(.secondary) } }
        }.aspectRatio(1,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:10)).accessibilityHidden(true)
        .task {
            if let bytes = await DriveClient.shared.cover(track), !Task.isCancelled {
                image=UIImage(data:bytes)
                #if DEBUG
                if let image { print("Three D displayed cover:",track.title,Int(image.size.width),Int(image.size.height)) }
                #endif
            }
        }
    }
}
