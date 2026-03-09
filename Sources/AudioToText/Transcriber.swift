import AWSTranscribeStreaming
import Foundation

enum TranscriberError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(String)
    case noSpeechDetected

    var description: String {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Required environment variable \(name) is not set"
        case .noSpeechDetected:
            return "No speech detected in audio"
        }
    }
}

final class Transcriber: @unchecked Sendable {
    private let client: TranscribeStreamingClient

    init() throws {
        let env = ProcessInfo.processInfo.environment
        for key in ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION"] {
            guard env[key] != nil else {
                throw TranscriberError.missingEnvironmentVariable(key)
            }
        }
        let region = env["AWS_REGION"]!
        self.client = try TranscribeStreamingClient(region: region)
    }

    func transcribe(audioData: Data, sampleRateHz: Int) async throws -> String {
        let chunkSize = 16 * 1024 // 16KB

        let audioStream = AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> { continuation in
            var offset = 0
            while offset < audioData.count {
                let end = min(offset + chunkSize, audioData.count)
                let chunk = audioData.subdata(in: offset..<end)
                continuation.yield(.audioevent(TranscribeStreamingClientTypes.AudioEvent(audioChunk: chunk)))
                offset = end
            }
            continuation.finish()
        }

        let input = StartStreamTranscriptionInput(
            audioStream: audioStream,
            languageCode: .enUs,
            mediaEncoding: .pcm,
            mediaSampleRateHertz: sampleRateHz
        )

        let output = try await client.startStreamTranscription(input: input)

        var transcripts: [String] = []
        if let resultStream = output.transcriptResultStream {
            for try await event in resultStream {
                switch event {
                case .transcriptevent(let te):
                    for result in te.transcript?.results ?? [] {
                        guard !result.isPartial else { continue }
                        for alt in result.alternatives ?? [] {
                            if let text = alt.transcript, !text.isEmpty {
                                transcripts.append(text)
                            }
                        }
                    }
                case .sdkUnknown:
                    break
                }
            }
        }

        let text = transcripts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            throw TranscriberError.noSpeechDetected
        }
        return text
    }

    private let chunkDurationSeconds = 30.0
    private let largeAudioThresholdSeconds = 30.0

    func transcribeChunked(audioData: Data, sampleRateHz: Int) async throws -> String {
        let durationSeconds = Double(audioData.count) / Double(sampleRateHz * 2)

        guard durationSeconds > largeAudioThresholdSeconds else {
            return try await transcribe(audioData: audioData, sampleRateHz: sampleRateHz)
        }

        let bytesPerSecond = sampleRateHz * 2
        let chunkBytes = Int(chunkDurationSeconds) * bytesPerSecond
        // Align to Int16 (2-byte) boundary
        let alignedChunkBytes = (chunkBytes / 2) * 2

        var chunks: [(index: Int, data: Data)] = []
        var offset = 0
        var index = 0
        while offset < audioData.count {
            let end = min(offset + alignedChunkBytes, audioData.count)
            chunks.append((index: index, data: audioData.subdata(in: offset..<end)))
            offset = end
            index += 1
        }

        var results: [(index: Int, transcript: String)] = []
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for chunk in chunks {
                group.addTask {
                    do {
                        let text = try await self.transcribe(audioData: chunk.data, sampleRateHz: sampleRateHz)
                        return (chunk.index, text)
                    } catch TranscriberError.noSpeechDetected {
                        return (chunk.index, "")
                    }
                }
            }
            for try await result in group {
                results.append((index: result.0, transcript: result.1))
            }
        }

        results.sort { $0.index < $1.index }
        let combined = results.map { $0.transcript }.joined(separator: " ").trimmingCharacters(in: .whitespaces)

        if combined.isEmpty {
            throw TranscriberError.noSpeechDetected
        }
        return combined
    }
}
