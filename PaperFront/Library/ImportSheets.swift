import SwiftUI

struct URLImportSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind: ItemKind = .book
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/book.pdf", text: $text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($focused)
                    Button {
                        if let s = UIPasteboard.general.string { text = s }
                    } label: { Label("Paste from Clipboard", systemImage: "doc.on.clipboard") }
                } header: { Text("Link") } footer: {
                    Text("Direct links to PDF, EPUB, text, Markdown, RTF or image files. Web pages are saved as readable documents.")
                }

                Section("Add to") {
                    Picker("Shelf", selection: $kind) {
                        ForEach(ItemKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Mocha.base.ignoresSafeArea())
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let link = text, shelf = kind
                        dismiss()
                        Task { await store.importFromWeb(link, kind: shelf) }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                kind = router.tab.kind
                focused = true
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
    }
}

struct NewDocumentSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Title", text: $title)
                    .font(.title2.weight(.semibold))
                    .padding()
                Divider().overlay(Mocha.surface1)
                TextEditor(text: $text)
                    .font(.system(.body, design: .serif))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
            }
            .background(Mocha.base.ignoresSafeArea())
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let t = title, body = text
                        dismiss()
                        Task { await store.createDocument(title: t, text: body) }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
