import SwiftUI
import PDFKit

struct ReaderLoader: View {
    let item: LibraryItem
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReaderModel?
    @State private var failed = false

    var body: some View {
        ZStack {
            Mocha.crust.ignoresSafeArea()
            if let model {
                ReaderView(model: model)
            } else if failed {
                ContentUnavailableView {
                    Label("Can't Open", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The file for “\(item.title)” is missing or damaged.")
                } actions: {
                    Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if let m = ReaderModel(item: item, store: store) { model = m } else { failed = true }
        }
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ReaderView: View {
    @Bindable var model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    @State private var sliderValue = 0.0
    @State private var scrubbing = false
    @State private var showSidebar = false
    @State private var exportFile: ExportFile?
    @State private var confirmBake = false
    @State private var confirmClear = false
    @State private var noteText = ""
    @State private var showNoteAlert = false
    @State private var errorText: String?

    private var showChrome: Bool { model.chromeVisible || model.config.mode != .read }

    var body: some View {
        ZStack {
            Mocha.crust.ignoresSafeArea()
            PageCurlView(model: model, config: model.config)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if showChrome {
                    topBar.transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if showChrome {
                    bottomStack.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .animation(.smooth(duration: 0.3), value: showChrome)
        .animation(.smooth(duration: 0.25), value: model.config.mode)
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(showChrome ? .automatic : .hidden)
        .onChange(of: model.currentPage) { _, new in if !scrubbing { sliderValue = Double(new) } }
        .onChange(of: model.config.night) { _, new in UserDefaults.standard.set(new, forKey: "reader.night") }
        .onAppear { sliderValue = Double(model.currentPage) }
        .onDisappear { model.close() }
        .sheet(isPresented: $showSidebar) { ReaderSidebar(model: model) { page in
            showSidebar = false
            model.goTo(page)
        } }
        .sheet(item: $exportFile) { file in ShareSheet(url: file.url).presentationDetents([.medium, .large]) }
        .confirmationDialog(
            "Highlight",
            isPresented: Binding(get: { model.highlightActionID != nil }, set: { if !$0 { model.highlightActionID = nil } }),
            titleVisibility: .visible
        ) {
            if let id = model.highlightActionID {
                Button("Add or Edit Note") {
                    noteText = model.annotations.highlights.first { $0.id == id }?.note ?? ""
                    showNoteAlert = true
                }
                ForEach(Swatch.highlightChoices) { swatch in
                    Button("Change to \(swatch.label)") { model.annotations.setColor(swatch, for: id) }
                }
                Button("Delete Highlight", role: .destructive) { model.annotations.removeHighlight(id: id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Note", isPresented: $showNoteAlert) {
            TextField("Write a note", text: $noteText)
            Button("Save") {
                if let id = model.highlightActionID { model.annotations.setNote(noteText, for: id) }
                model.highlightActionID = nil
            }
            Button("Cancel", role: .cancel) { model.highlightActionID = nil }
        }
        .confirmationDialog("Bake annotations into this book?", isPresented: $confirmBake, titleVisibility: .visible) {
            Button("Bake In Permanently", role: .destructive) {
                do { try model.bakeIntoLibraryCopy() } catch { errorText = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Highlights and drawings become part of PaperFront's copy of the file and the separate layer is emptied. The file you imported is never touched.")
        }
        .confirmationDialog("Remove every highlight and drawing?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove All Annotations", role: .destructive) { model.clearAnnotations() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    // MARK: Top bar

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassIconButton(systemName: "chevron.left") { dismiss() }

                VStack(spacing: 1) {
                    Text(model.item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(model.pageLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular, in: .capsule)

                Menu {
                    Button { showSidebar = true } label: { Label("Contents & Highlights", systemImage: "list.bullet") }

                    Picker("Page Style", selection: $model.config.night) {
                        Label("Mocha Night", systemImage: "moon.stars").tag(true)
                        Label("Original Paper", systemImage: "doc.plaintext").tag(false)
                    }

                    Toggle(isOn: $model.config.showLayer) {
                        Label("Show Annotation Layer", systemImage: "square.3.layers.3d")
                    }

                    Divider()
                    Button { exportCopy() } label: { Label("Export Annotated PDF…", systemImage: "square.and.arrow.up") }
                    Button { confirmBake = true } label: { Label("Bake Into Book…", systemImage: "square.and.arrow.down.on.square") }
                        .disabled(model.annotations.isEmpty)
                    Button(role: .destructive) { confirmClear = true } label: { Label("Remove All Annotations…", systemImage: "trash") }
                        .disabled(model.annotations.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
            }
        }
    }

    private func exportCopy() {
        do { exportFile = ExportFile(url: try model.exportAnnotatedCopy()) }
        catch { errorText = error.localizedDescription }
    }

    // MARK: Bottom

    private var bottomStack: some View {
        VStack(spacing: 10) {
            switch model.config.mode {
            case .read: pageSlider
            case .highlight: highlightTray
            case .draw: drawTray
            }
            modePicker
        }
    }

    private var pageSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.pages").foregroundStyle(Mocha.subtext0)
            Slider(
                value: $sliderValue,
                in: 0...Double(max(model.pageCount - 1, 1)),
                step: 1,
                onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { model.goTo(Int(sliderValue)) }
                }
            )
            .tint(Mocha.mauve)
            .disabled(model.pageCount < 2)
            Text("\(Int(sliderValue) + 1)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Mocha.subtext1)
                .frame(minWidth: 28)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }

    private var modePicker: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                modeButton(.read, "book", "Read")
                modeButton(.highlight, "highlighter", "Highlight")
                modeButton(.draw, "pencil.tip", "Draw")
            }
        }
    }

    private func modeButton(_ mode: ReaderMode, _ symbol: String, _ label: String) -> some View {
        let selected = model.config.mode == mode
        return Button {
            withAnimation(.smooth) { model.config.mode = mode }
            if mode != .read { model.config.showLayer = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                if selected { Text(label).font(.subheadline.weight(.semibold)) }
            }
            .foregroundStyle(selected ? Mocha.crust : Mocha.text)
            .padding(.horizontal, selected ? 18 : 16)
            .frame(height: 46)
            .glassEffect(
                selected ? .regular.tint(Mocha.mauve).interactive() : .regular.interactive(),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var highlightTray: some View {
        VStack(spacing: 8) {
            Text("Drag across text to highlight · tap a highlight to edit")
                .font(.caption)
                .foregroundStyle(Mocha.subtext0)
            swatchRow(Swatch.highlightChoices, selection: $model.config.highlightColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var drawTray: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(PenTool.allCases, id: \.self) { tool in
                    let selected = model.config.penTool == tool
                    Button { model.config.penTool = tool } label: {
                        Image(systemName: icon(for: tool))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selected ? Mocha.crust : Mocha.text)
                            .frame(width: 44, height: 40)
                            .glassEffect(selected ? .regular.tint(Mocha.mauve).interactive() : .regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button { model.config.penWidth = model.config.penWidth.next } label: {
                    Circle()
                        .fill(Mocha.text)
                        .frame(width: widthDot, height: widthDot)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(model.config.penTool == .eraser)
                Button { model.controller?.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .opacity(model.canUndo ? 1 : 0.4)
                Button { model.controller?.redo() } label: {
                    Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .opacity(model.canRedo ? 1 : 0.4)
            }
            if model.config.penTool != .eraser {
                swatchRow(Swatch.penChoices, selection: $model.config.penColor)
            }
            HStack {
                Button { model.controller?.previous() } label: { Label("Previous", systemImage: "chevron.left").font(.footnote) }
                Spacer()
                Text(model.pageLabel).font(.caption).foregroundStyle(Mocha.subtext0)
                Spacer()
                Button { model.controller?.next() } label: { Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon).font(.footnote) }
            }
            .tint(Mocha.lavender)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var widthDot: CGFloat {
        switch model.config.penWidth { case .thin: return 6; case .medium: return 12; case .thick: return 20 }
    }

    private func icon(for tool: PenTool) -> String {
        switch tool {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    private func swatchRow(_ swatches: [Swatch], selection: Binding<Swatch>) -> some View {
        HStack(spacing: 12) {
            ForEach(swatches) { swatch in
                Button { selection.wrappedValue = swatch } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Mocha.text.opacity(0.35), lineWidth: 1))
                        .overlay {
                            if selection.wrappedValue == swatch {
                                Circle().strokeBorder(Mocha.text, lineWidth: 2.5).padding(-4)
                            }
                        }
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.label)
            }
        }
    }
}

struct GlassIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}
