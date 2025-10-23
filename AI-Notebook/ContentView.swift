import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var drawing = PKDrawing()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PencilCanvasView(drawing: $drawing)
                .background(Color(UIColor.systemBackground))
                .ignoresSafeArea()

            Button {
                drawing = PKDrawing()
            } label: {
                Label("Clear", systemImage: "trash")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.trailing, 20)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }
}

#Preview {
    ContentView()
}
