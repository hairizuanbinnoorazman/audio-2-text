import AWSBedrockRuntime
import Foundation

enum TextCleanerError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(String)
    case invalidResponse

    var description: String {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Required environment variable \(name) is not set"
        case .invalidResponse:
            return "Failed to parse Bedrock response"
        }
    }
}

final class TextCleaner: @unchecked Sendable {
    private let client: BedrockRuntimeClient

    init() throws {
        let env = ProcessInfo.processInfo.environment
        guard let region = env["AWS_REGION"] else {
            throw TextCleanerError.missingEnvironmentVariable("AWS_REGION")
        }
        self.client = try BedrockRuntimeClient(region: region)
    }

    func clean(rawText: String) async throws -> String {
        let systemPrompt = """
            You are a text cleanup assistant. Your job is to clean up raw speech-to-text transcriptions. \
            Remove verbal fillers (umm, uh, um, like, you know, so, basically, actually, I mean, right, okay so). \
            Fix grammar and punctuation. \
            Preserve the speaker's original intent and meaning exactly. \
            Return only the cleaned text with no preamble, explanation, or quotes.
            """

        let requestBody: [String: Any] = [
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": rawText]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        let input = InvokeModelInput(
            body: jsonData,
            contentType: "application/json",
            modelId: "global.anthropic.claude-haiku-4-5-20251001-v1:0"
        )

        let response = try await client.invokeModel(input: input)

        guard let responseBody = response.body,
              let json = try JSONSerialization.jsonObject(with: responseBody) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw TextCleanerError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
