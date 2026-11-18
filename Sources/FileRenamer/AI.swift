import Foundation

// MARK: - Generic OpenAI-compatible client (works with OpenAI, Groq, OpenRouter, llama.cpp, ollama, ...)

enum AI {
    enum AIError: Error { case http(Int, String), badResponse }

    /// Send a text prompt (and optionally one base64 JPEG image) and return the reply.
    static func ask(_ p: Provider, prompt: String, imageB64: String? = nil) async throws -> String {
        guard let url = URL(string: p.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw AIError.badResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(p.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 90

        var messageContent: Any
        if let b64 = imageB64 {
            messageContent = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]]
            ]
        } else {
            messageContent = prompt
        }

        let body: [String: Any] = [
            "model": p.model,
            // Generous budget: reasoning models (e.g. Qwen3 thinking) burn
            // most of it on hidden reasoning before emitting the short answer.
            "max_tokens": 512,
            "messages": [["role": "user", "content": messageContent]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
