import SwiftUI
import PencilKit
import UIKit

struct CanvasViewportState: Equatable {
    static let offsetTolerance: CGFloat = 0.5
    static let scaleTolerance: CGFloat = 0.01

    var contentOffset: CGPoint
    var zoomScale: CGFloat
    var isRestoredFromPersistence: Bool

    init(
        contentOffset: CGPoint = .zero,
        zoomScale: CGFloat = 1,
        isRestoredFromPersistence: Bool = false
    ) {
        self.contentOffset = contentOffset
        self.zoomScale = zoomScale
        self.isRestoredFromPersistence = isRestoredFromPersistence
    }

    init(noteViewport: NoteViewport?) {
        if let noteViewport {
            self.contentOffset = CGPoint(
                x: CGFloat(noteViewport.offsetX),
                y: CGFloat(noteViewport.offsetY)
            )
            self.zoomScale = CGFloat(noteViewport.zoomScale)
            self.isRestoredFromPersistence = true
        } else {
            self.contentOffset = .zero
            self.zoomScale = 1
            self.isRestoredFromPersistence = false
        }
    }

    var isApproximatelyDefault: Bool {
        abs(contentOffset.x) < Self.offsetTolerance &&
            abs(contentOffset.y) < Self.offsetTolerance &&
            abs(zoomScale - 1) < Self.scaleTolerance
    }

