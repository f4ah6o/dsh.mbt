import SwiftUI

private struct ConversationScrollMetrics: Equatable {
    let contentOffsetY: CGFloat
    let isNearLatest: Bool
}

struct ClientHomeView: View {
    @ObservedObject var model: DshClientModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var userScrollInProgress = false
    @State private var isNearLatest = true

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                hostPicker
                HStack {
                    Label(model.connection.capitalized, systemImage: connectionIcon)
                        .font(.caption)
                        .accessibilityLabel("Connection \(model.connection)")
                    Spacer()
                    Button("Connect") { Task { await model.connect() } }
                        .disabled(model.isBusy)
                }
                .padding(.horizontal)
                Text(model.authSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                List(selection: $model.selectedSessionID) {
                    ForEach(model.sessions) { session in
                        Button {
                            Task { await model.selectSession(session.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title).lineLimit(2)
                                Text(session.status.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(session.id)
                        .accessibilityLabel("\(session.title), \(session.status)")
                    }
                }
                .listStyle(.plain)
                Button {
                    Task { await model.createSession() }
                } label: {
                    Label("New conversation", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("dsh")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    .accessibilityLabel("Refresh workspace")
                }
            }
        } detail: {
            conversation
        }
        .alert("Workspace", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.resumeIfConfigured() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.resumeIfConfigured() }
            } else {
                model.suspend()
            }
        }
    }

    private var hostPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tailnet host")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("https://host.example.ts.net", text: $model.hostURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("HTTPS tailnet host URL")
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            if model.selectedSessionID != nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(model.messages) { message in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(message.role.capitalized)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(message.content.isEmpty ? "(No text content)" : message.content)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .id(message.id)
                            }
                            if model.messages.isEmpty {
                                ContentUnavailableView("No messages yet", systemImage: "text.bubble")
                                    .padding(.top, 40)
                            }
                        }
                        .padding()
                    }
                    .onScrollGeometryChange(for: ConversationScrollMetrics.self) { geometry in
                        ConversationScrollMetrics(
                            contentOffsetY: geometry.contentOffset.y,
                            isNearLatest: geometry.contentOffset.y + geometry.containerSize.height >=
                                geometry.contentSize.height - 24
                        )
                    } action: { oldMetrics, newMetrics in
                        isNearLatest = newMetrics.isNearLatest
                        guard abs(oldMetrics.contentOffsetY - newMetrics.contentOffsetY) > 0.5 else { return }
                        model.updateFollowLatestFromUserScroll(
                            isNearLatest: newMetrics.isNearLatest,
                            isUserScrolling: userScrollInProgress
                        )
                    }
                    .onScrollPhaseChange { _, phase in
                        let wasUserScrolling = userScrollInProgress
                        let isUserDriven = phase == .interacting || phase == .decelerating
                        if wasUserScrolling && !isUserDriven {
                            model.updateFollowLatestFromUserScroll(
                                isNearLatest: isNearLatest,
                                isUserScrolling: true
                            )
                        }
                        userScrollInProgress = isUserDriven
                    }
                    .onChange(of: model.messages.count, initial: true) { _, _ in
                        scrollToLatest(using: proxy)
                    }
                    .onChange(of: model.messages.last?.content ?? "", initial: true) { _, _ in
                        scrollToLatest(using: proxy)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !model.followLatest, let lastID = model.messages.last?.id {
                            Button("Jump to latest", systemImage: "arrow.down.to.line") {
                                model.setFollowLatest(true)
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                            .accessibilityLabel("Jump to latest message")
                        }
                    }
                }
                if let pending = model.pendingApproval {
                    approvalCard(pending)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                if let notice = model.commandNotice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Command status. \(notice)")
                }
                composer
            } else {
                ContentUnavailableView(
                    "Choose a conversation",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Connect to your dsh host on the tailnet, then select or create a session.")
                )
            }
        }
        .navigationTitle(model.sessions.first(where: { $0.id == model.selectedSessionID })?.title ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard model.followLatest, let lastID = model.messages.last?.id else { return }
        proxy.scrollTo(lastID, anchor: .bottom)
    }

    private func approvalCard(_ approval: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Approval required", systemImage: "hand.raised.fill")
                .font(.headline)
            Text(approval["name"] as? String ?? "Tool request")
                .font(.subheadline.weight(.medium))
            if let arguments = approval["arguments"],
               let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Deny", role: .destructive) { Task { await model.decideApproval(approved: false) } }
                    .disabled(model.isBusy)
                Spacer()
                Button("Approve", role: .none) { Task { await model.decideApproval(approved: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: Binding(
                get: { model.draft },
                set: { model.setDraft($0) }
            ), axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Message")
            Button {
                Task { await model.sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .safeAreaPadding(.bottom, 0)
    }

    private var connectionIcon: String {
        switch model.connection {
        case "synced": "checkmark.circle.fill"
        case "connecting": "arrow.triangle.2.circlepath"
        case "needs_resync": "exclamationmark.arrow.triangle.2.circlepath"
        default: "wifi.slash"
        }
    }
}
