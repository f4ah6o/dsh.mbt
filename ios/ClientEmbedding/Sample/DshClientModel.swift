import Combine
import Foundation
import Security

struct ClientSessionRow: Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
}

struct ClientMessageRow: Identifiable {
    let id: Int
    let role: String
    let content: String
}

@MainActor
final class DshClientModel: ObservableObject {
    @Published var hostURL = UserDefaults.standard.string(forKey: "dsh.native.host") ?? "" {
        didSet { UserDefaults.standard.set(hostURL, forKey: "dsh.native.host") }
    }
    @Published var connection = "offline"
    @Published var authSummary = "Not connected"
    @Published var sessions: [ClientSessionRow] = []
    @Published var selectedSessionID: String?
    @Published var messages: [ClientMessageRow] = []
    @Published var pendingApproval: [String: Any]?
    @Published var draft = ""
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let handle: DshMoonBitClientHandle
    private var streamTask: Task<Void, Never>?
    private var preferenceScope: String?

    init() {
        _ = dsh_moonbit_runtime_start()
        handle = dsh_moonbit_client_create()
        refreshFromClient()
    }

    deinit {
        streamTask?.cancel()
        _ = dsh_moonbit_client_dispose(handle)
    }

    func connect() async {
        guard !isBusy else { return }
        guard let baseURL = validatedBaseURL() else {
            errorMessage = "Enter the HTTPS URL of the host on your tailnet."
            return
        }
        isBusy = true
        errorMessage = nil
        _ = dsh_moonbit_client_begin_connect(handle)
        refreshFromClient()
        do {
            try await loadSnapshot(baseURL: baseURL)
            streamTask?.cancel()
            streamTask = Task { [weak self] in
                await self?.maintainEventStream(baseURL: baseURL)
            }
        } catch {
            _ = dsh_moonbit_client_connection_failed(handle)
            errorMessage = error.localizedDescription
            refreshFromClient()
        }
        isBusy = false
    }

    func resumeIfConfigured() async {
        guard !hostURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if connection == "synced", streamTask != nil { return }
        await connect()
    }

    func suspend() {
        streamTask?.cancel()
        streamTask = nil
        guard connection != "offline" else { return }
        _ = dsh_moonbit_client_connection_failed(handle)
        persistPreferences()
        refreshFromClient()
    }

