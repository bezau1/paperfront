import SwiftUI

@main
struct PaperFrontApp: App {
    @State private var store = LibraryStore()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(Mocha.mauve)
        }
    }
}
