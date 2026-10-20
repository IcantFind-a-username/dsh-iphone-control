import Foundation

// MARK: - Wire models (mirror the /pocket/api JSON)

struct PocketImageRef: Codable, Equatable {
    var mediaType: String?
    var name: String?
    var attachmentId: String?
}

struct PocketUsage: Codable, Equatable {
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var total: Int?
    var secs: Double?
    var tps: Double?
    var cacheRate: Double?
}

struct PocketItem: Codable, Identifiable, Equatable {
    var id: String
    var k: String
    var seq: Double?
    var t: Double?
    var text: String?
    var think: String?
    var imgs: [PocketImageRef]?
    var callId: String?
    var name: String?
    var label: String?
    var detail: String?
    var status: String?
    var result: String?
    var isError: Bool?
    var usage: PocketUsage?

    var time: Date? {
        guard let t else { return nil }
        return Date(timeIntervalSince1970: t / 1000)
    }
}

struct PocketSession: Codable, Identifiable, Equatable {
    var id: String
    var title: String?
    var cwd: String?
    var running: Bool?
    var updatedAt: Double?
    var blank: Bool?

    var name: String { title?.isEmpty == false ? title! : "会话" }
    var updated: Date? {
        guard let updatedAt else { return nil }
        return Date(timeIntervalSince1970: updatedAt / 1000)
    }
}

struct LiveState: Codable, Equatable {
    var text: String
    var think: String

    static let empty = LiveState(text: "", think: "")
}

struct FeedSession: Codable, Equatable {
    var id: String
    var title: String?
}

struct FeedResponse: Codable {
    var ok: Bool
    var session: FeedSession?
    var rev: Int
    var running: Bool
    var live: LiveState?
    var hasMore: Bool?
    var oldestSeq: Int?
    var title: String?
    var items: [PocketItem]
}

struct SessionsResponse: Codable {
    var ok: Bool
    var items: [PocketSession]
}

struct NewSessionResponse: Codable {
    var ok: Bool
    var id: String
    var cwd: String?
}

struct SendResponse: Codable {
    var ok: Bool
    var requestId: String?
}

struct SimpleResponse: Codable {
    var ok: Bool
    var error: String?
}

struct WhaleEvent: Codable, Identifiable, Equatable {
    var ts: Double
    var model: String?
    var cost: Double?
    var tokens: Double?

    var id: Double { ts }
}

struct WhaleResponse: Codable, Equatable {
    var ok: Bool
    var error: String?
    var date: String?
    var balance: Double?
    var today: Double?
    var events: [WhaleEvent]?
    var offPeak: Bool?
    var peakLabel: String?
    var updatedAt: Double?
}

struct PingResponse: Codable {
    var ok: Bool
    var version: String?
}

enum PocketError: LocalizedError {
    case message(String)
    case badURL

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .badURL: return "服务器地址无效"
        }
    }
}
