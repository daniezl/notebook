import SwiftUI
import PencilKit
import UIKit

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
        canvasView.allowsFingerDrawing = true
        canvasView.tool = PKInkingTool(.pen, color: .label, width: 5)
        canvasView.backgroundColor = .clear
        canvasView.minimumZoomScale = 1.0
        canvasView.maximumZoomScale = 1.0

        DispatchQueue.main.async {
            context.coordinator.showToolPicker(for: canvasView)
        }

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }

        DispatchQueue.main.async {
            context.coordinator.showToolPicker(for: uiView)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private var drawing: Binding<PKDrawing>
        private var toolPicker: PKToolPicker?

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }

        func showToolPicker(for canvasView: PKCanvasView) {
            guard let targetWindow = canvasView.window ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow || $0.windowScene?.activationState == .foregroundActive }) else {
                retryShowToolPicker(for: canvasView)
                return
            }

            let picker: PKToolPicker
            if let sharedPicker = PKToolPicker.shared(for: targetWindow) {
                picker = sharedPicker
            } else if let cachedPicker = toolPicker {
                picker = cachedPicker
            } else {
                picker = PKToolPicker()
            }

            toolPicker = picker
            picker.addObserver(canvasView)

            if !canvasView.isFirstResponder {
                canvasView.becomeFirstResponder()
            }

            picker.setVisible(true, forFirstResponder: canvasView)
        }

        private func retryShowToolPicker(for canvasView: PKCanvasView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak canvasView] in
                guard let self, let canvasView else { return }
                self.showToolPicker(for: canvasView)
            }
        }
    }
}
