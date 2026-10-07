import Foundation

private struct StubReply {
    let status: Int
    let body: Data
}

private final class StubRouter: @unchecked Sendable {
    private let lock = NSLock()
    private let postStarted = DispatchSemaphore(value: 0)
    private let postRelease = DispatchSemaphore(value: 0)
    private var blockNextPost = false
    private var postStatus = "completed"
    private var postIDs: [String] = []
    private var receiptStatuses: [String: String] = [:]
    private var missingReceipts = Set<String>()
    private var receiptLookups: [String] = []

    func configurePost(status: String) {
        lock.lock()
        postStatus = status
        lock.unlock()
    }

    func blockNextSubmission() {
        lock.lock()
        blockNextPost = true
        lock.unlock()
    }

    func waitForSubmission() {
        postStarted.wait()
    }

    func releaseSubmission() {
        postRelease.signal()
    }

    var submittedIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return postIDs
    }

    var lookedUpIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return receiptLookups
    }

    func configureReceipt(_ commandID: String, status: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let status {
            receiptStatuses[commandID] = status
            missingReceipts.remove(commandID)
        } else {
            missingReceipts.insert(commandID)
        }
    }

    func response(to request: URLRequest) -> StubReply {
        let path = request.url?.path ?? ""
        if path == "/api/v1/snapshot" {
            return jsonReply(status: 200, body: snapshot())
        }
        if path.hasPrefix("/api/v1/sessions/") {
            return jsonReply(status: 200, body: sessionDetail())
        }
        if path == "/api/v1/commands", request.httpMethod == "POST" {
            guard let body = bodyData(request),
                  let command = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let commandID = command["command_id"] as? String else {
                return jsonReply(status: 400, body: ["error": "missing command id"])
            }
            lock.lock()
            postIDs.append(commandID)
            let status = postStatus
            receiptStatuses[commandID] = status
            let shouldBlock = blockNextPost
            blockNextPost = false
            lock.unlock()
            if shouldBlock {
                postStarted.signal()
                postRelease.wait()
            }
            return jsonReply(status: 200, body: receipt(commandID, status: status))
        }
        if path.hasPrefix("/api/v1/commands/") {
            let commandID = String(path.dropFirst("/api/v1/commands/".count))
            lock.lock()
            receiptLookups.append(commandID)
            let missing = missingReceipts.contains(commandID)
            let status = receiptStatuses[commandID] ?? "accepted"
            lock.unlock()
            if missing {
                return jsonReply(status: 404, body: ["error": "receipt not found"])
            }
            return jsonReply(status: 200, body: receipt(commandID, status: status))
        }
        return jsonReply(status: 404, body: ["error": "route not found"])
    }

    private func snapshot() -> [String: Any] {
        [
            "protocol_version": 1,
            "server_id": "test-server",
            "identity_key": "test-identity",
            "workspace_id": "test-workspace",
            "auth_revision": 1,
            "epoch": "test-epoch",
            "revision": 1,
            "cursor": "test-epoch:1",
            "auth": [
                "state": "signed_out",
                "account": NSNull(),
                "plan_usage": "disabled",
                "scopes": [String](),
                "models": [[String: String]](),
                "selected_model": NSNull(),
            ],
            "projection": [
                "sessions": [["id": "session-1", "title": "Test session", "status": "ready"]],
            ],
        ]
    }

    private func sessionDetail() -> [String: Any] {
        [
            "protocol_version": 1,
            "identity_key": "test-identity",
            "auth_revision": 1,
            "workspace_id": "test-workspace",
            "epoch": "test-epoch",
            "revision": 1,
            "cursor": "test-epoch:1",
            "projection": ["session": ["id": "session-1", "messages": [[String: Any]]()]],
        ]
    }

    private func receipt(_ commandID: String, status: String) -> [String: Any] {
        [
            "protocol_version": 1,
            "workspace_id": "test-workspace",
            "command_id": commandID,
            "payload_fingerprint": "test-fingerprint-\(commandID)",
            "status": status,
            "accepted_revision": 1,
        ]
    }

    private func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            body.append(buffer, count: count)
        }
        return body
    }

    private func jsonReply(status: Int, body: [String: Any]) -> StubReply {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        return StubReply(status: status, body: data)
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var router: StubRouter?

    static func install(_ router: StubRouter) {
        lock.lock()
        self.router = router
        lock.unlock()
    }

    private static func currentRouter() -> StubRouter? {
        lock.lock()
        defer { lock.unlock() }
        return router
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "native.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let reply = Self.currentRouter()?.response(to: request),
              let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
private struct DshClientModelTests {
    static func main() async throws {
        try await rejectsA2xxRejectionWithoutClearingDraft()
        try await persistsBeforeAcceptAndSerializesTapsWithoutDeletingNewTyping()
        try await restoresAndReconcilesAcceptedUnknownAndExpiredReceipts()
        print("iOS client model/C bridge tests passed (3 scenarios).")
    }

    private static func rejectsA2xxRejectionWithoutClearingDraft() async throws {
        let router = StubRouter()
        router.configurePost(status: "rejected")
        let defaults = freshDefaults()
        let model = makeModel(router: router, defaults: defaults)
        await connectToSession(model)
        model.setDraft("keep this draft")
        await model.sendDraft()

        try expect(model.draft == "keep this draft", "a rejected 2xx receipt must preserve the draft")
        try expect(model.commandNotice?.contains("rejected") == true, "the rejection needs a visible outcome")
        try expect(router.submittedIDs.count == 1, "the rejected command should be submitted once")
        model.suspend()
    }

    private static func persistsBeforeAcceptAndSerializesTapsWithoutDeletingNewTyping() async throws {
        let router = StubRouter()
        router.configurePost(status: "completed")
        router.blockNextSubmission()
        let defaults = freshDefaults()
        let model = makeModel(router: router, defaults: defaults)
        await connectToSession(model)
        model.setDraft("first prompt")

        let send = Task { await model.sendDraft() }
        await Task.detached { router.waitForSubmission() }.value

        let pending = persistedCommands(in: defaults)
        let scopeKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("dsh.client.preferences.v1.") }
        try expect(pending.count == 1, "pending command metadata must be durable before the POST can return; found \(pending), keys \(scopeKeys)")
        try expect(pending[0]["status"] as? String == "submitted", "the saved command must be marked submitted")

        model.setDraft("new typing while request waits")
        let duplicateTap = Task { await model.sendDraft() }
        await duplicateTap.value
        try expect(router.submittedIDs.count == 1, "rapid taps must share one in-flight mutation")

        router.releaseSubmission()
        await send.value
        try expect(router.submittedIDs.count == 1, "a duplicate tap must not create another command ID")
        try expect(model.draft == "new typing while request waits", "the completed send must not erase later typing")
        model.suspend()
    }

    private static func restoresAndReconcilesAcceptedUnknownAndExpiredReceipts() async throws {
        let router = StubRouter()
        router.configurePost(status: "accepted")
        let defaults = freshDefaults()
        let firstModel = makeModel(router: router, defaults: defaults)
        await connectToSession(firstModel)
        for prompt in ["accepted", "expired", "unknown"] {
            firstModel.setDraft(prompt)
            await firstModel.sendDraft()
        }
        let ids = router.submittedIDs
        try expect(ids.count == 3, "the setup should create three distinct command receipts")
        router.configureReceipt(ids[0], status: "accepted")
        router.configureReceipt(ids[1], status: "expired")
        router.configureReceipt(ids[2], status: nil)
        firstModel.suspend()
        let beforeRestart = persistedCommands(in: defaults)
        try expect(beforeRestart.count == 3, "pending receipts must survive the first model lifecycle; found \(beforeRestart)")

        let secondModel = makeModel(router: router, defaults: defaults)
        await secondModel.connect()
        try expect(router.submittedIDs.count == 3, "restored commands must be looked up, never replayed")
        try expect(Set(router.lookedUpIDs).isSuperset(of: ids), "connect must query every restored command ID")
        try expect(secondModel.commandNotice?.contains("no confirmed receipt") == true, "missing receipts need a visible unconfirmed state")

        let remaining = persistedCommands(in: defaults)
        let pairs: [(String, String)] = remaining.compactMap { item in
            guard let id = item["command_id"] as? String else { return nil }
            return (id, item["status"] as? String ?? "")
        }
        let byID = Dictionary(uniqueKeysWithValues: pairs)
        try expect(byID[ids[0]] == "accepted", "accepted receipts should remain pending; ids=\(ids) saved=\(byID)")
        try expect(byID[ids[2]] == "unconfirmed", "a missing receipt should stay explicitly unconfirmed; saved=\(byID)")
        try expect(byID[ids[1]] == nil, "expired receipts should be removed from pending state; saved=\(byID)")
        secondModel.suspend()
    }

    private static func connectToSession(_ model: DshClientModel) async {
        await model.connect()
        await model.selectSession("session-1")
        precondition(model.connection == "synced", "test host should synchronize the model")
    }

    private static func makeModel(router: StubRouter, defaults: UserDefaults) -> DshClientModel {
        StubURLProtocol.install(router)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let model = DshClientModel(urlSession: session, defaults: defaults, eventStreamEnabled: false)
        model.hostURL = "https://native.test"
        return model
    }

    private static func freshDefaults() -> UserDefaults {
        let name = "dsh-client-model-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func persistedCommands(in defaults: UserDefaults) -> [[String: Any]] {
        let prefix = "dsh.client.preferences.v1."
        guard let entry = defaults.dictionaryRepresentation().first(where: { $0.key.hasPrefix(prefix) && $0.key != prefix }),
              let data = entry.value as? Data,
              let preferences = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return preferences["commands"] as? [[String: Any]] ?? []
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(description: message) }
    }
}
