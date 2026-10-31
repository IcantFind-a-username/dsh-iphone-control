import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var baseURL: String
    @Published private(set) var token: String
    @Published private(set) var deviceToken: String
    @Published private(set) var deviceId: String

    @Published var sessionId: String?
    @Published var title = "Pocket"
    @Published var items: [PocketItem] = []
    @Published var sessions: [PocketSession] = []
    @Published var rev = -1
    @Published var running = false
    @Published var liveText = ""
    @Published var liveThink = ""
    @Published var connected = false
    @Published var connectionError: String?
    @Published var pendingText: String?
    @Published var pendingImages = 0
    @Published var hasMore = false
    @Published var oldestSeq: Double?
    @Published var loadingOlder = false
    @Published var sending = false
    @Published var cwd = ""
    @Published var whale: WhaleResponse?
    @Published var context: ContextUsage?
    @Published var modelCatalog: ModelCatalog?
    @Published var permissions: PermissionCatalog?
    @Published var modelLoading = false
    @Published var whaleLoading = false

    private var pollTask: Task<Void, Never>?
    private var generation = 0
    private var toastTask: Task<Void, Never>?
    @Published var toast: String?
    @Published var sidebarOpen = false
    private let imageCache = NSCache<NSString, UIImage>()
    private var lastRunning = false

    init() {
        baseURL = UserDefaults.standard.string(forKey: "pocket.base") ?? PocketDefaults.baseURL
        token = UserDefaults.standard.string(forKey: "pocket.token") ?? PocketDefaults.token
        deviceToken = UserDefaults.standard.string(forKey: "pocket.device") ?? ""
        deviceId = UserDefaults.standard.string(forKey: "pocket.deviceId") ?? ""
    }

    /// True when this phone holds a Secure Enclave key for the server.
    var hasBiometricKey: Bool {
        !deviceId.isEmpty && BiometricKey.load() != nil
    }

    /// Re-auth with Face ID: challenge → sign in the Secure Enclave → device token.
    @discardableResult
    func biometricUnlock() async -> Bool {
        guard let api, !deviceId.isEmpty, let key = BiometricKey.load() else { return false }
        do {
            let challenge: ChallengeResponse = try await api.post("api/challenge", json: ["deviceId": deviceId])
            guard let nonce = challenge.nonce else { return false }
            let signature = try BiometricKey.sign(key, nonce)
            let verified: PairResponse = try await api.post("api/verify", json: ["deviceId": deviceId, "signature": signature])
            guard let token = verified.deviceToken, !token.isEmpty else {
                flash(verified.error ?? "Face ID 校验失败")
                return false
            }
            deviceToken = token
            UserDefaults.standard.set(token, forKey: "pocket.device")
            connectionError = nil
            await start()
            return true
        } catch {
            flash(error.localizedDescription)
            return false
        }
    }

    var paired: Bool { api != nil && !token.isEmpty }
    var liveActive: Bool { running || !liveText.isEmpty || !liveThink.isEmpty }

    private var api: PocketAPI? {
        let credential = deviceToken.isEmpty ? token : deviceToken
        return PocketAPI(baseURLString: baseURL, token: credential)
    }

    // MARK: - Pairing

    static func normalizedBase(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return value }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        if !value.lowercased().hasSuffix("/pocket") { value += "/pocket" }
        return value
    }

    @discardableResult
    func pair(base: String, token: String, code: String = "") async -> Bool {
        let base = Self.normalizedBase(base)
        guard let candidate = PocketAPI(baseURLString: base, token: token) else {
            connectionError = "服务器地址无效"
            return false
        }

        do {
            let info: PairInfo = try await candidate.get("api/pair-info")
            var payload: [String: Any] = [
                "token": token.trimmingCharacters(in: .whitespacesAndNewlines),
                "label": UIDevice.current.name
            ]
            let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if info.totp {
                guard trimmedCode.count == 6 else {
                    connectionError = "这台电脑已开启两步验证，请输入 Authenticator 里的 6 位验证码"
                    return false
                }
                payload["code"] = trimmedCode
            }
            let response: PairResponse = try await candidate.post("api/pair", json: payload)
            guard let deviceToken = response.deviceToken, !deviceToken.isEmpty else {
                connectionError = response.error ?? "配对失败"
                return false
            }
            self.baseURL = base.trimmingCharacters(in: .whitespacesAndNewlines)
            self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            self.deviceToken = deviceToken
            if let newId = response.deviceId, !newId.isEmpty {
                self.deviceId = newId
                UserDefaults.standard.set(newId, forKey: "pocket.deviceId")
            }
            UserDefaults.standard.set(self.baseURL, forKey: "pocket.base")
            UserDefaults.standard.set(self.token, forKey: "pocket.token")
            UserDefaults.standard.set(self.deviceToken, forKey: "pocket.device")
            connectionError = nil
            await start()
            return true
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    func unpair() {
        pollTask?.cancel()
        pollTask = nil
        token = ""
        deviceToken = ""
        sessionId = nil
        items = []
        UserDefaults.standard.removeObject(forKey: "pocket.token")
        UserDefaults.standard.removeObject(forKey: "pocket.device")
    }

    // MARK: - Lifecycle

    private var started = false

    func startIfNeeded() async {
        guard !started else { return }
        started = true
        guard paired else { return }
        await start()
    }

    func start() async {
        guard paired else { return }
        await loadSessions()
        let stored = UserDefaults.standard.string(forKey: "pocket.session")
        if let stored, sessions.contains(where: { $0.id == stored && $0.blank != true }) {
            await open(stored)
        } else if let first = sessions.first(where: { $0.blank != true }) ?? sessions.first {
            await open(first.id)
        } else {
            await newSession()
        }
    }

    func loadSessions() async {
        guard let api else { return }
        do {
            let response: SessionsResponse = try await api.get("api/sessions")
            sessions = response.items
            connected = true
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func flash(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    func open(_ id: String) async {
        generation += 1
        let gen = generation
        pollTask?.cancel()
        sessionId = id
        items = []
        rev = -1
        running = false
        liveText = ""
        liveThink = ""
        pendingText = nil
        hasMore = false
        oldestSeq = nil
        UserDefaults.standard.set(id, forKey: "pocket.session")
        guard let api else { return }

        if let known = sessions.first(where: { $0.id == id }) {
            title = known.name
            cwd = known.cwd ?? ""
        }

        do {
            let feed: FeedResponse = try await api.get("api/session", query: [.init(name: "id", value: id)])
            guard gen == generation else { return }
            if let feedTitle = feed.session?.title, !feedTitle.isEmpty {
                title = feedTitle
            } else if let feedTitle = feed.title, !feedTitle.isEmpty {
                title = feedTitle
            }
            merge(feed.items)
            rev = feed.rev
            running = feed.running
            liveText = feed.live?.text ?? ""
            liveThink = feed.live?.think ?? ""
            hasMore = feed.hasMore ?? false
            oldestSeq = feed.oldestSeq.map(Double.init)
            context = feed.context
            connected = true
            connectionError = nil
        } catch {
            if case PocketError.gone = error {
                flash("这个会话已失效，已切换到其他会话")
                await loadSessions()
                if let next = sessions.first(where: { $0.id != id }) {
                    await open(next.id)
                } else {
                    await newSession()
                }
                return
            }
            connectionError = error.localizedDescription
        }
        startPolling()
        Task { await loadModels() }
        Task { await loadPermissions() }
    }

    // MARK: - Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let delay: UInt64 = self.running ? 450_000_000 : 1_200_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    func refresh() async {
        guard let sessionId, let api else { return }
        let gen = generation
        do {
            let feed: FeedResponse = try await api.get(
                "api/events",
                query: [
                    .init(name: "id", value: sessionId),
                    .init(name: "after", value: String(rev))
                ]
            )
            guard gen == generation, self.sessionId == sessionId else { return }
            merge(feed.items)
            rev = feed.rev
            running = feed.running
            liveText = feed.live?.text ?? ""
            liveThink = feed.live?.think ?? ""
            context = feed.context
            if let feedTitle = feed.title, !feedTitle.isEmpty { title = feedTitle }
            connected = true
            connectionError = nil
            if lastRunning && !running { Haptics.done() }
            lastRunning = running
        } catch {
            connected = false
            connectionError = error.localizedDescription
        }
    }

    private func merge(_ incoming: [PocketItem]) {
        guard !incoming.isEmpty else { return }
        var map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in incoming { map[item.id] = item }
        items = map.values.sorted { ($0.seq ?? 0) < ($1.seq ?? 0) }
        if let pendingText, incoming.contains(where: { $0.k == "u" && ($0.text ?? "") == pendingText }) {
            self.pendingText = nil
        }
    }

    // MARK: - Actions

    func send(text: String, images: [Data], mode: String = "queue") async {
        guard let sessionId, let api else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }

        sending = true
        pendingText = trimmed.isEmpty ? "（图片）" : trimmed
        pendingImages = images.count
        defer { sending = false }

        var payload: [String: Any] = ["id": sessionId, "text": trimmed, "mode": mode]
        if !images.isEmpty {
            payload["images"] = images.map { data -> [String: Any] in
                [
                    "mediaType": "image/jpeg",
                    "data": data.base64EncodedString(),
                    "name": "photo.jpg"
                ]
            }
        }

        do {
            let _: SendResponse = try await api.post("api/send", json: payload)
            Haptics.tap()
        } catch {
            connectionError = error.localizedDescription
            pendingText = nil
            pendingImages = 0
            Haptics.error()
            flash(error.localizedDescription)
        }
    }

    func stopTurn() async {
        guard let sessionId, let api else { return }
        let _: SimpleResponse? = try? await api.post("api/cancel", json: ["id": sessionId])
        Haptics.tap()
    }

    func newSession() async {
        guard let api else { return }
        do {
            var payload: [String: Any] = [:]
            if !cwd.isEmpty { payload["cwd"] = cwd }
            let created: NewSessionResponse = try await api.post("api/new", json: payload)
            await loadSessions()
            await open(created.id)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadImage(sessionId: String, ref: PocketImageRef) async -> UIImage? {
        guard let attachmentId = ref.attachmentId, let api else { return nil }
        let key = "\(sessionId):\(attachmentId)" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        do {
            let data = try await api.data("api/image", query: [
                .init(name: "id", value: sessionId),
                .init(name: "ref", value: attachmentId)
            ])
            guard let image = UIImage(data: data) else { return nil }
            imageCache.setObject(image, forKey: key)
            return image
        } catch {
            return nil
        }
    }

    func loadPermissions() async {
        guard let api, let sessionId else { return }
        do {
            let catalog: PermissionCatalog = try await api.get("api/permissions", query: [.init(name: "id", value: sessionId)])
            permissions = catalog
        } catch {
            /* optional */
        }
    }

    func selectPermission(_ value: String) async {
        guard let api, let sessionId else { return }
        do {
            let response: PermissionResponse = try await api.post("api/permission", json: [
                "id": sessionId, "preset": value
            ])
            if response.ok {
                permissions?.current = response.current ?? value
                Haptics.tap()
                flash("权限已切换为\(permissionLabel(value))")
            } else {
                flash(response.error ?? "切换失败")
            }
        } catch {
            flash(error.localizedDescription)
        }
    }

    func permissionLabel(_ value: String) -> String {
        switch value {
        case "read-only": return "只读"
        case "workspace-write": return "工作区可写"
        case "danger-full-access": return "完全访问"
        case "custom": return "自定义"
        default: return value
        }
    }

    var currentPermissionLabel: String {
        guard let value = permissions?.current, !value.isEmpty else { return "权限" }
        return permissionLabel(value)
    }

    @discardableResult
    func deleteSession(_ id: String) async -> Bool {
        guard let api else { return false }
        do {
            let response: SimpleResponse = try await api.post("api/delete-session", json: ["id": id])
            if response.ok {
                sessions.removeAll { $0.id == id }
                if sessionId == id {
                    if let next = sessions.first {
                        await open(next.id)
                    } else {
                        await newSession()
                    }
                }
                Haptics.tap()
                flash(response.hidden == true ? "已从手机移除（电脑上还在运行）" : "会话已删除")
                return true
            }
            flash(response.error ?? "删除失败")
        } catch {
            flash(error.localizedDescription)
        }
        return false
    }

    func loadModels() async {
        guard let api else { return }
        modelLoading = true
        defer { modelLoading = false }
        do {
            let catalog: ModelCatalog = try await api.get("api/models", query: [
                .init(name: "id", value: sessionId ?? "")
            ])
            modelCatalog = catalog
        } catch {
            flash(error.localizedDescription)
        }
    }

    func selectModel(provider: String, model: String, reasoningEffort: String?) async {
        guard let sessionId, let api else { return }
        do {
            var payload: [String: Any] = ["id": sessionId, "provider": provider, "model": model]
            if let reasoningEffort { payload["reasoningEffort"] = reasoningEffort }
            let response: SelectModelResponse = try await api.post("api/model", json: payload)
            if let selection = response.selection {
                modelCatalog?.current = selection
            }
            Haptics.tap()
            flash("已切换到 \(modelName(provider: provider, model: model))")
            await refresh()
        } catch {
            flash(error.localizedDescription)
            Haptics.error()
        }
    }

    func modelName(provider: String, model: String) -> String {
        if let entry = modelCatalog?.groups.first(where: { $0.id == provider })?.models.first(where: { $0.id == model }) {
            return entry.name
        }
        return model
    }

    var currentModelLabel: String {
        guard let current = modelCatalog?.current else { return "模型" }
        return modelName(provider: current.provider, model: current.model)
    }

    func loadWhale() async {
        guard let api else { return }
        whaleLoading = true
        defer { whaleLoading = false }
        do {
            whale = try await api.get("api/whale")
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func retry() async {
        if sessionId == nil {
            await start()
        } else {
            await refresh()
        }
    }

    func loadOlder() async {
        guard !loadingOlder, let sessionId, let api, let oldest = oldestSeq, hasMore else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let response: OlderResponse = try await api.get(
                "api/older",
                query: [
                    .init(name: "id", value: sessionId),
                    .init(name: "before", value: String(Int(oldest)))
                ]
            )
            merge(response.items)
            hasMore = response.hasMore ?? false
            if let newRev = response.rev, newRev > rev { rev = newRev }
        } catch {
            connectionError = error.localizedDescription
        }
    }
}
