import SwiftUI

@main
struct DshClientEmbeddingApp: App {
    @StateObject private var model = DshClientModel()

    var body: some Scene {
        WindowGroup {
            ClientHomeView(model: model)
        }
    }
}
