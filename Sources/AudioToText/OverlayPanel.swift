import AppKit

final class OverlayPanel {
    private let panel: NSPanel
    private let transcriptionField: NSTextField
    private let statusField: NSTextField
    private let waveformView: WaveformView

    init() {
        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 120

        // Position at bottom center of main screen
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = screenFrame.origin.x + (screenFrame.size.width - panelWidth) / 2.0
        let y = screenFrame.origin.y + 40

        let panelRect = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        // Content view with rounded dark background
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        contentView.layer?.cornerRadius = 16.0
        contentView.layer?.masksToBounds = true
        panel.contentView = contentView

        // Transcription text field
        transcriptionField = NSTextField(frame: NSRect(x: 20, y: 40, width: panelWidth - 120, height: 50))
        transcriptionField.isBezeled = false
        transcriptionField.drawsBackground = false
        transcriptionField.isEditable = false
        transcriptionField.isSelectable = false
        transcriptionField.textColor = .white
        transcriptionField.font = NSFont.systemFont(ofSize: 16.0, weight: .medium)
        transcriptionField.stringValue = "Listening..."
        transcriptionField.alignment = .left
        transcriptionField.lineBreakMode = .byTruncatingTail
        contentView.addSubview(transcriptionField)

        // Status label
        statusField = NSTextField(frame: NSRect(x: 20, y: 15, width: 200, height: 20))
        statusField.isBezeled = false
        statusField.drawsBackground = false
        statusField.isEditable = false
        statusField.isSelectable = false
        statusField.textColor = NSColor(white: 0.6, alpha: 1.0)
        statusField.font = NSFont.systemFont(ofSize: 12.0)
        statusField.stringValue = "Dictating..."
        contentView.addSubview(statusField)

        // Waveform view (right side)
        waveformView = WaveformView(frame: NSRect(x: panelWidth - 90, y: 20, width: 70, height: 80))
        contentView.addSubview(waveformView)

        // Start hidden
        panel.orderOut(nil)
    }

    func show() {
        transcriptionField.stringValue = "Listening..."
        statusField.stringValue = "Dictating..."
        panel.orderFrontRegardless()
        waveformView.startAnimating()
    }

    func hide() {
        waveformView.stopAnimating()
        panel.orderOut(nil)
    }

    func updateTranscription(_ text: String) {
        transcriptionField.stringValue = text
    }

    func updateStatus(_ text: String) {
        statusField.stringValue = text
    }

    func stopWaveform() {
        waveformView.stopAnimating()
    }
}
