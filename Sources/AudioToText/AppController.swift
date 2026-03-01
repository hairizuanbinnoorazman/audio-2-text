import AppKit

enum AppState {
    case idle
    case recording
    case transcribing
}

final class AppController {
    private let overlay: OverlayPanel
    private let recorder: AudioRecorder
    private let transcriber: Transcriber
    private var state: AppState = .idle
    private var transcriptionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(overlay: OverlayPanel, recorder: AudioRecorder, transcriber: Transcriber) {
        self.overlay = overlay
        self.recorder = recorder
        self.transcriber = transcriber
    }

    func hotkeyPressed() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            print("Transcription in progress, please wait...")
        }
    }

    private func startRecording() {
        print("Hotkey pressed, starting dictation...")
        overlay.show()

        do {
            try recorder.start()
        } catch {
            print("Recording error:", error)
            handleError("Mic error: \(error)")
            return
        }

        state = .recording
    }

    private func stopRecordingAndTranscribe() {
        print("Hotkey pressed, stopping recording...")
        state = .transcribing

        overlay.updateTranscription("Transcribing...")
        overlay.updateStatus("Transcribing...")
        overlay.stopWaveform()

        let audioData = recorder.stop()

        guard !audioData.isEmpty else {
            handleError("No audio captured")
            return
        }

        let sampleRate = recorder.sampleRate
        let overlay = self.overlay
        let transcriber = self.transcriber

        transcriptionTask = Task { @MainActor [weak self] in
            defer { self?.timeoutTask?.cancel() }
            do {
                let text = try await transcriber.transcribe(
                    audioData: audioData,
                    sampleRateHz: sampleRate
                )

                guard !Task.isCancelled else { return }

                print("Transcription result:", text)
                overlay.updateTranscription(text)
                overlay.updateStatus("Done!")

                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                overlay.hide()
                TextInjector.inject(text: text)
                self?.state = .idle
            } catch {
                guard !Task.isCancelled else { return }
                print("Transcription error:", error)
                self?.handleError("Transcription failed: \(error)")
            }
        }

        // Safety timeout: force-hide overlay if transcription hangs
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }

            print("Transcription timed out, force-hiding overlay")
            self?.transcriptionTask?.cancel()
            overlay.hide()
            self?.state = .idle
        }
    }

    private func handleError(_ message: String) {
        overlay.updateTranscription("")
        overlay.updateStatus(message)

        let overlay = self.overlay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            overlay.hide()
            self?.state = .idle
        }
    }
}
