import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var drawing = PKDrawing()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.secondarySystemBackground)
                    .ignoresSafeArea()

                PencilCanvasView(drawing: $drawing)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        drawing = PKDrawing()
                    }
                }
            }
            .toolbar(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    ContentView()
}