    func toNoteViewport() -> NoteViewport? {
        guard !isApproximatelyDefault else {
            return nil
        }

        return NoteViewport(
            offsetX: Double(contentOffset.x),
            offsetY: Double(contentOffset.y),
            zoomScale: Double(zoomScale)
        )
    }
}

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var backgroundColor: UIColor
    @Binding var viewport: CanvasViewportState

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, viewport: $viewport)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .label, width: 5)
        canvasView.backgroundColor = backgroundColor
        canvasView.isOpaque = false

        context.coordinator.configureFreeformCanvas(for: canvasView)
        context.coordinator.registerPencilPreferenceObserver(for: canvasView)

        DispatchQueue.main.async {
            context.coordinator.showToolPicker(for: canvasView)
        }

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }

        if uiView.backgroundColor != backgroundColor {
            uiView.backgroundColor = backgroundColor
        }

        context.coordinator.configureFreeformCanvas(for: uiView)
        context.coordinator.registerPencilPreferenceObserver(for: uiView)

        DispatchQueue.main.async {
            context.coordinator.showToolPicker(for: uiView)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
        private let baseCanvasSize = CGSize(width: 8192, height: 8192)
        private var drawing: Binding<PKDrawing>
        private var viewport: Binding<CanvasViewportState>
        private var toolPicker: PKToolPicker?
        private weak var observedCanvasView: PKCanvasView?
        private var pencilPreferenceObserver: NSObjectProtocol?
        private var hasInitializedViewport = false
        private var hasUserAdjustedViewport = false
        private var hasConfiguredContentSize = false
        private var lastViewportSize: CGSize = .zero
        private var initialContentOffset: CGPoint = .zero

        init(drawing: Binding<PKDrawing>, viewport: Binding<CanvasViewportState>) {
            self.drawing = drawing
            self.viewport = viewport
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
            observedCanvasView = canvasView

            updateViewportBinding(
                offset: scrollView.contentOffset,
                zoomScale: scrollView.zoomScale,
                markAsRestored: false
            )

            guard hasInitializedViewport, !hasUserAdjustedViewport else { return }

            let deltaX = abs(scrollView.contentOffset.x - initialContentOffset.x)
            let deltaY = abs(scrollView.contentOffset.y - initialContentOffset.y)

            if deltaX > 2 || deltaY > 2 {
                hasUserAdjustedViewport = true
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard scrollView is PKCanvasView else { return }
            hasUserAdjustedViewport = true
            updateViewportBinding(
                offset: scrollView.contentOffset,
                zoomScale: scrollView.zoomScale,
                markAsRestored: false
            )
        }

        func configureFreeformCanvas(for canvasView: PKCanvasView) {
            canvasView.isScrollEnabled = true
            canvasView.minimumZoomScale = 0.2
            canvasView.maximumZoomScale = 4.0
            canvasView.bounces = false
            canvasView.bouncesZoom = false
            canvasView.alwaysBounceVertical = false
            canvasView.alwaysBounceHorizontal = false
            canvasView.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0)
            canvasView.contentInsetAdjustmentBehavior = .never
            canvasView.showsVerticalScrollIndicator = false
            canvasView.showsHorizontalScrollIndicator = false
            canvasView.delegate = self

            let viewportSize = CGSize(width: ceil(canvasView.bounds.width), height: ceil(canvasView.bounds.height))
            let viewportChanged = abs(viewportSize.width - lastViewportSize.width) > 1 || abs(viewportSize.height - lastViewportSize.height) > 1

            if viewportSize.width <= 1 || viewportSize.height <= 1 {
                if !hasInitializedViewport {
                    DispatchQueue.main.async { [weak self, weak canvasView] in
                        guard let self, let canvasView else { return }
                        self.configureFreeformCanvas(for: canvasView)
                    }
                }
                return
            }

            if observedCanvasView !== canvasView {
                observedCanvasView = canvasView
                hasInitializedViewport = false
                hasUserAdjustedViewport = false
                hasConfiguredContentSize = false
                lastViewportSize = viewportSize
            } else if viewportChanged {
                lastViewportSize = viewportSize
            }

            if !hasConfiguredContentSize {
                canvasView.contentSize = baseCanvasSize
                hasConfiguredContentSize = true
            }

            if !hasInitializedViewport || (viewportChanged && !hasUserAdjustedViewport) {
                applyInitialViewport(for: canvasView)
            }
        }

        private func applyInitialViewport(for canvasView: PKCanvasView) {
            let size = baseCanvasSize
            guard size.width > 0, size.height > 0, canvasView.bounds.width > 0, canvasView.bounds.height > 0 else {
                hasInitializedViewport = false
                return
            }

            let storedViewport = viewport.wrappedValue
            let inset = canvasView.adjustedContentInset

            let defaultOffset = CGPoint(
                x: max(((size.width - canvasView.bounds.width) / 2 - inset.left) * 0.4, -inset.left + 200),
                y: max(((size.height - canvasView.bounds.height) / 2 - inset.top) * 0.4, -inset.top + 150)
            )

            let hasStoredViewport = storedViewport.isRestoredFromPersistence || !storedViewport.isApproximatelyDefault
            let shouldUseStoredViewport = hasStoredViewport
            let desiredOffset = shouldUseStoredViewport ? storedViewport.contentOffset : defaultOffset
            let clampedOffset = clampContentOffset(desiredOffset, for: canvasView)

            let desiredZoom = shouldUseStoredViewport ? storedViewport.zoomScale : canvasView.zoomScale
            let clampedZoom = clampZoomScale(desiredZoom, for: canvasView)

            if abs(canvasView.zoomScale - clampedZoom) > 0.001 {
                canvasView.setZoomScale(clampedZoom, animated: false)
            }

            hasInitializedViewport = true
            hasUserAdjustedViewport = false
            lastViewportSize = CGSize(width: ceil(canvasView.bounds.width), height: ceil(canvasView.bounds.height))
            initialContentOffset = clampedOffset

            canvasView.setContentOffset(clampedOffset, animated: false)

            updateViewportBinding(
                offset: clampedOffset,
                zoomScale: clampedZoom,
                markAsRestored: false
            )
        }

        private func clampContentOffset(_ offset: CGPoint, for canvasView: PKCanvasView) -> CGPoint {
            let inset = canvasView.adjustedContentInset
            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, canvasView.contentSize.width - canvasView.bounds.width + inset.right)
            let maxY = max(minY, canvasView.contentSize.height - canvasView.bounds.height + inset.bottom)

            let clampedX = min(max(offset.x, minX), maxX)
            let clampedY = min(max(offset.y, minY), maxY)
            return CGPoint(x: clampedX, y: clampedY)
        }

        private func clampZoomScale(_ zoomScale: CGFloat, for canvasView: PKCanvasView) -> CGFloat {
            let minimum = canvasView.minimumZoomScale
            let maximum = canvasView.maximumZoomScale
            if minimum > maximum {
                return zoomScale
            }
            return min(max(zoomScale, minimum), maximum)
        }

        private func updateViewportBinding(offset: CGPoint, zoomScale: CGFloat, markAsRestored: Bool) {
            let newState = CanvasViewportState(
                contentOffset: offset,
                zoomScale: zoomScale,
                isRestoredFromPersistence: markAsRestored
            )
            let current = viewport.wrappedValue
            if !approximatelyEqual(current, newState) || current.isRestoredFromPersistence != newState.isRestoredFromPersistence {
                viewport.wrappedValue = newState
            }
        }

        private func approximatelyEqual(_ lhs: CanvasViewportState, _ rhs: CanvasViewportState) -> Bool {
            let deltaX = abs(lhs.contentOffset.x - rhs.contentOffset.x)
            let deltaY = abs(lhs.contentOffset.y - rhs.contentOffset.y)
            let deltaScale = abs(lhs.zoomScale - rhs.zoomScale)
            return deltaX < CanvasViewportState.offsetTolerance &&
                deltaY < CanvasViewportState.offsetTolerance &&
                deltaScale < CanvasViewportState.scaleTolerance
        }

        func registerPencilPreferenceObserver(for canvasView: PKCanvasView) {
            observedCanvasView = canvasView
            updateFingerDrawingPolicy(for: canvasView)

            guard pencilPreferenceObserver == nil else { return }

            pencilPreferenceObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let canvasView = self.observedCanvasView else { return }
                self.updateFingerDrawingPolicy(for: canvasView)
            }
        }

        private func updateFingerDrawingPolicy(for canvasView: PKCanvasView) {
            if #available(iOS 14.0, *) {
                canvasView.allowsFingerDrawing = !UIPencilInteraction.prefersPencilOnlyDrawing
            } else {
                canvasView.allowsFingerDrawing = true
            }
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

        deinit {
            if let observer = pencilPreferenceObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
