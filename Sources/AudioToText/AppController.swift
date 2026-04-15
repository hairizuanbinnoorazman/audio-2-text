import AppKit

protocol TranscriptionService: Sendable {
    func transcribe(audioData: Data, sampleRateHz: Int) async throws -> String
}

protocol TextCleaningService: Sendable {
    func clean(rawText: String) async throws -> String
}

enum AppState {
    case idle
    case starting
    case recording
    case transcribing
}

final class AppController {
    private let overlay: OverlayPanel
    private let recorder: AudioRecorder
    private let transcriptionService: any TranscriptionService
    private let textCleaner: (any TextCleaningService)?
    private var state: AppState = .idle
    private var transcriptionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var lastHotkeyTime = DispatchTime(uptimeNanoseconds: 0)

    init(overlay: OverlayPanel, recorder: AudioRecorder, transcriptionService: any TranscriptionService, textCleaner: (any TextCleaningService)?) {
        self.overlay = overlay
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.textCleaner = textCleaner
    }

    func hotkeyPressed() {
        let now = DispatchTime.now()
        let delta = now.uptimeNanoseconds - lastHotkeyTime.uptimeNanoseconds
        print("[\(logTS())] [AppController] hotkeyPressed() called, state=\(state), delta=\(delta)ns")
        guard delta > 300_000_000 else {
            print("[\(logTS())] [AppController] DEBOUNCED — skipping (delta \(delta)ns < 300ms)")
            return
        }
        lastHotkeyTime = now

        switch state {
        case .idle:
            startRecording()
        case .starting:
            print("[\(logTS())] [AppController] Session still starting, please wait...")
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            print("[\(logTS())] [AppController] Transcription in progress, please wait...")
        }
    }

    private func startRecording() {
        print("[\(logTS())] [AppController] State: \(state) → starting")
        state = .starting
        overlay.show()

        do {
            try recorder.start { [weak self] in
                guard let self = self, self.state == .starting else { return }
                print("[\(logTS())] [AppController] Session ready — State: starting → recording")
                self.state = .recording
            }
            print("[\(logTS())] [AppController] recorder.start() returned (session starting in background)")
        } catch {
            print("[\(logTS())] [AppController] Recording error:", error)
            state = .idle
            handleError("Mic error: \(error)")
            return
        }
    }

    private func stopRecordingAndTranscribe() {
        print("[\(logTS())] [AppController] State: \(state) → transcribing")
        state = .transcribing

        overlay.updateTranscription("Transcribing...")
        overlay.updateStatus("Transcribing...")
        overlay.stopWaveform()

        let audioData = recorder.stop()
        print("[\(logTS())] [AppController] Audio data from recorder: \(audioData.count) bytes")

        guard !audioData.isEmpty else {
            print("[\(logTS())] [AppController] ERROR: No audio captured — aborting transcription")
            handleError("No audio captured")
            return
        }

        let sampleRate = recorder.sampleRate
        print("[\(logTS())] [AppController] Using sample rate: \(sampleRate) Hz")
        let overlay = self.overlay
        let transcriptionService = self.transcriptionService
        let textCleaner = self.textCleaner

        transcriptionTask = Task { @MainActor [weak self] in
            defer { self?.timeoutTask?.cancel() }
            do {
                let rawText = try await transcriptionService.transcribe(
                    audioData: audioData,
                    sampleRateHz: sampleRate
                )

                guard !Task.isCancelled else { return }

                print("Transcription result:", rawText)

                var finalText = rawText
                if let textCleaner = textCleaner {
                    overlay.updateStatus("Cleaning up...")
                    do {
                        finalText = try await textCleaner.clean(rawText: rawText)
                        print("Cleaned text:", finalText)
                    } catch {
                        print("Text cleanup failed (using raw text):", error)
                    }
                }

                guard !Task.isCancelled else { return }

                overlay.updateTranscription(finalText)
                overlay.updateStatus("Done!")

                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                overlay.hide()
                TextInjector.inject(text: finalText)
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
