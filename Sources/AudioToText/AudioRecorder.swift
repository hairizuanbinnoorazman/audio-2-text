import AVFoundation
import CoreMedia
import Foundation

enum RecorderError: Error, CustomStringConvertible {
    case noMicrophoneFound
    case sessionConfigurationFailed

    var description: String {
        switch self {
        case .noMicrophoneFound:
            return "No microphone device found"
        case .sessionConfigurationFailed:
            return "Failed to configure capture session"
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

final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private let pcmBuffer = LockedData()
    private let captureQueue = DispatchQueue(label: "audio.capture.queue")
    private(set) var sampleRate: Int = 48000
    private var channelCount: Int = 1
    private var formatDetected = false

    func start() throws {
        let session = AVCaptureSession()

        guard let mic = AVCaptureDevice.default(for: .audio) else {
            throw RecorderError.noMicrophoneFound
        }

        let input = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(input) else {
            throw RecorderError.sessionConfigurationFailed
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            throw RecorderError.sessionConfigurationFailed
        }
        session.addOutput(output)

        pcmBuffer.reset()
        formatDetected = false
        sampleRate = 48000
        channelCount = 1

        session.startRunning()
        self.captureSession = session
    }

    func stop() -> Data {
        captureSession?.stopRunning()
        captureSession = nil
        return pcmBuffer.takeData()
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if !formatDetected, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
            if let asbd = asbd {
                sampleRate = Int(asbd.mSampleRate)
                channelCount = max(1, Int(asbd.mChannelsPerFrame))
            }
            formatDetected = true
        }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return }

        let bufferCount = Int(audioBufferList.mNumberBuffers)
        guard bufferCount > 0 else { return }

        let buf = audioBufferList.mBuffers
        guard let rawPtr = buf.mData else { return }
        let floatPtr = rawPtr.assumingMemoryBound(to: Float32.self)
        let totalFloats = Int(buf.mDataByteSize) / MemoryLayout<Float32>.size
        let frameCount = totalFloats / channelCount

        var int16Data = Data(count: frameCount * MemoryLayout<Int16>.size)
        int16Data.withUnsafeMutableBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                var sample: Float
                if channelCount > 1 {
                    var sum: Float = 0
                    for ch in 0..<channelCount {
                        sum += floatPtr[i * channelCount + ch]
                    }
                    sample = sum / Float(channelCount)
                } else {
                    sample = floatPtr[i]
                }
                sample = max(-1.0, min(1.0, sample))
                int16Ptr[i] = Int16(sample * 32767.0)
            }
        }
        pcmBuffer.append(int16Data)
    }
}
