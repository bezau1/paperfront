import SwiftUI

struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Books", systemImage: "books.vertical", value: AppTab.books) {
                ShelfView(kind: .book)
            }
            Tab("Documents", systemImage: "doc.text", value: AppTab.documents) {
                ShelfView(kind: .document)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .background(Mocha.base.ignoresSafeArea())
        .fileImporter(
            isPresented: $router.showFileImporter,
            allowedContentTypes: DocumentImporter.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let kind = router.tab.kind
                Task { await store.importFiles(urls, kind: kind) }
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $router.showURLImport) { URLImportSheet() }
        .sheet(isPresented: $router.showNewDocument) { NewDocumentSheet() }
        .fullScreenCover(item: $router.reading) { item in
            ReaderLoader(item: item)
                .preferredColorScheme(.dark)
        }
        .overlay(alignment: .top) { importBanner }
        .alert(
            "PaperFront",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onOpenURL { url in
            let kind = router.tab.kind
            Task { await store.importFile(url, kind: kind) }
        }
    }

    @ViewBuilder private var importBanner: some View {
        if let status = store.importStatus {
            HStack(spacing: 10) {
                ProgressView()
                Text(status).font(.subheadline).lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
