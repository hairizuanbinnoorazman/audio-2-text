import AVFoundation

enum RecorderError: Error, CustomStringConvertible {
    case noInputAvailable
    case engineStartFailed(Error)

    var description: String {
        switch self {
        case .noInputAvailable:
            return "No audio input device available"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        }
    }
}

/// Thread-safe buffer for accumulating PCM data from the audio tap.
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
    private let engine = AVAudioEngine()
    private let pcmBuffer = LockedData()
    private var isRunning = false
    private(set) var sampleRate: Int = 48000
    private var firstBufferLogged = false

    func start(onReady: @escaping () -> Void) throws {
        print("[\(logTS())] [AudioRecorder] Starting AVAudioEngine capture...")
        guard !isRunning else {
            print("[\(logTS())] [AudioRecorder] WARNING: start() called while already running")
            return
        }

        pcmBuffer.reset()
        firstBufferLogged = false

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else {
            throw RecorderError.noInputAvailable
        }

        sampleRate = Int(hwFormat.sampleRate)
        print("[\(logTS())] [AudioRecorder] Input format: \(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch")

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            let pcmData = self.convertToInt16Mono(buffer: buffer)
            if !self.firstBufferLogged {
                self.firstBufferLogged = true
                print("[\(logTS())] [AudioRecorder] First audio buffer received (\(pcmData.count) bytes)")
            }
            self.pcmBuffer.append(pcmData)
        }

        engine.prepare()

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecorderError.engineStartFailed(error)
        }

        isRunning = true
        print("[\(logTS())] [AudioRecorder] AVAudioEngine started successfully")

        DispatchQueue.main.async {
            onReady()
        }
    }

    func stop() -> Data {
        print("[\(logTS())] [AudioRecorder] Stopping AVAudioEngine...")
        guard isRunning else {
            print("[\(logTS())] [AudioRecorder] WARNING: stop() called while not running")
            return Data()
        }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let data = pcmBuffer.takeData()
        print("[\(logTS())] [AudioRecorder] Total PCM data accumulated: \(data.count) bytes")
        if data.isEmpty {
            print("[\(logTS())] [AudioRecorder] WARNING: No audio data captured")
        }
        return data
    }

    /// Convert non-interleaved Float32 from AVAudioEngine tap to Int16 mono PCM.
    private func convertToInt16Mono(buffer: AVAudioPCMBuffer) -> Data {
        guard let floatData = buffer.floatChannelData else { return Data() }
        let frameCount = Int(buffer.frameLength)
        var data = Data(count: frameCount * 2)
        data.withUnsafeMutableBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            let channel0 = floatData[0]
            for i in 0..<frameCount {
                let sample = max(-1.0, min(1.0, channel0[i]))
                int16Ptr[i] = Int16(sample * Float(Int16.max))
            }
        }
        return data
    }
}
