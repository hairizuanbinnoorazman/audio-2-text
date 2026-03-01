import AVFoundation
import Foundation

enum RecorderError: Error, CustomStringConvertible {
    case invalidFormat

    var description: String {
        switch self {
        case .invalidFormat:
            return "Failed to create audio format"
        }
    }
}

/// Thread-safe buffer for accumulating PCM data from the CoreAudio callback thread.
private final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        data = Data()
        lock.unlock()
    }

    func takeData() -> Data {
        lock.lock()
        let result = data
        data = Data()
        lock.unlock()
        return result
    }
}

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private let pcmBuffer = LockedData()
    private(set) var sampleRate: Int = 0

    func start() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        sampleRate = Int(hwFormat.sampleRate)
        if sampleRate == 0 {
            print("Hardware sample rate is 0, falling back to 48000")
            sampleRate = 48000
        }

        print("Recording at native sample rate \(sampleRate) Hz")

        guard let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.invalidFormat
        }

        pcmBuffer.reset()

        let buffer = pcmBuffer
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { pcmBuf, _ in
            guard let floatData = pcmBuf.floatChannelData?[0] else { return }
            let frameCount = Int(pcmBuf.frameLength)

            // Convert Float32 samples to Int16 PCM
            var int16Data = Data(count: frameCount * MemoryLayout<Int16>.size)
            int16Data.withUnsafeMutableBytes { rawPtr in
                let int16Ptr = rawPtr.bindMemory(to: Int16.self)
                for i in 0..<frameCount {
                    var sample = floatData[i]
                    sample = max(-1.0, min(1.0, sample))
                    int16Ptr[i] = Int16(sample * 32767.0)
                }
            }
            buffer.append(int16Data)
        }

        try engine.start()
        self.engine = engine
    }

    func stop() -> Data {
        if let engine = engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        return pcmBuffer.takeData()
    }
}
