import Foundation

private struct StubReply {
    let status: Int
    let body: Data
    var keepOpen = false
}

private final class StubRouter: @unchecked Sendable {
    private let lock = NSLock()
    private let postStarted = DispatchSemaphore(value: 0)
    private let postRelease = DispatchSemaphore(value: 0)
    private let blockedRequestStarted = DispatchSemaphore(value: 0)
    private let blockedRequestRelease = DispatchSemaphore(value: 0)
    private let openEventStreamStarted = DispatchSemaphore(value: 0)
    private let eventErrorDelivered = DispatchSemaphore(value: 0)
    private var blockNextPost = false
    private var blockedPath: String?
    private var postStatus = "completed"
    private var identityKey = "test-identity"
    private var postIDs: [String] = []
    private var postOperations: [String] = []
    private var receiptStatuses: [String: String] = [:]
    private var missingReceipts = Set<String>()
    private var receiptLookups: [String] = []
    private var eventStreamRequests = 0

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

    func blockNextRequest(path: String) {
        lock.lock()
        blockedPath = path
        lock.unlock()
    }

    func configureIdentity(_ identityKey: String) {
        lock.lock()
        self.identityKey = identityKey
        lock.unlock()
    }

    func waitForBlockedRequest() -> Bool {
        blockedRequestStarted.wait(timeout: .now() + .seconds(10)) == .success
    }

    func releaseBlockedRequest() {
        blockedRequestRelease.signal()
    }

    func waitForOpenEventStream() -> Bool {
        openEventStreamStarted.wait(timeout: .now() + .seconds(10)) == .success
    }

    func signalOpenEventStream() {
        openEventStreamStarted.signal()
    }

    func waitForEventErrorDelivery() -> Bool {
        eventErrorDelivered.wait(timeout: .now() + .seconds(10)) == .success
    }

    func signalEventErrorDelivery() {
        eventErrorDelivered.signal()
    }

