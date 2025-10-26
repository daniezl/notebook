import SwiftUI
import PencilKit
import UIKit
import Foundation

struct NoteViewport: Codable, Hashable {
    var offsetX: Double
    var offsetY: Double
    var zoomScale: Double
}

struct Note: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var drawingData: Data
    var backgroundPresetID: String
    var updatedAt: Date
    var viewport: NoteViewport?
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        drawing: PKDrawing,
        backgroundPresetID: String,
        updatedAt: Date = Date(),
        viewport: NoteViewport? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.drawingData = drawing.dataRepresentation()
        self.backgroundPresetID = backgroundPresetID
        self.updatedAt = updatedAt
        self.viewport = viewport
        self.deletedAt = deletedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        drawingData: Data,
        backgroundPresetID: String,
        updatedAt: Date = Date(),
        viewport: NoteViewport? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.drawingData = drawingData
        self.backgroundPresetID = backgroundPresetID
        self.updatedAt = updatedAt
        self.viewport = viewport
        self.deletedAt = deletedAt
    }

    func makeDrawing() -> PKDrawing {
        (try? PKDrawing(data: drawingData)) ?? PKDrawing()
    }
}

final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var recentlyDeleted: [Note] = []

    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private struct PersistedNotes: Codable {
        var notes: [Note]
        var recentlyDeleted: [Note]
    }

    init() {
        self.storageURL = NoteStore.makeStorageURL()
        self.encoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }()
        self.decoder = {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }()
        load()
    }

    func upsert(_ note: Note) {
        var sanitized = note
        sanitized.deletedAt = nil

        if let index = notes.firstIndex(where: { $0.id == sanitized.id }) {
            notes[index] = sanitized
        } else {
            notes.append(sanitized)
        }
        notes.sort { $0.updatedAt > $1.updatedAt }

        if let deletedIndex = recentlyDeleted.firstIndex(where: { $0.id == sanitized.id }) {
            recentlyDeleted.remove(at: deletedIndex)
        }

        persist()
    }

    func delete(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var deletedNote = notes.remove(at: index)
        deletedNote.deletedAt = Date()
        recentlyDeleted.removeAll { $0.id == deletedNote.id }
        recentlyDeleted.append(deletedNote)
        recentlyDeleted.sort { (lhs, rhs) in
            let lhsDate = lhs.deletedAt ?? .distantPast
            let rhsDate = rhs.deletedAt ?? .distantPast
            return lhsDate > rhsDate
        }
        persist()
    }

    func restore(_ note: Note) {
        guard let index = recentlyDeleted.firstIndex(where: { $0.id == note.id }) else { return }
        var restored = recentlyDeleted.remove(at: index)
        restored.deletedAt = nil
        if let existingIndex = notes.firstIndex(where: { $0.id == restored.id }) {
            notes[existingIndex] = restored
        } else {
            notes.append(restored)
        }
        notes.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func permanentlyDelete(_ note: Note) {
        recentlyDeleted.removeAll { $0.id == note.id }
        persist()
    }

    func note(withID id: UUID) -> Note? {
        notes.first(where: { $0.id == id })
    }

    func makeDefaultTitle() -> String {
        Self.titleDateFormatter.string(from: Date())
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            notes = []
            recentlyDeleted = []
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            if let decoded = try? decoder.decode(PersistedNotes.self, from: data) {
                notes = decoded.notes.sorted { $0.updatedAt > $1.updatedAt }
                recentlyDeleted = decoded.recentlyDeleted.sorted {
                    ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
                }
            } else {
                let decodedNotes = try decoder.decode([Note].self, from: data)
                notes = decodedNotes
                    .filter { $0.deletedAt == nil }
                    .sorted { $0.updatedAt > $1.updatedAt }
                recentlyDeleted = decodedNotes
                    .compactMap { note -> Note? in
                        guard let deletedAt = note.deletedAt else { return nil }
                        var trashed = note
                        trashed.deletedAt = deletedAt
                        return trashed
                    }
                    .sorted {
                        ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
                    }
            }
        } catch {
            notes = []
            recentlyDeleted = []
            #if DEBUG
            print("Failed to load notes: \(error)")
            #endif
        }
    }

    private func persist() {
        do {
            let payload = PersistedNotes(notes: notes, recentlyDeleted: recentlyDeleted)
            let data = try encoder.encode(payload)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            #if DEBUG
            print("Failed to persist notes: \(error)")
            #endif
        }
    }

    private static func makeStorageURL() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let folder = baseDirectory.appendingPathComponent("SavedNotes", isDirectory: true)

        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        return folder.appendingPathComponent("notes.json")
    }
}

enum NoteRoute: Hashable {
    case existing(UUID)
    case new(Note)
}

struct ContentView: View {
    @StateObject private var store = NoteStore()
    @State private var path: [NoteRoute] = []
    @AppStorage("globalBackgroundPresetID") private var globalBackgroundPresetID = BackgroundPreset.white.id

