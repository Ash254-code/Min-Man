import SwiftUI
import PDFKit

#if canImport(VisionKit)
import VisionKit

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

#else

/// Fallback when VisionKit is unavailable for the current target/platform.
struct VotesScannerSheet: View {
    let onComplete: (Data?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Document scanning is not available on this device.")
                .multilineTextAlignment(.center)
            Button("Close") { onCancel() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .onAppear {
            // Return nil to keep existing save validation behaviour unchanged.
            onComplete(nil)
        }
    }
}

#endif
