import Foundation

enum GoogleSpeechError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(String)
    case noSpeechDetected
    case apiError(Int, String)
    case invalidResponse

    var description: String {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Required environment variable \(name) is not set"
        case .noSpeechDetected:
            return "No speech detected in audio"
        case .apiError(let code, let message):
            return "Google Speech API error (\(code)): \(message)"
        case .invalidResponse:
            return "Failed to parse Google Speech API response"
        }
    }
}

final class GoogleSpeechTranscriber: @unchecked Sendable, TranscriptionService {
    private let apiKey: String

    init() throws {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] else {
            throw GoogleSpeechError.missingEnvironmentVariable("GOOGLE_API_KEY")
        }
        self.apiKey = apiKey
    }

    func transcribe(audioData: Data, sampleRateHz: Int) async throws -> String {
        print("[\(logTS())] [GoogleSpeech] Sending \(audioData.count) bytes @ \(sampleRateHz)Hz")

        let requestBody: [String: Any] = [
            "config": [
                "encoding": "LINEAR16",
                "sampleRateHertz": sampleRateHz,
                "languageCode": "en-US"
            ],
            "audio": [
                "content": audioData.base64EncodedString()
            ]
        ]

        let url = URL(string: "https://speech.googleapis.com/v1/speech:recognize?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            let errorMessage: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                errorMessage = message
            } else {
                errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw GoogleSpeechError.apiError(httpResponse.statusCode, errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleSpeechError.invalidResponse
        }

        var transcripts: [String] = []
        if let results = json["results"] as? [[String: Any]] {
            for result in results {
                if let alternatives = result["alternatives"] as? [[String: Any]],
                   let firstAlt = alternatives.first,
                   let transcript = firstAlt["transcript"] as? String,
                   !transcript.isEmpty {
                    transcripts.append(transcript)
                }
            }
        }

        let text = transcripts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        print("[\(logTS())] [GoogleSpeech] Transcription result: \(text)")

        if text.isEmpty {
            throw GoogleSpeechError.noSpeechDetected
        }
        return text
    }
}
