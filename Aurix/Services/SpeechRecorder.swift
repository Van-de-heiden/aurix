import Foundation
import Combine
@preconcurrency import Speech
@preconcurrency import AVFoundation

@MainActor
final class SpeechRecorder: ObservableObject {
    @Published var transcript = ""
    @Published var recording = false
    @Published var error: String?
    @Published var preparing = false
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Task<Void, Never>?
    private var tapped = false
    private var generation = UUID()
    var onTimedFinish: (() -> Void)?

    func start() async {
        guard !recording, !preparing else { return }
        task?.cancel(); task = nil; request = nil
        preparing = true; error = nil; transcript = ""
        let run = UUID(); generation = run
        let permission = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard generation == run, !Task.isCancelled else { preparing = false; return }
        guard permission == .authorized else { preparing = false; error = "Erlaube die Spracherkennung in den iPhone-Einstellungen. Du kannst dein Essen auch tippen."; return }
        let microphone = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard generation == run, !Task.isCancelled else { preparing = false; return }
        guard microphone else { preparing = false; error = "Der Mikrofonzugriff ist ausgeschaltet."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-CH")), recognizer.isAvailable else { preparing = false; error = "Die Spracherkennung ist gerade nicht verfügbar. Du kannst die Mahlzeit unten tippen."; return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
            request.contextualStrings = ["Poulet", "Skyr", "Proteindrink", "Haferflocken", "Morgenessen", "Quark"]
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            let input = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == run else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if failure != nil, self.recording { self.error = "Die Aufnahme wurde unterbrochen. Dein bisheriger Text bleibt erhalten."; self.stopAudio() }
                    if result?.isFinal == true { self.stopAudio() }
                }
            }
            engine.prepare(); try engine.start(); recording = true; preparing = false
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled, let self, self.recording else { return }
                self.onTimedFinish?()
            }
        } catch { preparing = false; self.error = "Die Aufnahme konnte nicht starten. Bitte versuche es erneut."; cancel() }
    }
    func finish() async -> String {
        let run = generation
        stopAudio()
        // Give the recognizer a short opportunity to deliver the final words.
        try? await Task.sleep(for: .milliseconds(700))
        guard generation == run, !Task.isCancelled else { return "" }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel(); task = nil; request = nil
        return text
    }
    func cancel() {
        generation = UUID(); stopAudio(); task?.cancel(); task = nil; request = nil; preparing = false
    }
    private func stopAudio() {
        timer?.cancel(); timer = nil
        if engine.isRunning { engine.stop() }
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private enum RecorderError: Error { case noInput }
}
