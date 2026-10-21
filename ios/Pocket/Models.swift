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

struct AskOption: Codable, Equatable {
    var label: String
    var description: String
}

struct AskQuestion: Codable, Equatable {
    var header: String
    var question: String
    var multiSelect: Bool
    var options: [AskOption]
}

struct AskPayload: Codable, Equatable {
    var questions: [AskQuestion]
}

struct ContextUsage: Codable, Equatable {
    var used: Int?
    var window: Int?
    var ratio: Double?
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
    var ask: AskPayload?

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
    var context: ContextUsage?
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

struct PermissionOption: Codable, Identifiable, Equatable {
    var value: String
    var name: String
    var id: String { value }
}

struct PermissionCatalog: Codable, Equatable {
    var ok: Bool
    var current: String?
    var options: [PermissionOption]
    var defaultPreset: String?
}

struct PermissionResponse: Codable {
    var ok: Bool
    var current: String?
    var error: String?
}

struct ModelSelection: Codable, Equatable {
    var provider: String
    var model: String
    var reasoningEffort: String?
}

struct ReasoningEffortOption: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}

struct ModelReasoning: Codable, Equatable {
    var efforts: [ReasoningEffortOption]
    var defaultEffort: String?
}

struct ModelEntry: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String?
    var reasoning: ModelReasoning?
}

struct ModelGroup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var models: [ModelEntry]
}

struct ModelFailure: Codable, Equatable {
    var id: String
    var name: String
    var message: String
}

struct ModelCatalog: Codable, Equatable {
    var ok: Bool
    var `default`: ModelSelection?
    var groups: [ModelGroup]
    var failures: [ModelFailure]?
    var current: ModelSelection?
}

struct SelectModelResponse: Codable {
    var ok: Bool
    var selection: ModelSelection?
}

struct PingResponse: Codable {
    var ok: Bool
    var version: String?
}

enum PocketError: LocalizedError {
    case message(String)
    case badURL
    case gone

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .badURL: return "服务器地址无效"
        case .gone: return "这个会话的日志文件已丢失，请新建会话"
        }
    }
}
