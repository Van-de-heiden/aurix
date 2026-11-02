import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import AurixCore
@preconcurrency import AVFoundation

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureMetadataOutputObjectsDelegate {
    enum Mode { case photo, barcode }
    @Published private(set) var ready = false
    @Published private(set) var torchOn = false
    @Published private(set) var hasTorch = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var error: String?
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ch.aurix.camera", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var generation = UUID()
    // Main-thread token prevents queued readiness/results from reviving a closed screen.
    private var requestedGeneration = UUID()
    private var active = false
    private var mode = Mode.photo
    private var barcodeSent = false
    private var takingPhoto = false
    private var photoGeneration: UUID?
    private var retryAfter = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    var onPhoto: ((Data) -> Void)?
    var onBarcode: ((String) -> Void)?

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.active else { return }
                self.publish(self.generation) { self.ready = false; self.error = "Kamera kurz unterbrochen. Sie startet automatisch wieder." }
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.active else { return }
                self.configureAndRun(self.generation)
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
            let reset = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
            self?.queue.async { [weak self] in
                guard let self, self.active else { return }
                if reset { self.configureAndRun(self.generation) }
                else { self.fail("Die Kamera wurde angehalten. Starte sie erneut oder gib den Barcode ein.", self.generation) }
            }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start(_ mode: Mode) {
        #if targetEnvironment(simulator)
        ready = false; permissionDenied = false
        error = "Im Simulator ist keine Kamera verfügbar. Nutze die Barcode-Eingabe oder die Fotomediathek."
        #else
        let run = UUID(); requestedGeneration = run
        ready = false; error = nil; permissionDenied = false
        queue.async {
            self.active = true; self.mode = mode; self.barcodeSent = false
            self.generation = run
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: self.configureAndRun(run)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    self.queue.async {
                        guard self.generation == run, self.active else { return }
                        if granted { self.configureAndRun(run) }
                        else { self.denyPermission(run) }
                    }
                }
            default: self.denyPermission(run)
            }
        }
        #endif
    }
    func stop() {
        requestedGeneration = UUID(); ready = false; torchOn = false
        queue.async {
            self.active = false; self.generation = UUID(); self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    func retryBarcode() {
        queue.async { self.barcodeSent = false; self.retryAfter = Date().addingTimeInterval(0.8) }
    }
    func toggleTorch() {
        queue.async {
            guard self.active, let device = self.device, device.hasTorch else { return }
            self.setTorch(device.torchMode != .on)
        }
    }
    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on { try device.setTorchModeOn(level: min(0.6, AVCaptureDevice.maxAvailableTorchLevel)) }
            else { device.torchMode = .off }
            publish(generation) { self.torchOn = on }
        } catch { /* Scanning remains available without the torch. */ }
    }
    func capture() {
        queue.async {
            guard self.active, self.mode == .photo, self.configured, self.session.isRunning, !self.takingPhoto else { return }
            self.takingPhoto = true; self.photoGeneration = self.generation
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
    private func configureAndRun(_ run: UUID) {
        guard active, generation == run else { return }
        do {
            if !configured { try configure() }
            if let device {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = mode == .barcode ? .near : .none }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            }
            let types: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .upce, .itf14]
            metadataOutput.metadataObjectTypes = mode == .barcode ? types.filter { metadataOutput.availableMetadataObjectTypes.contains($0) } : []
            if mode == .barcode && metadataOutput.metadataObjectTypes.isEmpty {
                fail("Dieses Gerät kann keine Produktbarcodes lesen. Gib die Nummer unter dem Barcode ein.", run); return
            }
            if !session.isRunning { session.startRunning() }
            guard active, generation == run else { return }
            publish(run) { self.ready = self.session.isRunning && !self.session.isInterrupted; self.error = nil; self.hasTorch = self.device?.hasTorch == true }
        } catch { fail("Die Kamera konnte nicht gestartet werden. Versuche es erneut oder nutze die Barcode-Eingabe.", run) }
    }
    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Remove any partial setup left by a failed attempt.
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CocoaError(.featureUnsupported)
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
        session.addInput(input)
        guard session.canAddOutput(photoOutput) else { throw CocoaError(.featureUnsupported) }
        session.addOutput(photoOutput)
        guard session.canAddOutput(metadataOutput) else { throw CocoaError(.featureUnsupported) }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: queue)
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        device = camera; configured = true
    }
    private func publish(_ run: UUID, _ update: @escaping () -> Void) {
        DispatchQueue.main.async { guard self.requestedGeneration == run else { return }; update() }
    }
    private func fail(_ message: String, _ run: UUID) { publish(run) { self.error = message; self.ready = false } }
    private func denyPermission(_ run: UUID) {
        publish(run) { self.permissionDenied = true; self.error = "Erlaube DAYFUEL den Kamerazugriff in den iPhone-Einstellungen."; self.ready = false }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard active, mode == .barcode, !barcodeSent, Date() >= retryAfter else { return }
        for object in metadataObjects {
            guard let object = object as? AVMetadataMachineReadableCodeObject, let raw = object.stringValue,
                  let code = object.type == .upce ? Barcode.expandedUPCE(raw) : Barcode.normalized(raw) else { continue }
            barcodeSent = true
            publish(generation) { self.onBarcode?(code) }
            return
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let original = photo.fileDataRepresentation()
        let failed = error != nil
        queue.async {
            let run = self.photoGeneration
            self.photoGeneration = nil; self.takingPhoto = false
            guard let run, run == self.generation, self.active, self.mode == .photo else { return }
            guard !failed, let original, let data = Self.compressed(original) else {
                self.fail("Das Foto konnte nicht verarbeitet werden. Versuche es erneut.", run); return
            }
            self.publish(run) { self.onPhoto?(data) }
        }
    }
    static func compressed(_ data: Data) -> Data? {
        guard data.count <= 30_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1280,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // A fresh JPEG from the oriented pixels carries no source EXIF/GPS metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
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