    var submittedIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return postIDs
    }

    var submittedOperations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return postOperations
    }

    var lookedUpIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return receiptLookups
    }

    var eventRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return eventStreamRequests
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
            let reply = jsonReply(status: 200, body: snapshot())
            waitIfBlocked(path)
            return reply
        }
        if path.hasPrefix("/api/v1/sessions/") {
            let id = String(path.dropFirst("/api/v1/sessions/".count))
            let reply = jsonReply(status: 200, body: sessionDetail(id))
            waitIfBlocked(path)
            return reply
        }
        if path == "/api/v1/events" {
            lock.lock()
            eventStreamRequests += 1
            let requestNumber = eventStreamRequests
            lock.unlock()
            if requestNumber == 1 {
                waitIfBlocked(path)
                return jsonReply(status: 503, body: ["error": "delayed event stream failure"])
            }
            return StubReply(status: 200, body: Data(": keepalive\n\n".utf8), keepOpen: true)
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
            postOperations.append(command["operation"] as? String ?? "")
            let shouldBlock = blockNextPost
            blockNextPost = false
            lock.unlock()
            if shouldBlock {
                postStarted.signal()
                postRelease.wait()
            }
            waitIfBlocked(path)
            return jsonReply(status: 200, body: receipt(commandID, status: status))
        }
        if path.hasPrefix("/api/v1/commands/") {
            let commandID = String(path.dropFirst("/api/v1/commands/".count))
            waitIfBlocked(path)
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
        let identityKey = currentIdentityKey()
        return [
            "protocol_version": 1,
            "server_id": "test-server",
            "identity_key": identityKey,
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
                "sessions": [[
                    "id": "session-1",
                    "title": "Session for \(identityKey)",
                    "status": "ready",
                ]],
            ],
        ]
    }

    private func sessionDetail(_ id: String) -> [String: Any] {
        [
            "protocol_version": 1,
            "identity_key": currentIdentityKey(),
            "auth_revision": 1,
            "workspace_id": "test-workspace",
            "epoch": "test-epoch",
            "revision": 1,
            "cursor": "test-epoch:1",
            "projection": ["session": [
                "id": id,
                "messages": [["role": "assistant", "content": "response for \(id)"]],
            ]],
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

    private func waitIfBlocked(_ path: String) {
        lock.lock()
        let matchesPrefix: Bool
        if let blockedPath {
            matchesPrefix = blockedPath.hasSuffix("/") && path.hasPrefix(blockedPath)
        } else {
            matchesPrefix = false
        }
        let shouldBlock = blockedPath == path || matchesPrefix
        if shouldBlock { blockedPath = nil }
        lock.unlock()
        guard shouldBlock else { return }
        blockedRequestStarted.signal()
        blockedRequestRelease.wait()
    }

    private func currentIdentityKey() -> String {
        lock.lock()
        defer { lock.unlock() }
        return identityKey
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
        request.url?.host?.hasSuffix("native.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let request = self.request
        let client = self.client
        DispatchQueue.global(qos: .userInitiated).async {
            let router = Self.currentRouter()
            guard let url = request.url, let reply = router?.response(to: request),
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: reply.status,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": url.path == "/api/v1/events" ? "text/event-stream" : "application/json"
                    ]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            if reply.keepOpen {
                router?.signalOpenEventStream()
            } else {
                client?.urlProtocolDidFinishLoading(self)
                if url.path == "/api/v1/events" && reply.status >= 500 {
                    router?.signalEventErrorDelivery()
                }
            }
        }
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
        try await suspensionDiscardsLateSnapshotAndDoesNotStartStream()
        try await hostChangeDiscardsLateSnapshotAndSessionResponse()
        try await selectionIntentWinsOverDelayedSessionResponse()
        try await suspendedSubmissionIsReconciledWithoutReplay()
        try await staleReceiptReadCannotCrossHostChange()
        try await delayedSubmissionBecomesUncertainAfterHostChange()
        try await followLatestPreferencePersists()
        try await staleEventStreamFailureCannotClearReplacementStream()
        try await followLatestChangesOnlyFromUserScrolling()
        try await scopeChangeDuringAutoCreateAbortsFollowupSend()
        print("iOS client model/C bridge tests passed (13 scenarios).")
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

    private static func suspensionDiscardsLateSnapshotAndDoesNotStartStream() async throws {
        let router = StubRouter()
        router.blockNextRequest(path: "/api/v1/snapshot")
        let model = makeModel(
            router: router,
            defaults: freshDefaults(),
            eventStreamEnabled: true
        )
        model.hostURL = "https://native.test"
        let connect = Task { await model.connect() }
        try await waitForBlockedRequest(router)

        model.suspend()
        router.releaseBlockedRequest()
        await connect.value

        try expect(model.connection == "offline", "a snapshot returned after suspension must not restore connectivity")
        try expect(model.sessions.isEmpty, "a late snapshot must not repopulate the suspended client")
        try expect(router.eventRequestCount == 0, "a stale connect must not start an event stream")
    }

    private static func hostChangeDiscardsLateSnapshotAndSessionResponse() async throws {
        let router = StubRouter()
        router.blockNextRequest(path: "/api/v1/snapshot")
        let model = makeModel(router: router, defaults: freshDefaults())
        model.hostURL = "https://old.native.test"
        let oldConnect = Task { await model.connect() }
        try await waitForBlockedRequest(router)

        model.hostURL = "https://new.native.test"
        router.configureIdentity("new-identity")
        await model.connect()
        router.releaseBlockedRequest()
        await oldConnect.value
        try expect(model.sessions.first?.title == "Session for new-identity", "an old host snapshot must not replace the newly connected identity")
        try expect(model.connection == "synced", "the old connect completion must not mark the newer host offline")

        router.blockNextRequest(path: "/api/v1/sessions/session-1")
        let oldSession = Task { await model.selectSession("session-1") }
        try await waitForBlockedRequest(router)
        model.hostURL = "https://third.native.test"
        router.configureIdentity("third-identity")
        await model.connect()
        router.releaseBlockedRequest()
        await oldSession.value

        try expect(model.sessions.first?.title == "Session for third-identity", "a late session response must not cross an endpoint switch")
        try expect(model.messages.isEmpty, "a late session response must not restore the previous host transcript")
        try expect(model.selectedSessionID == nil, "a late session response must not restore the previous host selection")
    }

    private static func selectionIntentWinsOverDelayedSessionResponse() async throws {
        let router = StubRouter()
        let model = makeModel(router: router, defaults: freshDefaults())
        await model.connect()

        router.blockNextRequest(path: "/api/v1/sessions/session-1")
        let firstSelection = Task { await model.selectSession("session-1") }
        try await waitForBlockedRequest(router)
        await model.selectSession("session-2")
        router.releaseBlockedRequest()
        await firstSelection.value

        try expect(model.selectedSessionID == "session-2", "the delayed selection must not replace the user's newer choice")
        try expect(model.messages.contains(where: { $0.content == "response for session-2" }), "the newer session transcript should remain visible")
    }

    private static func suspendedSubmissionIsReconciledWithoutReplay() async throws {
        let router = StubRouter()
        router.configurePost(status: "accepted")
        let defaults = freshDefaults()
        let model = makeModel(router: router, defaults: defaults)
        await connectToSession(model)
        model.setDraft("keep receipt across suspension")
        router.blockNextRequest(path: "/api/v1/commands")

        let send = Task { await model.sendDraft() }
        try await waitForBlockedRequest(router)
        model.suspend()
        guard let commandID = router.submittedIDs.first else {
            throw TestFailure(description: "the suspended submission should have reached the host once")
        }
        router.configureReceipt(commandID, status: "completed")
        await model.resumeIfConfigured()
        router.releaseBlockedRequest()
        await send.value
        try await waitForReconnection(model, router: router, commandID: commandID)

        try expect(router.submittedIDs == [commandID], "resume must never replay the already submitted command")
        try expect(router.lookedUpIDs.contains(commandID), "resume must resolve the saved command by receipt ID")
        try expect(!persistedCommands(in: defaults).contains(where: { ($0["command_id"] as? String) == commandID }), "completed receipts should leave pending state")
        model.suspend()
    }

    private static func staleReceiptReadCannotCrossHostChange() async throws {
        let router = StubRouter()
        router.configurePost(status: "accepted")
        let defaults = freshDefaults()
        let firstModel = makeModel(router: router, defaults: defaults)
        await connectToSession(firstModel)
        firstModel.setDraft("receipt scoped to original host")
        await firstModel.sendDraft()
        guard let commandID = router.submittedIDs.first else {
            throw TestFailure(description: "the setup command should have been submitted")
        }
        firstModel.suspend()

        router.configureReceipt(commandID, status: "completed")
        router.blockNextRequest(path: "/api/v1/commands/\(commandID)")
        let secondModel = makeModel(router: router, defaults: defaults)
        let reconnect = Task { await secondModel.connect() }
        try await waitForBlockedRequest(router)

        secondModel.hostURL = "https://different.native.test"
        router.releaseBlockedRequest()
        await reconnect.value

        try expect(
            persistedCommands(in: defaults).contains(where: { ($0["command_id"] as? String) == commandID }),
            "a receipt response from the previous endpoint must not clear its outstanding ID"
        )
        try expect(secondModel.connection == "offline", "the old receipt completion must not restore the previous connection")
    }

    private static func delayedSubmissionBecomesUncertainAfterHostChange() async throws {
        let router = StubRouter()
        router.configurePost(status: "completed")
        let defaults = freshDefaults()
        let model = makeModel(router: router, defaults: defaults)
        await connectToSession(model)
        model.setDraft("preserve while the host changes")
        router.blockNextRequest(path: "/api/v1/commands")

        let send = Task { await model.sendDraft() }
        try await waitForBlockedRequest(router)
        model.hostURL = "https://other.native.test"
        router.releaseBlockedRequest()
        await send.value

        guard let commandID = router.submittedIDs.first else {
            throw TestFailure(description: "the delayed command should have reached the original host")
        }
        let pending = persistedCommands(in: defaults)
        try expect(model.draft == "preserve while the host changes", "a stale POST response must not clear the user's draft")
        try expect(
            pending.contains(where: {
                ($0["command_id"] as? String) == commandID && ($0["status"] as? String) == "uncertain"
            }),
            "a response arriving after an endpoint switch must leave the submitted ID uncertain"
        )
        try expect(router.lookedUpIDs.isEmpty, "a stale POST must not query a receipt through the changed endpoint")

        model.hostURL = "https://native.test"
        await model.resumeIfConfigured()
        try expect(router.submittedIDs == [commandID], "reconnect must not replay the uncertain command")
        try expect(router.lookedUpIDs.contains(commandID), "reconnect should resolve the uncertain command by receipt ID")
        model.suspend()
    }

    private static func followLatestPreferencePersists() async throws {
        let router = StubRouter()
        let defaults = freshDefaults()
        let firstModel = makeModel(router: router, defaults: defaults)
        await firstModel.connect()
        firstModel.setFollowLatest(false)
        try expect(!firstModel.followLatest, "the shared client should expose the user's reading position preference")
        firstModel.suspend()

        let secondModel = makeModel(router: router, defaults: defaults)
        await secondModel.connect()
        try expect(!secondModel.followLatest, "the reading position preference should restore after reconnect")
        secondModel.setFollowLatest(true)
        try expect(secondModel.followLatest, "following the newest message should be user-controllable")
        secondModel.suspend()
    }

    private static func staleEventStreamFailureCannotClearReplacementStream() async throws {
        let router = StubRouter()
        router.blockNextRequest(path: "/api/v1/events")
        let model = makeModel(router: router, defaults: freshDefaults(), eventStreamEnabled: true)
        await model.connect()
        try await waitForBlockedRequest(router)

        await model.selectSession("session-1")
        let replacementOpened = await Task.detached { router.waitForOpenEventStream() }.value
        try expect(replacementOpened, "selecting a session should open a replacement event stream")

        router.releaseBlockedRequest()
        let oldFailureDelivered = await Task.detached { router.waitForEventErrorDelivery() }.value
        try expect(oldFailureDelivered, "the canceled stream fixture should deliver its delayed failure")
        try await Task.sleep(for: .milliseconds(50))

        try expect(router.eventRequestCount == 2, "the selected session should own the replacement stream")
        try expect(model.connection == "synced", "a canceled stream failure must not clear the replacement connection")
        model.suspend()
    }

    private static func followLatestChangesOnlyFromUserScrolling() async throws {
        let model = makeModel(router: StubRouter(), defaults: freshDefaults())
        model.setFollowLatest(true)

        model.updateFollowLatestFromUserScroll(isNearLatest: false, isUserScrolling: false)
        try expect(model.followLatest, "content growth must not disable follow-latest without user scrolling")

        model.updateFollowLatestFromUserScroll(isNearLatest: false, isUserScrolling: true)
        try expect(!model.followLatest, "scrolling away from the latest message should preserve reading position")

        model.updateFollowLatestFromUserScroll(isNearLatest: true, isUserScrolling: false)
        try expect(!model.followLatest, "layout changes must not re-enable follow-latest after scrolling away")

        model.updateFollowLatestFromUserScroll(isNearLatest: true, isUserScrolling: true)
        try expect(model.followLatest, "scrolling back to the bottom should resume follow-latest")
        model.suspend()
    }

    private static func scopeChangeDuringAutoCreateAbortsFollowupSend() async throws {
        let router = StubRouter()
        router.blockNextRequest(path: "/api/v1/sessions/")
        let model = makeModel(router: router, defaults: freshDefaults())
        await model.connect()
        model.setDraft("do not submit into the next identity")
        let send = Task { await model.sendDraft() }
        try await waitForBlockedRequest(router)

        router.configureIdentity("new-identity")
        let snapshotRequest = URLRequest(url: URL(string: "https://native.test/api/v1/snapshot")!)
        let changedScopeSnapshot = router.response(to: snapshotRequest).body
        try injectScopeChangeThroughSharedClient(model, snapshot: changedScopeSnapshot)
        router.releaseBlockedRequest()
        await send.value

        try expect(router.submittedOperations == ["session_create"], "an auto-create flow must not send its draft into a changed account scope")
        model.suspend()
    }

    private static func connectToSession(_ model: DshClientModel) async {
        await model.connect()
        await model.selectSession("session-1")
        precondition(model.connection == "synced", "test host should synchronize the model")
    }

    private static func makeModel(
        router: StubRouter,
        defaults: UserDefaults,
        eventStreamEnabled: Bool = false
    ) -> DshClientModel {
        StubURLProtocol.install(router)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let model = DshClientModel(
            urlSession: session,
            defaults: defaults,
            eventStreamEnabled: eventStreamEnabled
        )
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

    private static func waitForBlockedRequest(_ router: StubRouter) async throws {
        let reached = await Task.detached { router.waitForBlockedRequest() }.value
        try expect(reached, "the URL fixture did not reach its delayed response within 10 seconds")
    }

    private static func waitForReconnection(
        _ model: DshClientModel,
        router: StubRouter,
        commandID: String
    ) async throws {
        for _ in 0..<250 {
            if model.connection == "synced" && router.lookedUpIDs.contains(commandID) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw TestFailure(description: "deferred resume did not reconnect and look up the submitted command")
    }

    private static func injectScopeChangeThroughSharedClient(
        _ model: DshClientModel,
        snapshot: Data
    ) throws {
        guard let handle = Mirror(reflecting: model).children.first(where: { $0.label == "handle" })?.value
            as? DshMoonBitClientHandle else {
            throw TestFailure(description: "the test could not inspect the shared-client handle")
        }
        guard let resultRaw = snapshot.withUnsafeBytes({ buffer -> UnsafeMutablePointer<CChar>? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return dsh_moonbit_client_accept_snapshot(
                handle,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                buffer.count
            )
        }) else {
            throw TestFailure(description: "the shared client rejected the synthetic scope snapshot")
        }
        defer { dsh_moonbit_free_string(resultRaw) }
        let resultData = Data(String(cString: resultRaw).utf8)
        guard let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
              result["ok"] as? Bool == true,
              result["status"] as? String == "identity_changed" else {
            throw TestFailure(description: "the shared client did not accept the identity-change fixture")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(description: message) }
    }
}
