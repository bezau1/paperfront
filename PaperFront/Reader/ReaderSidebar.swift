import SwiftUI

struct ReaderSidebar: View {
    @Bindable var model: ReaderModel
    let jump: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    Text("Contents").tag(0)
                    Text("Highlights").tag(1)
                    Text("Drawings").tag(2)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                List {
                    switch tab {
                    case 0: contents
                    case 1: highlights
                    default: drawings
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Mocha.base.ignoresSafeArea())
            .navigationTitle(model.item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    @ViewBuilder private var contents: some View {
        let rows = model.outline
        if rows.isEmpty {
            placeholder("No table of contents", "This file doesn't include chapter markers.", "list.bullet")
        } else {
            ForEach(rows) { row in
                Button { jump(row.page) } label: {
                    HStack {
                        Text(row.title).padding(.leading, CGFloat(row.depth) * 14)
                        Spacer()
                        Text("\(row.page + 1)").foregroundStyle(Mocha.subtext0).monospacedDigit()
                    }
                }
                .listRowBackground(Mocha.surface0.opacity(0.6))
            }
        }
    }

    @ViewBuilder private var highlights: some View {
        let all = model.annotations.highlights.sorted { ($0.page, $0.createdAt) < ($1.page, $1.createdAt) }
        if all.isEmpty {
            placeholder("No highlights yet", "Switch to Highlight mode and drag across some text.", "highlighter")
        } else {
            ForEach(all) { h in
                Button { jump(h.page) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(h.color.color).frame(width: 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(h.text).lineLimit(4).font(.callout)
                            if !h.note.isEmpty {
                                Label(h.note, systemImage: "note.text").font(.footnote).foregroundStyle(Mocha.lavender)
                            }
                            Text("Page \(h.page + 1)").font(.caption).foregroundStyle(Mocha.subtext0)
                        }
                    }
                }
                .listRowBackground(Mocha.surface0.opacity(0.6))
                .swipeActions {
                    Button(role: .destructive) { model.annotations.removeHighlight(id: h.id) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    @ViewBuilder private var drawings: some View {
        let pages = model.annotations.drawnPages
        if pages.isEmpty {
            placeholder("No drawings yet", "Switch to Draw mode and sketch on any page.", "pencil.tip")
        } else {
            ForEach(pages, id: \.self) { page in
                Button { jump(page) } label: {
                    Label("Page \(page + 1)", systemImage: "scribble")
                }
                .listRowBackground(Mocha.surface0.opacity(0.6))
            }
        }
    }

    private func placeholder(_ title: String, _ message: String, _ symbol: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .listRowBackground(Color.clear)
    }
}
