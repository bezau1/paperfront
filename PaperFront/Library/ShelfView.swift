import SwiftUI

struct ShelfView: View {
    let kind: ItemKind
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var renaming: LibraryItem?
    @State private var renameText = ""

    private var items: [LibraryItem] {
        store.items
            .filter { $0.kind == kind }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    emptyState.padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 190), spacing: 22)], spacing: 30) {
                        ForEach(items) { item in
                            Button { router.reading = item } label: { CoverCell(item: item) }
                                .buttonStyle(.plain)
                                .contextMenu { menu(for: item) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                }
            }
            .background(Mocha.base.ignoresSafeArea())
            .navigationTitle(kind.title)
            .searchable(text: $query, prompt: "Search \(kind.title.lowercased())")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { router.tab = kind == .book ? .books : .documents; router.showFileImporter = true } label: {
                            Label("Import from Files", systemImage: "folder")
                        }
                        Button { router.tab = kind == .book ? .books : .documents; router.showURLImport = true } label: {
                            Label("Import from URL", systemImage: "link")
                        }
                        Button { router.tab = kind == .book ? .books : .documents; router.showNewDocument = true } label: {
                            Label("New Document", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") { if let item = renaming { store.rename(item, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func menu(for item: LibraryItem) -> some View {
        Button { renameText = item.title; renaming = item } label: { Label("Rename", systemImage: "pencil") }
        Button {
            store.move(item, to: item.kind == .book ? .document : .book)
        } label: {
            Label(item.kind == .book ? "Move to Documents" : "Move to Books",
                  systemImage: item.kind == .book ? "doc.text" : "books.vertical")
        }
        ShareLink(item: store.pdfURL(for: item)) { Label("Share Original PDF", systemImage: "square.and.arrow.up") }
        Divider()
        Button(role: .destructive) { store.delete(item) } label: { Label("Delete", systemImage: "trash") }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(kind == .book ? "Your shelf is empty" : "No documents yet",
                  systemImage: kind == .book ? "books.vertical" : "doc.text")
        } description: {
            Text("Import PDF, EPUB, text, Markdown, RTF, HTML or images from Files, or paste a link.")
        } actions: {
            Button("Import from Files") { router.showFileImporter = true }
                .buttonStyle(.glassProminent)
            Button("Import from URL") { router.showURLImport = true }
                .buttonStyle(.glass)
        }
    }
}

struct CoverCell: View {
    let item: LibraryItem
    @Environment(LibraryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                cover
                if item.progress > 0 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.45))
                                Rectangle().fill(Mocha.mauve).frame(width: geo.size.width * item.progress)
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay(alignment: .leading) {
                // A hint of binding along the spine.
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
                    .allowsHitTesting(false)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 8, topTrailingRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 8)

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Mocha.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Mocha.subtext0)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        item.author.isEmpty ? "\(item.pageCount) pages" : item.author
    }

    @ViewBuilder private var cover: some View {
        if let image = store.cover(for: item) {
            Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
        } else {
            let accents: [Color] = [Mocha.mauve, Mocha.blue, Mocha.teal, Mocha.green, Mocha.peach, Mocha.red, Mocha.pink]
            let accent = accents[abs(item.title.hashValue) % accents.count]
            ZStack {
                LinearGradient(colors: [accent.opacity(0.9), Mocha.surface0], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(item.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Mocha.crust)
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
        }
    }
}
