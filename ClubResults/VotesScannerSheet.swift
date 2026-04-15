import SwiftUI
import VisionKit
import PDFKit

struct VotesScannerSheet: UIViewControllerRepresentable {
    let onComplete: (Data?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: (Data?) -> Void
        let onCancel: () -> Void

        init(onComplete: @escaping (Data?) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let document = PDFDocument()
            for index in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: index)
                if let page = PDFPage(image: image) {
                    document.insert(page, at: document.pageCount)
                }
            }
            onComplete(document.dataRepresentation())
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onComplete(nil)
        }
    }
}