    func selectSession(_ id: String) async {
        _ = callString(Data(id.utf8)) { pointer, count in
            dsh_moonbit_client_set_selection(handle, pointer, count)
        }
        selectedSessionID = id
        persistPreferences()
        guard let baseURL = validatedBaseURL() else { return }
        do {
            let data = try await request(baseURL: baseURL, path: "/api/v1/sessions/\(id)")
            _ = callString(data) { pointer, count in
                dsh_moonbit_client_accept_session(handle, pointer, count)
            }
            refreshFromClient()
            restartEventStream()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDraft(_ value: String) {
        draft = value
        _ = callString(Data(value.utf8)) { pointer, count in
            dsh_moonbit_client_set_draft(handle, pointer, count)
        }
        persistPreferences()
    }

    func createSession() async {
        do {
            let sessionID = UUID().uuidString.lowercased()
            _ = try await sendCommand(
                operation: "session_create",
                sessionID: nil,
                input: ["id": sessionID, "title": "New session"],
                approvalRevision: -1
            )
            await connect()
            await selectSession(sessionID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendDraft() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        do {
            var sessionID = selectedSessionID
            if sessionID == nil {
                sessionID = UUID().uuidString.lowercased()
                _ = try await sendCommand(
                    operation: "session_create",
                    sessionID: nil,
                    input: ["id": sessionID!, "title": String(prompt.prefix(52))],
                    approvalRevision: -1
                )
                await connect()
                await selectSession(sessionID!)
            }
            _ = try await sendCommand(
                operation: "session_send",
                sessionID: sessionID,
                input: ["prompt": prompt],
                approvalRevision: -1
            )
            setDraft("")
            guard let baseURL = validatedBaseURL() else { throw ClientError.invalidHost }
            try await loadSnapshot(baseURL: baseURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decideApproval(approved: Bool) async {
        guard let pendingApproval,
              let callID = pendingApproval["call_id"] as? String,
              let sessionID = selectedSessionID,
              let row = currentSummary(for: sessionID),
              let revision = row["approval_revision"] as? Int else {
            errorMessage = "This approval changed. Refresh the workspace before deciding."
            return
        }
        do {
            _ = try await sendCommand(
                operation: "tool_approve",
                sessionID: sessionID,
                input: ["call_id": callID, "approved": approved],
                approvalRevision: revision
            )
            if let baseURL = validatedBaseURL() { try await loadSnapshot(baseURL: baseURL) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let baseURL = validatedBaseURL() else {
            errorMessage = "Enter the HTTPS URL of the host on your tailnet."
            return
        }
        do {
            try await loadSnapshot(baseURL: baseURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendCommand(
        operation: String,
        sessionID: String?,
        input: [String: Any],
        approvalRevision: Int
    ) async throws -> [String: Any] {
        guard let baseURL = validatedBaseURL() else { throw ClientError.invalidHost }
        let entropy = try secureEntropyHex()
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        guard let commandID = withDataSlices([Data(timestamp.utf8), Data(entropy.utf8)], { slices -> UnsafeMutablePointer<CChar>? in
            guard slices.count == 2 else { return nil }
            return dsh_moonbit_new_command_id(
                slices[0].baseAddress, slices[0].count,
                slices[1].baseAddress, slices[1].count
            )
        }).flatMap(bridgeString) else { throw ClientError.commandIDUnavailable }

        let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let inputString = String(decoding: inputData, as: UTF8.self)
        let commandInput = [
            Data(commandID.utf8), Data(operation.utf8), Data((sessionID ?? "").utf8), Data(inputString.utf8),
        ]
        guard let preparedRaw = withDataSlices(commandInput, { slices -> UnsafeMutablePointer<CChar>? in
            guard slices.count == 4 else { return nil }
            return dsh_moonbit_client_queue_command(
                handle,
                slices[0].baseAddress, slices[0].count,
                slices[1].baseAddress, slices[1].count,
                slices[2].baseAddress, slices[2].count,
                slices[3].baseAddress, slices[3].count,
                Int32(approvalRevision)
            )
        }).flatMap(bridgeString),
        let prepared = parseObject(preparedRaw),
        prepared["ok"] as? Bool == true,
        let command = prepared["command"] as? [String: Any] else {
            throw ClientError.commandRejected
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: command, options: [.sortedKeys]) else {
            throw ClientError.commandRejected
        }
        _ = callString(Data(commandID.utf8)) { pointer, count in
            dsh_moonbit_client_mark_command_sent(handle, pointer, count)
        }
        let receiptData: Data
        do {
            receiptData = try await request(
                baseURL: baseURL,
                path: "/api/v1/commands",
                method: "POST",
                body: encoded
            )
        } catch {
            _ = callString(Data(commandID.utf8)) { pointer, count in
                dsh_moonbit_client_mark_command_uncertain(handle, pointer, count)
            }
            refreshFromClient()
            if let receipt = try? await request(baseURL: baseURL, path: "/api/v1/commands/\(commandID)") {
                _ = callString(receipt) { pointer, count in
                    dsh_moonbit_client_apply_receipt(handle, pointer, count)
                }
                refreshFromClient()
            }
            throw error
        }
        guard let appliedRaw = callString(receiptData, { pointer, count in
            dsh_moonbit_client_apply_receipt(handle, pointer, count)
        }), let applied = parseObject(appliedRaw), applied["ok"] as? Bool == true else {
            throw ClientError.receiptRejected
        }
        refreshFromClient()
        return parseObject(String(decoding: receiptData, as: UTF8.self)) ?? [:]
    }

    private func loadSnapshot(baseURL: URL) async throws {
        let raw = try await request(baseURL: baseURL, path: "/api/v1/snapshot")
        guard let resultRaw = callString(raw, { pointer, count in
            dsh_moonbit_client_accept_snapshot(handle, pointer, count)
        }),
        let result = parseObject(resultRaw), result["ok"] as? Bool == true else {
            throw ClientError.snapshotRejected
        }
        restorePreferencesForCurrentScope()
        refreshFromClient()
        if let id = selectedSessionID {
            let detail = try await request(baseURL: baseURL, path: "/api/v1/sessions/\(id)")
            _ = callString(detail) { pointer, count in
                dsh_moonbit_client_accept_session(handle, pointer, count)
            }
            refreshFromClient()
        }
    }

    private func maintainEventStream(baseURL: URL) async {
        while !Task.isCancelled {
            do {
                let wantsSnapshot = try await readProjectionStream(baseURL: baseURL)
                if wantsSnapshot { try await loadSnapshot(baseURL: baseURL) }
            } catch is CancellationError {
                return
            } catch {
                _ = dsh_moonbit_client_connection_failed(handle)
                refreshFromClient()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func readProjectionStream(baseURL: URL) async throws -> Bool {
        guard let state = clientState(),
              let cursor = state["cursor"] as? String, !cursor.isEmpty else {
            throw ClientError.snapshotRejected
        }
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/events"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "cursor", value: cursor)]
        if let selectedSessionID { query.append(URLQueryItem(name: "session_id", value: selectedSessionID)) }
        components.queryItems = query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ClientError.serverUnavailable
        }
        _ = dsh_moonbit_client_connection_restored(handle)
        refreshFromClient()

        var dataLines: [String] = []
        var eventID = ""
        var eventName = "message"
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if line.isEmpty {
                if !dataLines.isEmpty {
                    let raw = Data(dataLines.joined(separator: "\n").utf8)
                    guard let resultRaw = withDataSlices([raw, Data(eventID.utf8)], { slices -> UnsafeMutablePointer<CChar>? in
                        guard slices.count == 2 else { return nil }
                        return dsh_moonbit_client_accept_event(
                            handle,
                            slices[0].baseAddress, slices[0].count,
                            slices[1].baseAddress, slices[1].count
                        )
                    }).flatMap(bridgeString), let result = parseObject(resultRaw) else {
                        throw ClientError.eventRejected
                    }
                    refreshFromClient()
                    let status = result["status"] as? String ?? ""
                    dataLines.removeAll(keepingCapacity: true)
                    eventID = ""
                    let needsSnapshot = eventName == "resync" || [
                        "gap", "wrong_workspace", "identity_changed", "epoch_changed",
                        "requires_snapshot", "cursor_mismatch",
                    ].contains(status)
                    eventName = "message"
                    if needsSnapshot { return true }
                    continue
                }
                eventID = ""
                eventName = "message"
                continue
            }
            if line.hasPrefix(":") { continue }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let field = String(line[..<separator])
            var value = String(line[line.index(after: separator)...])
            if value.first == " " { value.removeFirst() }
            switch field {
            case "data": dataLines.append(value)
            case "id": eventID = value
            case "event": eventName = value
            default: break
            }
        }
        return false
    }

    private func request(
        baseURL: URL,
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        var request = URLRequest(
            url: baseURL.appending(path: path),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(detail.isEmpty ? "The workspace host returned an error." : detail)
        }
        return data
    }

    private func validatedBaseURL() -> URL? {
        guard let url = URL(string: hostURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    private func restorePreferencesForCurrentScope() {
        guard let current = clientState(), let scope = current["scope_key"] as? String,
              scope != preferenceScope else { return }
        let previousScope = preferenceScope
        preferenceScope = scope
        if let previousScope {
            UserDefaults.standard.removeObject(forKey: "dsh.client.preferences.v1.\(previousScope)")
        }
        guard let data = UserDefaults.standard.data(forKey: "dsh.client.preferences.v1.\(scope)") else { return }
        _ = callString(data) { pointer, count in
            dsh_moonbit_client_restore_preferences(handle, pointer, count)
        }
    }

    private func persistPreferences() {
        guard let raw = bridgeString(dsh_moonbit_client_persisted_state_json(handle)),
              let preferences = parseObject(raw),
              let scope = preferences["scope_key"] as? String,
              let data = raw.data(using: .utf8) else { return }
        UserDefaults.standard.set(data, forKey: "dsh.client.preferences.v1.\(scope)")
    }

    private func refreshFromClient() {
        guard let state = clientState() else { return }
        connection = state["connection"] as? String ?? "offline"
        draft = state["draft"] as? String ?? draft
        selectedSessionID = state["selected_session"] as? String
        if let auth = state["auth"] as? [String: Any] {
            let account = (auth["account"] as? [String: Any])?["email"] as? String
            let model = auth["selected_model"] as? String
            authSummary = [auth["state"] as? String, account, model]
                .compactMap { $0 }.joined(separator: " · ")
        }
        let projection = state["projection"] as? [String: Any]
        let sessionRows = projection?["sessions"] as? [[String: Any]] ?? []
        sessions = sessionRows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return ClientSessionRow(
                id: id,
                title: row["title"] as? String ?? id,
                status: row["status"] as? String ?? "unknown"
            )
        }
        let selected = state["selected_session_projection"] as? [String: Any]
        let rawMessages = selected?["messages"] as? [[String: Any]] ?? []
        var renderedMessages: [ClientMessageRow] = []
        for item in rawMessages {
            let role = item["role"] as? String ?? "message"
            let content = item["content"] as? String ?? ""
            if !content.isEmpty {
                renderedMessages.append(ClientMessageRow(
                    id: renderedMessages.count,
                    role: role,
                    content: content
                ))
            }
            for call in item["tool_calls"] as? [[String: Any]] ?? [] {
                let name = call["name"] as? String ?? "tool"
                let isCustom = call["kind"] as? String == "custom"
                let callContent: String
                if isCustom {
                    // Custom-call input is opaque provider text, not JSON.
                    callContent = call["arguments"] as? String ?? ""
                } else if let arguments = call["arguments"],
                          let data = try? JSONSerialization.data(
                            withJSONObject: arguments,
                            options: [.prettyPrinted, .sortedKeys]
                          ) {
                    callContent = String(data: data, encoding: .utf8) ?? ""
                } else {
                    callContent = ""
                }
                renderedMessages.append(ClientMessageRow(
                    id: renderedMessages.count,
                    role: isCustom ? "Custom call · \(name)" : "Tool request · \(name)",
                    content: callContent
                ))
            }
        }
        messages = renderedMessages
        pendingApproval = selected?["pending_approval"] as? [String: Any]
        persistPreferences()
    }

    private func currentSummary(for id: String) -> [String: Any]? {
        let state = clientState()
        let projection = state?["projection"] as? [String: Any]
        let rows = projection?["sessions"] as? [[String: Any]] ?? []
        return rows.first { ($0["id"] as? String) == id }
    }

    private func clientState() -> [String: Any]? {
        guard let raw = bridgeString(dsh_moonbit_client_state_json(handle)) else { return nil }
        return parseObject(raw)
    }

    private func restartEventStream() {
        guard let baseURL = validatedBaseURL() else { return }
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.maintainEventStream(baseURL: baseURL)
        }
    }

    private func secureEntropyHex() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw ClientError.randomUnavailable }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func callString(
        _ data: Data,
        _ call: (UnsafePointer<UInt8>?, Int) -> UnsafeMutablePointer<CChar>?
    ) -> String? {
        data.withUnsafeBytes { raw in
            guard let value = call(raw.bindMemory(to: UInt8.self).baseAddress, raw.count) else { return nil }
            defer { dsh_moonbit_free_string(value) }
            return String(cString: value)
        }
    }

    private func withDataSlices<T>(
        _ values: [Data],
        _ body: ([UnsafeBufferPointer<UInt8>]) -> T
    ) -> T {
        func descend(_ index: Int, _ slices: [UnsafeBufferPointer<UInt8>]) -> T {
            guard index < values.count else { return body(slices) }
            return values[index].withUnsafeBytes { raw in
                descend(index + 1, slices + [raw.bindMemory(to: UInt8.self)])
            }
        }
        return descend(0, [])
    }

    private func bridgeString(_ value: UnsafeMutablePointer<CChar>?) -> String? {
        guard let value else { return nil }
        defer { dsh_moonbit_free_string(value) }
        return String(cString: value)
    }

    private func parseObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private enum ClientError: LocalizedError {
        case invalidHost
        case randomUnavailable
        case commandIDUnavailable
        case commandRejected
        case receiptRejected
        case snapshotRejected
        case eventRejected
        case serverUnavailable
        case http(String)

        var errorDescription: String? {
            switch self {
            case .invalidHost: return "Enter the HTTPS URL of the host on your tailnet."
            case .randomUnavailable: return "Secure command ID generation failed."
            case .commandIDUnavailable: return "The shared client could not create a command ID."
            case .commandRejected: return "The shared client rejected this command. Refresh before retrying."
            case .receiptRejected: return "The workspace receipt did not match the queued command. Refresh before retrying."
            case .snapshotRejected: return "The workspace snapshot could not be synchronized."
            case .eventRejected: return "The workspace event could not be applied. Reconnect to resync."
            case .serverUnavailable: return "The workspace host did not accept the live event connection."
            case .http(let detail): return detail
            }
        }
    }
}
