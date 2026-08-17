import XCTest
@testable import NarratorKit

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OpenAIClientTests: XCTestCase {
    func makeClient() -> OpenAIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return OpenAIClient(
            config: EndpointConfig(baseURL: URL(string: "https://mock.test/v1")!,
                                   token: "sk-test", model: "gpt-test"),
            session: URLSession(configuration: cfg))
    }

    func ok(_ body: String, url: URL) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200,
                         httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    func testListModelsParsesAndSorts() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/models")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            return self.ok(#"{"data":[{"id":"zeta"},{"id":"alpha"}]}"#, url: req.url!)
        }
        let models = try await makeClient().listModels()
        XCTAssertEqual(models, ["alpha", "zeta"])
    }

    func testStreamChatConcatenatesDeltas() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"The "}}]}

        data: {"choices":[{"delta":{"content":"dark."}}]}

        data: [DONE]

        """
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/chat/completions")
            return self.ok(sse, url: req.url!)
        }
        var seen: [String] = []
        let lock = NSLock()
        let full = try await makeClient().streamChat(
            messages: [ChatMessage(role: "user", content: "go")],
            temperature: 0.7, maxTokens: 50) { delta in
                lock.lock(); seen.append(delta); lock.unlock()
            }
        XCTAssertEqual(full, "The dark.")
        XCTAssertEqual(seen, ["The ", "dark."])
    }

    func testHTTPErrorSurfacesStatus() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401,
                             httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await makeClient().listModels()
            XCTFail("expected throw")
        } catch let e as OpenAIError {
            XCTAssertEqual(e, .http(401))
        } catch { XCTFail("wrong error \(error)") }
    }
}
