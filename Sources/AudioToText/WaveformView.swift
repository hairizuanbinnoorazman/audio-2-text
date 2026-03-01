import AppKit

final class WaveformView: NSView {
    private var barHeights: [CGFloat] = Array(repeating: 0.2, count: 12)
    private var animationTimer: Timer?
    private var animating = false

    func startAnimating() {
        guard !animating else { return }
        animating = true
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopAnimating() {
        animating = false
        animationTimer?.invalidate()
        animationTimer = nil
        barHeights = Array(repeating: 0.2, count: 12)
        needsDisplay = true
    }

    private func tick() {
        for i in 0..<12 {
            let target = 0.2 + CGFloat.random(in: 0..<0.8)
            barHeights[i] += (target - barHeights[i]) * 0.3
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let barWidth: CGFloat = 3.0
        let gap: CGFloat = 3.0
        let totalWidth = CGFloat(12) * barWidth + CGFloat(11) * gap
        let startX = (bounds.size.width - totalWidth) / 2.0
        let maxHeight = bounds.size.height * 0.8
        let centerY = bounds.size.height / 2.0

        NSColor(white: 1.0, alpha: 0.7).setFill()

        for i in 0..<12 {
            let h = maxHeight * barHeights[i]
            let x = startX + CGFloat(i) * (barWidth + gap)
            let y = centerY - h / 2.0
            let bar = NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: barWidth, height: h),
                xRadius: 1.5,
                yRadius: 1.5
            )
            bar.fill()
        }
    }
}
