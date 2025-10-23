import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0
        context.coordinator.observeToolPicker(for: canvasView)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private var drawing: Binding<PKDrawing>
        private var toolPicker: PKToolPicker?
        private weak var canvasView: PKCanvasView?

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }

        func observeToolPicker(for canvasView: PKCanvasView) {
            self.canvasView = canvasView

            if let window = canvasView.window {
                attachToolPicker(to: canvasView, in: window)
            } else {
                DispatchQueue.main.async { [weak self, weak canvasView] in
                    guard let self, let canvasView, let window = canvasView.window else { return }
                    self.attachToolPicker(to: canvasView, in: window)
                }
            }
        }

        private func attachToolPicker(to canvasView: PKCanvasView, in window: UIWindow) {
            let picker = PKToolPicker.shared(for: window) ?? PKToolPicker()
            picker.addObserver(canvasView)
            picker.setVisible(true, forFirstResponder: canvasView)
            picker.selectedTool = PKInkingTool(.pen, color: .label, width: 5)
            canvasView.becomeFirstResponder()
            toolPicker = picker
        }
    }
}
