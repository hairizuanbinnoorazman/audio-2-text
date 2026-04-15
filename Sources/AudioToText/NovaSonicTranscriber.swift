import AWSBedrockRuntime
import Foundation

enum NovaSonicError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(String)
    case noSpeechDetected
    case streamError(String)

    var description: String {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Required environment variable \(name) is not set"
        case .noSpeechDetected:
            return "No speech detected in audio"
        case .streamError(let msg):
            return "Nova Sonic stream error: \(msg)"
        }
    }
}

final class NovaSonicTranscriber: @unchecked Sendable, TranscriptionService {
    private let client: BedrockRuntimeClient
    private let modelId = "amazon.nova-sonic-v1:0"

    init() throws {
        let env = ProcessInfo.processInfo.environment
        for key in ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION"] {
            guard env[key] != nil else {
                throw NovaSonicError.missingEnvironmentVariable(key)
            }
        }
        let region = env["AWS_REGION"]!
        self.client = try BedrockRuntimeClient(region: region)
    }

    func transcribe(audioData: Data, sampleRateHz: Int) async throws -> String {
        let resampledAudio = resampleTo16kHz(audioData: audioData, fromSampleRate: sampleRateHz)
        print("[\(logTS())] [NovaSonic] Resampled audio: \(audioData.count) bytes @ \(sampleRateHz)Hz → \(resampledAudio.count) bytes @ 16000Hz")

        let promptName = UUID().uuidString
        let systemContentName = UUID().uuidString
        let audioContentName = UUID().uuidString

        let inputStream = AsyncThrowingStream<BedrockRuntimeClientTypes.InvokeModelWithBidirectionalStreamInput, Error> { continuation in
            // 1. Session start
            let sessionStartEvent = self.buildEvent([
                "event": [
                    "sessionStart": [
                        "inferenceConfiguration": [
                            "maxTokens": 1024,
                            "topP": 0.95,
                            "temperature": 0.1
                        ]
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: sessionStartEvent)))

            // 2. Prompt start
            let promptStartEvent = self.buildEvent([
                "event": [
                    "promptStart": [
                        "promptName": promptName,
                        "textOutputConfiguration": [
                            "mediaType": "text/plain"
                        ],
                        "audioOutputConfiguration": [
                            "mediaType": "audio/lpcm",
                            "sampleRateHertz": 24000,
                            "sampleSizeBits": 16,
                            "channelCount": 1,
                            "voiceId": "matthew",
                            "encoding": "base64",
                            "audioType": "SPEECH"
                        ]
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: promptStartEvent)))

            // 3. System prompt: contentStart → textInput → contentEnd
            let systemContentStart = self.buildEvent([
                "event": [
                    "contentStart": [
                        "promptName": promptName,
                        "contentName": systemContentName,
                        "type": "TEXT",
                        "interactive": false,
                        "role": "SYSTEM",
                        "textInputConfiguration": [
                            "mediaType": "text/plain"
                        ]
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: systemContentStart)))

            let systemPrompt = """
                You are a speech-to-text transcription assistant. You receive audio input and must transcribe it accurately.

                Rules:
                - The audio is ALWAYS a speech recording. Transcribe it faithfully.
                - Remove verbal fillers: umm, uh, um, like, you know, so, basically, actually, I mean, right, okay so.
                - Fix grammar and punctuation.
                - Preserve the speaker's original words and meaning exactly — only remove fillers and fix mechanics.
                - Output ONLY the cleaned transcription text. Nothing else.
                """
            let systemTextInput = self.buildEvent([
                "event": [
                    "textInput": [
                        "promptName": promptName,
                        "contentName": systemContentName,
                        "content": systemPrompt
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: systemTextInput)))

            let systemContentEnd = self.buildEvent([
                "event": [
                    "contentEnd": [
                        "promptName": promptName,
                        "contentName": systemContentName
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: systemContentEnd)))

            // 4. Audio content start
            let audioContentStart = self.buildEvent([
                "event": [
                    "contentStart": [
                        "promptName": promptName,
                        "contentName": audioContentName,
                        "type": "AUDIO",
                        "interactive": true,
                        "role": "USER",
                        "audioInputConfiguration": [
                            "mediaType": "audio/lpcm",
                            "sampleRateHertz": 16000,
                            "sampleSizeBits": 16,
                            "channelCount": 1,
                            "audioType": "SPEECH",
                            "encoding": "base64"
                        ]
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: audioContentStart)))

            // 5. Send audio chunks as base64
            let chunkSize = 1024  // bytes of raw audio per chunk (512 samples = 32ms at 16kHz)
            var offset = 0
            while offset < resampledAudio.count {
                let end = min(offset + chunkSize, resampledAudio.count)
                let chunk = resampledAudio.subdata(in: offset..<end)
                let base64Chunk = chunk.base64EncodedString()

                let audioInputEvent = self.buildEvent([
                    "event": [
                        "audioInput": [
                            "promptName": promptName,
                            "contentName": audioContentName,
                            "content": base64Chunk
                        ]
                    ]
                ])
                continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: audioInputEvent)))
                offset = end
            }
            print("[\(logTS())] [NovaSonic] Sent \(resampledAudio.count / chunkSize + 1) audio chunks")

            // 6. Audio content end
            let audioContentEnd = self.buildEvent([
                "event": [
                    "contentEnd": [
                        "promptName": promptName,
                        "contentName": audioContentName
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: audioContentEnd)))

            // 7. Prompt end
            let promptEnd = self.buildEvent([
                "event": [
                    "promptEnd": [
                        "promptName": promptName
                    ]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: promptEnd)))

            // 8. Session end
            let sessionEnd = self.buildEvent([
                "event": [
                    "sessionEnd": [:] as [String: String]
                ]
            ])
            continuation.yield(.chunk(BedrockRuntimeClientTypes.BidirectionalInputPayloadPart(bytes: sessionEnd)))

            continuation.finish()
        }

        let input = InvokeModelWithBidirectionalStreamInput(
            body: inputStream,
            modelId: modelId
        )

        print("[\(logTS())] [NovaSonic] Starting bidirectional stream...")
        let output = try await client.invokeModelWithBidirectionalStream(input: input)

        // Collect USER-role text output from the response stream
        var userTranscripts: [String: String] = [:]  // contentId → accumulated text
        var userContentIds: Set<String> = []

        if let responseStream = output.body {
            for try await event in responseStream {
                switch event {
                case .chunk(let payload):
                    guard let bytes = payload.bytes else { continue }
                    guard let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                          let eventData = json["event"] as? [String: Any] else { continue }

                    if let contentStart = eventData["contentStart"] as? [String: Any] {
                        let role = contentStart["role"] as? String
                        let type = contentStart["type"] as? String
                        let contentId = contentStart["contentId"] as? String
                        if role == "USER", type == "TEXT", let id = contentId {
                            userContentIds.insert(id)
                            userTranscripts[id] = ""
                            print("[\(logTS())] [NovaSonic] User transcription content started: \(id)")
                        }
                    } else if let textOutput = eventData["textOutput"] as? [String: Any] {
                        let role = textOutput["role"] as? String
                        let contentId = textOutput["contentId"] as? String
                        let content = textOutput["content"] as? String
                        if role == "USER", let id = contentId, userContentIds.contains(id), let text = content {
                            userTranscripts[id] = text
                        }
                    } else if let contentEnd = eventData["contentEnd"] as? [String: Any] {
                        let contentId = contentEnd["contentId"] as? String
                        if let id = contentId, userContentIds.contains(id) {
                            print("[\(logTS())] [NovaSonic] User transcription content ended: \(id)")
                        }
                    }
                case .sdkUnknown:
                    break
                }
            }
        }

        // Join all user transcription texts
        let text = userTranscripts.values
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("[\(logTS())] [NovaSonic] Transcription result: \(text)")

        if text.isEmpty {
            throw NovaSonicError.noSpeechDetected
        }
        return text
    }

    // MARK: - Helpers

    private func buildEvent(_ dict: [String: Any]) -> Data {
        return (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }

    private func resampleTo16kHz(audioData: Data, fromSampleRate: Int) -> Data {
        guard fromSampleRate != 16000 else { return audioData }
        let inputSamples = audioData.count / 2  // Int16 = 2 bytes per sample
        let ratio = Double(fromSampleRate) / 16000.0
        let outputSamples = Int(Double(inputSamples) / ratio)
        var output = Data(count: outputSamples * 2)
        audioData.withUnsafeBytes { inBuf in
            let inPtr = inBuf.bindMemory(to: Int16.self)
            output.withUnsafeMutableBytes { outBuf in
                let outPtr = outBuf.bindMemory(to: Int16.self)
                for i in 0..<outputSamples {
                    let srcIndex = min(Int(Double(i) * ratio), inputSamples - 1)
                    outPtr[i] = inPtr[srcIndex]
                }
            }
        }
        return output
    }
}
