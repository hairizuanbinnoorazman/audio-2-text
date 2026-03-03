import AppKit

MicPermission.ensureAccess()

print("Initializing AWS Transcribe client...")
let transcriber: Transcriber
do {
    transcriber = try Transcriber()
} catch {
    fputs("Failed to initialize transcriber: \(error)\n", stderr)
    exit(1)
}
print("AWS Transcribe client ready.")

print("Initializing Bedrock text cleaner...")
let textCleaner: TextCleaner
do {
    textCleaner = try TextCleaner()
} catch {
    fputs("Failed to initialize text cleaner: \(error)\n", stderr)
    exit(1)
}
print("Bedrock text cleaner ready.")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let overlay = OverlayPanel()
let recorder = AudioRecorder()
let controller = AppController(
    overlay: overlay,
    recorder: recorder,
    transcriber: transcriber,
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
