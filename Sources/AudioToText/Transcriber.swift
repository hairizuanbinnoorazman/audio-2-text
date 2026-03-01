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
}
