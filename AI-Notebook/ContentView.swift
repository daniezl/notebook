import SwiftUI
import PencilKit
import UIKit

struct ContentView: View {
    @State private var drawing = PKDrawing()
    @AppStorage("selectedBackgroundPresetID") private var storedBackgroundPresetID: String = ""
    @State private var selectedBackgroundPreset = BackgroundPreset.white.id
    @State private var hasInitializedPreset = false

    private var selectedPreset: BackgroundPreset {
        BackgroundPreset.presets.first(where: { $0.id == selectedBackgroundPreset }) ?? .white
    }

    private var backgroundColor: Color {
        selectedPreset.color
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundColor
                .ignoresSafeArea()

            PencilCanvasView(drawing: $drawing, backgroundColor: selectedPreset.uiColor)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                Menu {
                    ForEach(BackgroundPreset.Category.allCases) { category in
                        Section(category.title) {
                            ForEach(BackgroundPreset.presets.filter { $0.category == category }) { preset in
                                Button {
                                    selectedBackgroundPreset = preset.id
                                    storedBackgroundPresetID = preset.id
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 14, height: 14)
                                        Text(preset.name)
                                        if selectedBackgroundPreset == preset.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("Change background color")
                .tint(.primary)

                Button {
                    drawing = PKDrawing()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
            .padding(.trailing, 20)
        }
        .preferredColorScheme(selectedPreset.preferredColorScheme)
        .onAppear {
            guard !hasInitializedPreset else { return }

            if storedBackgroundPresetID.isEmpty {
                let userInterfaceStyle = UIScreen.main.traitCollection.userInterfaceStyle
                let defaultPreset: BackgroundPreset = (userInterfaceStyle == .dark) ? .gray : .white
                selectedBackgroundPreset = defaultPreset.id
                storedBackgroundPresetID = defaultPreset.id
            } else {
                selectedBackgroundPreset = storedBackgroundPresetID
            }

            hasInitializedPreset = true
        }
    }
}


private struct BackgroundPreset: Identifiable {
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

#Preview {
    ContentView()
}
