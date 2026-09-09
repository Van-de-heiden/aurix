import SwiftUI
@preconcurrency import AVFoundation

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    enum Mode { case photo, barcode }
    @Published var ready = false
    @Published var error: String?
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ch.aurix.camera", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var configured = false
    private var generation = UUID()
    private var active = false
    private var mode = Mode.photo
    private var barcodeSent = false
    private var takingPhoto = false
    var onPhoto: ((Data) -> Void)?
    var onBarcode: ((String) -> Void)?

    func start(_ mode: Mode) {
        error = nil
        queue.async {
            self.active = true; self.mode = mode; self.barcodeSent = false
            let generation = UUID(); self.generation = generation
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.configureAndRun(generation)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    self.queue.async {
                        guard self.generation == generation, self.active else { return }
                        if granted { self.configureAndRun(generation) } else { self.fail("Erlaube den Kamerazugriff in den iPhone-Einstellungen, um Fotos und Barcodes zu erfassen.") }
                    }
                }
            default: self.fail("Erlaube den Kamerazugriff in den iPhone-Einstellungen, um Fotos und Barcodes zu erfassen.")
            }
        }
    }
    func stop() {
        ready = false
        queue.async {
            self.active = false; self.generation = UUID()
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    func retryBarcode() { queue.async { self.barcodeSent = false } }
    func capture() {
        queue.async {
            guard self.active, self.configured, self.session.isRunning, !self.takingPhoto else { return }
            self.takingPhoto = true
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
    private func configureAndRun(_ generation: UUID) {
        guard self.active, self.generation == generation else { return }
        do {
            if !configured {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .photo
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    fail("Auf diesem Gerät ist keine Kamera verfügbar. Nutze die Fotomediathek oder erfasse dein Essen von Hand."); return
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(metadataOutput) else { fail("Die Kamera konnte nicht gestartet werden."); return }
                session.addInput(input); session.addOutput(photoOutput); session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: queue)
                metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce].filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
                if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                configured = true
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.ready = true }
        } catch { fail("Die Kamera konnte nicht gestartet werden. \(error.localizedDescription)") }
    }
    private func fail(_ message: String) { DispatchQueue.main.async { self.error = message; self.ready = false } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard active, mode == .barcode, !barcodeSent,
              let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        barcodeSent = true
        DispatchQueue.main.async { self.onBarcode?(code) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async { self.takingPhoto = false }
        guard error == nil, let original = photo.fileDataRepresentation(), let image = UIImage(data: original), let data = Self.compressed(image) else {
            fail("Das Foto konnte nicht verarbeitet werden. Versuche es erneut."); return
        }
        DispatchQueue.main.async { self.onPhoto?(data) }
    }
    static func compressed(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1280
        let factor = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        // Redrawing fixes orientation and omits original EXIF/GPS metadata.
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
    }
    func makeUIView(context: Context) -> Preview { let view = Preview(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ uiView: Preview, context: Context) {}
}
