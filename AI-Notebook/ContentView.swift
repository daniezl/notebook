import SwiftUI
import PencilKit
import UIKit

struct ContentView: View {
    @State private var drawing = PKDrawing()
    @State private var selectedBackgroundPreset = BackgroundPreset.white.id

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
                    ForEach(BackgroundPreset.presets) { preset in
                        Button {
                            selectedBackgroundPreset = preset.id
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
    }
}

private struct BackgroundPreset: Identifiable {
    let id: String
    let name: String
    let uiColor: UIColor
    var color: Color { Color(uiColor) }

    static let white = BackgroundPreset(id: "white", name: "White", uiColor: .white)
    static let black = BackgroundPreset(id: "black", name: "Black", uiColor: .black)
    static let gray = BackgroundPreset(id: "gray", name: "Gray", uiColor: UIColor.systemGray5)
    static let cream = BackgroundPreset(id: "cream", name: "Cream", uiColor: UIColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 1.0))

    static let presets: [BackgroundPreset] = [white, black, gray, cream]
}

#Preview {
    ContentView()
}
