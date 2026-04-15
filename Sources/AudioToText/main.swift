import AppKit

MicPermission.ensureAccess()

let backend = ProcessInfo.processInfo.environment["TRANSCRIPTION_BACKEND"] ?? "transcribe"
print("Transcription backend: \(backend)")

let transcriptionService: any TranscriptionService
let textCleaner: (any TextCleaningService)?

switch backend {
case "nova-sonic":
    print("Initializing Nova Sonic transcriber...")
    do {
        transcriptionService = try NovaSonicTranscriber()
    } catch {
        fputs("Failed to initialize Nova Sonic transcriber: \(error)\n", stderr)
        exit(1)
    }
    print("Nova Sonic transcriber ready.")
    textCleaner = nil

case "transcribe":
    print("Initializing AWS Transcribe client...")
    do {
        transcriptionService = try Transcriber()
    } catch {
        fputs("Failed to initialize transcriber: \(error)\n", stderr)
        exit(1)
    }
    print("AWS Transcribe client ready.")

    print("Initializing Bedrock text cleaner...")
    do {
        textCleaner = try TextCleaner()
    } catch {
        fputs("Failed to initialize text cleaner: \(error)\n", stderr)
        exit(1)
    }
    print("Bedrock text cleaner ready.")

case "google":
    print("Initializing Google Speech transcriber...")
    do {
        transcriptionService = try GoogleSpeechTranscriber()
    } catch {
        fputs("Failed to initialize Google Speech transcriber: \(error)\n", stderr)
        exit(1)
    }
    print("Google Speech transcriber ready.")

    print("Initializing Gemini text cleaner...")
    do {
        textCleaner = try GeminiTextCleaner()
    } catch {
        fputs("Failed to initialize Gemini text cleaner: \(error)\n", stderr)
        exit(1)
    }
    print("Gemini text cleaner ready.")

default:
    fputs("Unknown TRANSCRIPTION_BACKEND: '\(backend)'. Use 'transcribe', 'nova-sonic', or 'google'.\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let overlay = OverlayPanel()
let recorder = AudioRecorder()
let controller = AppController(
    overlay: overlay,
    recorder: recorder,
    transcriptionService: transcriptionService,
    textCleaner: textCleaner
)

let hotkeyManager = HotkeyManager {
    controller.hotkeyPressed()
}

guard hotkeyManager.start() else {
    fputs("Failed to create event tap.\n", stderr)
    fputs("Grant Input Monitoring permission:\n", stderr)
    fputs("  System Settings > Privacy & Security > Input Monitoring\n", stderr)
    exit(1)
}

print("Listening for Ctrl+Option+K... Press the combo to toggle overlay.")
print("Press Ctrl+C to quit.")

app.run()
