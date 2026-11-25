import Foundation
import Security


enum DriveError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct Track: Codable, Equatable {
    let id: String
    let artist: String
    let title: String
    let seen: TimeInterval
    var artwork: String?
}

struct Snapshot: Codable {
    let active: Bool
    var endsAt: TimeInterval?
    var track: Track?
    var lastTrack: Track?
    var liked: Bool?
    var accepted: Bool?
    var message: String?
}

struct Account: Codable {
    let token: String
}

// Send credentials only to the origin selected at build time.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum Vault {
    static func query() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "DriveKeychainGroup") as? String, !group.isEmpty else {
            throw DriveError.message("Missing shared keychain configuration.")
        }
        return [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"ThreeDDrive",
                kSecAttrAccount as String:"home-assistant", kSecAttrAccessGroup as String:group]
    }
    static func load() throws -> Account {
        var q = try query()
        q[kSecReturnData as String] = true
        var raw: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &raw) == errSecSuccess, let data = raw as? Data else {
            throw DriveError.message("Connect to Home Assistant in the Three D Drive app.")
        }
        return try JSONDecoder().decode(Account.self, from:data)
    }
    static func save(_ account: Account) throws {
        let q = try query()
        let fields: [String:Any] = [kSecValueData as String:try JSONEncoder().encode(account),
                                   kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var result = SecItemUpdate(q as CFDictionary, fields as CFDictionary)
        if result == errSecItemNotFound { result = SecItemAdd(q.merging(fields) { $1 } as CFDictionary,nil) }
        guard result == errSecSuccess else { throw DriveError.message("Unable to save your sign-in in Keychain.") }
    }
}

actor DriveClient {
    static let shared = DriveClient()
    static let server: URL = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let host = info["DriveHost"] as? String, !host.isEmpty,
              let scheme = info["DriveScheme"] as? String, ["https", "http"].contains(scheme),
              let portText = info["DrivePort"] as? String, let port = Int(portText),
              (1...65535).contains(port) else { preconditionFailure("Check the Drive server settings in Config.") }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.port = port
        guard let url = parts.url else { preconditionFailure("Invalid Drive server host.") }
        return url
    }()
    private let transport = URLSession(configuration:.ephemeral,delegate:NoRedirect(),delegateQueue:nil)
    private let covers = NSCache<NSString, NSData>()
    private var registeredToken: Data?

    func connect(token: String) async throws {
        let value = token.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty else { throw DriveError.message("Enter your Home Assistant access token.") }
        var req = URLRequest(url:Self.server.appendingPathComponent("api/"),timeoutInterval:12)
        req.setValue("Bearer " + value,forHTTPHeaderField:"Authorization")
        _ = try await send(req)
        try Vault.save(Account(token:value))
    }
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for:request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DriveError.message("Home Assistant returned HTTP " + String((response as? HTTPURLResponse)?.statusCode ?? 0) + ".")
        }
        return data
    }
    private func action(_ path: String, _ body: [String:String], response: Bool, timeout: TimeInterval = 25) async throws -> Data {
        let account = try Vault.load()
        var url = Self.server.appendingPathComponent("api/services/" + path)
        if response { url = url.appending(queryItems:[URLQueryItem(name:"return_response",value:nil)]) }
        var req = URLRequest(url:url,timeoutInterval:timeout)
        req.httpMethod="POST"
        req.setValue("Bearer " + account.token,forHTTPHeaderField:"Authorization")
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=try JSONEncoder().encode(body)
        return try await send(req)
    }
    func command(_ name: String) async throws {
        _ = try await action("script/three_d_drive_" + name,[:],response:false)
    }
    func registerWidget(token: Data) async throws {
        guard !token.isEmpty, registeredToken != token else { return }
        struct Registration: Decodable {
            struct Result: Decodable {
                struct Content: Decodable { let registered: Bool }
                let status: Int
                let content: Content
            }
            let service_response: Result
        }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        let data = try await action("rest_command/three_d_drive_request",
                                    ["operation": "register_widget", "push_token": hex],
                                    response: true, timeout: 8)
        let result = try JSONDecoder().decode(Registration.self, from: data).service_response
        guard result.status == 200, result.content.registered else {
            throw DriveError.message("Home Assistant could not register the widget.")
        }
        registeredToken = token
        #if DEBUG
        print("Three D widget registered for track changes.")
        #endif
    }
    func request(_ operation: String, id: String = "") async throws -> Snapshot {
        struct Envelope: Decodable {
            struct Reply: Decodable { let status: Int; let content: Snapshot? }
            let service_response: Reply
        }
        let data = try await action("rest_command/three_d_drive_request",["operation":operation,"track_id":id],response:true)
        let reply = try JSONDecoder().decode(Envelope.self,from:data).service_response
        guard reply.status == 200, let snapshot = reply.content else { throw DriveError.message("The station listener is unavailable.") }
        return snapshot
    }
    func like(_ id: String) async throws -> Snapshot {
        let s = try await request("like",id:id)
        guard s.accepted == true else { throw DriveError.message(s.message ?? "Refresh to identify the song.") }
        return s
    }
    func cover(_ track: Track, timeout: TimeInterval = 10) async -> Data? {
        guard let artwork = track.artwork else { return nil }
        if let cached = covers.object(forKey:artwork as NSString) { return cached as Data }
        struct Envelope: Decodable {
            struct Reply: Decodable {
                struct Payload: Decodable { var image: Data? }
                let content: Payload
            }
            let service_response: Reply
        }
        do {
            let payload = try await action("rest_command/three_d_drive_request",
                ["operation":"artwork","track_id":track.id], response:true, timeout:timeout)
            guard let bytes = try JSONDecoder().decode(Envelope.self,from:payload).service_response.content.image else {return nil}
            covers.totalCostLimit = 4 * 1024 * 1024
            covers.setObject(bytes as NSData,forKey:artwork as NSString,cost:bytes.count)
            return bytes
        } catch { return nil }
    }
}