    private var appColorPreset: BackgroundPreset {
        BackgroundPreset.presets.first(where: { $0.id == globalBackgroundPresetID }) ?? .white
    }

    var body: some View {
        NavigationStack(path: $path) {
            NoteListView(path: $path)
                .environmentObject(store)
                .navigationDestination(for: NoteRoute.self) { route in
                    switch route {
                    case .existing(let id):
                        if let note = store.note(withID: id) {
                            NoteEditorView(note: note, isNew: false)
                                .environmentObject(store)
                        } else {
                            MissingNoteView()
                        }
                    case .new(let note):
                        NoteEditorView(note: note, isNew: true)
                            .environmentObject(store)
                    }
                }
        }
        .preferredColorScheme(appColorPreset.preferredColorScheme)
    }
}

private struct NoteListView: View {
    @Binding var path: [NoteRoute]
    @EnvironmentObject private var store: NoteStore
    @AppStorage("globalBackgroundPresetID") private var globalBackgroundPresetID = BackgroundPreset.white.id

    private var globalPreset: BackgroundPreset {
        BackgroundPreset.presets.first(where: { $0.id == globalBackgroundPresetID }) ?? .white
    }

    var body: some View {
        List {
            if store.notes.isEmpty {
                EmptyNotesView()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.notes) { note in
                    NavigationLink(value: NoteRoute.existing(note.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.ifBlank(replaceWith: "未命名笔记"))
                                .font(.headline)
                            Text(note.updatedAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .onDelete(perform: delete)
            }

            if !store.recentlyDeleted.isEmpty {
                Section {
                    NavigationLink {
                        RecentlyDeletedListView()
                            .environmentObject(store)
                    } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    createNewNote()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建笔记")
                .applyGlassyControl()
            }
        }
    }

    private func createNewNote() {
        let defaultPreset = globalPreset
        let title = store.makeDefaultTitle()
        let newNote = Note(title: title, drawing: PKDrawing(), backgroundPresetID: defaultPreset.id)
        path.append(.new(newNote))
    }

    private func delete(at offsets: IndexSet) {
        offsets
            .compactMap { index -> Note? in
                guard store.notes.indices.contains(index) else { return nil }
                return store.notes[index]
            }
            .forEach { store.delete($0) }
    }
}

private struct RecentlyDeletedListView: View {
    @EnvironmentObject private var store: NoteStore

    var body: some View {
        List {
            if store.recentlyDeleted.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Recently Deleted is empty")
                        .font(.headline)
                    Text("Deleted notes stay here for a limited time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            } else {
                ForEach(store.recentlyDeleted) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title.ifBlank(replaceWith: "未命名笔记"))
                            .font(.headline)
                        if let deletedAt = note.deletedAt {
                            Text(deletedAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .swipeActions(edge: .leading) {
                        Button {
                            store.restore(note)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.permanentlyDelete(note)
                        } label: {
                            Label("Delete Permanently", systemImage: "trash.slash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recently Deleted")
    }
}

private struct EmptyNotesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text("还没有笔记")
                .font(.headline)
            Text("点右上角的加号来创建新笔记。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct MissingNoteView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("找不到这条笔记")
                .font(.headline)
            Button("返回列表") {
                dismiss()
            }
            .applyGlassyControl()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

private struct NoteEditorView: View {
    private let noteID: UUID

    @EnvironmentObject private var store: NoteStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("globalBackgroundPresetID") private var globalBackgroundPresetID = BackgroundPreset.white.id

    @State private var isNewNote: Bool
    @State private var title: String
    @State private var drawing: PKDrawing
    @State private var viewport: CanvasViewportState
    @State private var selectedBackgroundPresetID: String
    @State private var lastSavedTitle: String
    @State private var lastSavedBackgroundID: String
    @State private var lastSavedDrawingData: Data
    @State private var lastSavedViewport: NoteViewport?
    @State private var autoSaveWorkItem: DispatchWorkItem?

    private var selectedPreset: BackgroundPreset {
        BackgroundPreset.presets.first(where: { $0.id == selectedBackgroundPresetID }) ?? .white
    }

    private var hasUnsavedChanges: Bool {
        if isNewNote {
            return true
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle != lastSavedTitle {
            return true
        }

        if selectedPreset.id != lastSavedBackgroundID {
            return true
        }

        if drawing.dataRepresentation() != lastSavedDrawingData {
            return true
        }

        let currentViewport = viewport.toNoteViewport()
        if currentViewport != lastSavedViewport {
            return true
        }

        return false
    }

    private var backgroundPresetMenu: some View {
        Menu {
            ForEach(BackgroundPreset.Category.allCases) { category in
                Section(category.title) {
                    ForEach(BackgroundPreset.presets.filter { $0.category == category }) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 12, height: 12)
                                Text(preset.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("背景颜色", systemImage: "paintpalette")
                .labelStyle(.iconOnly)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .accessibilityLabel("切换背景颜色")
        .tint(.primary)
        .applyGlassyControl()
        .applyMenuButtonStyle()
    }

    init(note: Note, isNew: Bool) {
        self.noteID = note.id
        _isNewNote = State(initialValue: isNew)
        _title = State(initialValue: note.title)
        _drawing = State(initialValue: note.makeDrawing())
        _viewport = State(initialValue: CanvasViewportState(noteViewport: note.viewport))
        _selectedBackgroundPresetID = State(initialValue: note.backgroundPresetID)
        _lastSavedTitle = State(initialValue: note.title)
        _lastSavedBackgroundID = State(initialValue: note.backgroundPresetID)
        _lastSavedDrawingData = State(initialValue: note.drawingData)
        _lastSavedViewport = State(initialValue: note.viewport)
        _autoSaveWorkItem = State(initialValue: nil)
    }

    var body: some View {
        ZStack {
            selectedPreset.color
                .ignoresSafeArea()

            PencilCanvasView(
                drawing: $drawing,
                backgroundColor: selectedPreset.uiColor,
                viewport: $viewport
            )
                .ignoresSafeArea()
        }
        .preferredColorScheme(selectedPreset.preferredColorScheme)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    commitPendingAutoSave()
                    dismiss()
                } label: {
                    Label("返回", systemImage: "chevron.backward")
                }
                .applyGlassyControl()
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                backgroundPresetMenu
            }
        }
        .navigationBarBackButtonHidden()
        .onAppear {
            globalBackgroundPresetID = selectedPreset.id
            scheduleAutoSave()
        }
        .onDisappear {
            commitPendingAutoSave()
        }
        .onChange(of: title) { _ in
            scheduleAutoSave()
        }
        .onChange(of: drawing) { _ in
            scheduleAutoSave()
        }
        .onChange(of: selectedBackgroundPresetID) { _ in
            scheduleAutoSave()
        }
        .onChange(of: viewport) { _ in
            scheduleAutoSave()
        }
    }

    private func scheduleAutoSave() {
        autoSaveWorkItem?.cancel()
        guard hasUnsavedChanges else { return }

        let workItem = DispatchWorkItem { [self] in
            autoSaveWorkItem = nil
            saveNote()
        }
        autoSaveWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func commitPendingAutoSave() {
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        saveNote()
    }

    private func applyPreset(_ preset: BackgroundPreset) {
        selectedBackgroundPresetID = preset.id
        globalBackgroundPresetID = preset.id
        scheduleAutoSave()
    }

    private func saveNote() {
        guard hasUnsavedChanges else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = store.makeDefaultTitle()
        let finalTitle: String

        if trimmedTitle.isEmpty {
            finalTitle = isNewNote ? fallbackTitle : lastSavedTitle.ifBlank(replaceWith: fallbackTitle)
        } else {
            finalTitle = trimmedTitle
        }

        let drawingData = drawing.dataRepresentation()
        let viewportData = viewport.toNoteViewport()
        let note = Note(
            id: noteID,
            title: finalTitle,
            drawingData: drawingData,
            backgroundPresetID: selectedPreset.id,
            updatedAt: Date(),
            viewport: viewportData
        )

        store.upsert(note)
        title = finalTitle
        lastSavedTitle = finalTitle
        lastSavedBackgroundID = selectedPreset.id
        lastSavedDrawingData = drawingData
        lastSavedViewport = viewportData
        isNewNote = false
        globalBackgroundPresetID = selectedPreset.id
    }
}

struct BackgroundPreset: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }
        var title: String { rawValue }
        var preferredScheme: ColorScheme { self == .light ? .light : .dark }
    }

    let id: String
    let name: String
    let uiColor: UIColor
    let category: Category
    var color: Color { Color(uiColor) }
    var preferredColorScheme: ColorScheme? { category.preferredScheme }

    static let white = BackgroundPreset(id: "white", name: "White", uiColor: .white, category: .light)
    static let cream = BackgroundPreset(id: "cream", name: "Cream", uiColor: UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1.0), category: .light)
    static let gray = BackgroundPreset(id: "gray", name: "Gray", uiColor: UIColor(white: 0.2, alpha: 1.0), category: .dark)
    static let black = BackgroundPreset(id: "black", name: "Black", uiColor: .black, category: .dark)

    static let presets: [BackgroundPreset] = [white, cream, gray, black]
}

private extension View {
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else if #available(iOS 15.0, *) {
            self.buttonStyle(.borderedProminent)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyControlSize(_ size: ControlSize) -> some View {
        if #available(iOS 15.0, *) {
            self.controlSize(size)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyCapsuleBorder() -> some View {
        if #available(iOS 15.0, *) {
            self.buttonBorderShape(.capsule)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyGlassyControl() -> some View {
        self
            .applyControlSize(.small)
            .applyCapsuleBorder()
            .glassButtonStyle()
    }

    @ViewBuilder
    func applyMenuButtonStyle() -> some View {
        if #available(iOS 17.0, *) {
            self.menuStyle(.button)
        } else {
            self
        }
    }
}

private extension String {
    func ifBlank(replaceWith replacement: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? replacement : self
    }
}

#Preview {
    ContentView()
}
