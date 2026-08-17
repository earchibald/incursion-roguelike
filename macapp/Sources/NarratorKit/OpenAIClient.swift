// See the Incursion LICENSE file for copyright information.
//
// A minimal OpenAI-compatible chat client: /v1/models for discovery and
// streaming /v1/chat/completions over SSE. Works against OpenAI, vLLM,
// LM Studio, and Ollama. The token appears only in the Authorization
// header; it is never logged.
import Foundation

public struct EndpointConfig: Equatable {
    public var baseURL: URL
    public var token: String
    public var model: String

    public init(baseURL: URL, token: String, model: String) {
        self.baseURL = baseURL
        self.token = token
        self.model = model
    }
}

public enum OpenAIError: Error, Equatable {
    case http(Int), badResponse, emptyReply
}

public final class OpenAIClient {
    private let config: EndpointConfig
    private let session: URLSession

    public init(config: EndpointConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    private func request(path: String) -> URLRequest {
        var req = URLRequest(url: config.baseURL.appendingPathComponent(path))
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60
        return req
    }

    public func listModels() async throws -> [String] {
        struct ModelList: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }
        let (data, resp) = try await session.data(for: request(path: "models"))
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard http.statusCode == 200 else { throw OpenAIError.http(http.statusCode) }
        return try JSONDecoder().decode(ModelList.self, from: data)
            .data.map(\.id).sorted()
    }

    public func streamChat(messages: [ChatMessage], temperature: Double,
                           maxTokens: Int,
                           onDelta: @escaping @Sendable (String) -> Void)
                           async throws -> String {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta
            }
            let choices: [Choice]
        }
        var req = request(path: "chat/completions")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = WireJSON.chatBody(model: config.model, messages: messages,
                                         temperature: temperature,
                                         maxTokens: maxTokens, stream: true)
        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard http.statusCode == 200 else { throw OpenAIError.http(http.statusCode) }
        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let d = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(Chunk.self, from: d),
                  let delta = chunk.choices.first?.delta.content,
                  !delta.isEmpty else { continue }
            full += delta
            onDelta(delta)
        }
        guard !full.isEmpty else { throw OpenAIError.emptyReply }
        return full
    }

    /// One tiny round trip; returns the latency for the settings window.
    public func testConnection() async throws -> TimeInterval {
        let start = Date()
        _ = try await streamChat(
            messages: [ChatMessage(role: "user", content: "Reply with the single word: ready")],
            temperature: 0, maxTokens: 4, onDelta: { _ in })
        return Date().timeIntervalSince(start)
    }
}
