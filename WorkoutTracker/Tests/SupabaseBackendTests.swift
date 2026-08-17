import XCTest
@testable import WorkoutTracker

/// Transport double: captures the request, returns a canned response.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var status = 200
    var responseData = Data("[]".utf8)
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!
        return (responseData, response)
    }
}

final class SupabaseBackendTests: XCTestCase {
    var transport: MockTransport!
    var backend: SupabaseBackend!
    let base = URL(string: "https://example.supabase.co")!

    override func setUp() {
        super.setUp()
        transport = MockTransport()
        backend = SupabaseBackend(baseURL: base, anonKey: "test-key", transport: transport)
    }

    var lastRequest: URLRequest { transport.requests.last! }

    // MARK: - Request building

    func testFetchRequest() async throws {
        _ = try await backend.fetchWorkouts()

        XCTAssertEqual(lastRequest.httpMethod, "GET")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/workouts?select=*&order=date.asc")
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: "apikey"), "test-key")
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testInsertRequest() async throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let workout = Workout(id: id, name: "Bench", duration: 3600,
                              exercises: [Exercise(name: "Bench press", sets: 4, reps: 8, weight: 155)])

        try await backend.insert(workout)

        XCTAssertEqual(lastRequest.httpMethod, "POST")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/workouts")
        let body = try JSONSerialization.jsonObject(with: lastRequest.httpBody!) as! [String: Any]
        XCTAssertEqual(body["id"] as? String, id.uuidString)
        XCTAssertEqual(body["name"] as? String, "Bench")
        XCTAssertEqual(body["duration"] as? Double, 3600)
        XCTAssertEqual((body["exercises"] as? [[String: Any]])?.count, 1)
        // Dates must go out as ISO8601 so timestamptz accepts them.
        XCTAssertTrue((body["date"] as! String).hasSuffix("Z"))
    }

    func testUpdateRequestFiltersById() async throws {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        try await backend.update(Workout(id: id, name: "Renamed", duration: 60))

        XCTAssertEqual(lastRequest.httpMethod, "PATCH")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/workouts?id=eq.\(id.uuidString)")
        XCTAssertNotNil(lastRequest.httpBody)
    }

    func testDeleteRequestFiltersById() async throws {
        let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        try await backend.delete(id: id)

        XCTAssertEqual(lastRequest.httpMethod, "DELETE")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/workouts?id=eq.\(id.uuidString)")
    }

    func testDeleteAllRequest() async throws {
        try await backend.deleteAll()

        XCTAssertEqual(lastRequest.httpMethod, "DELETE")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/workouts?id=not.is.null")
    }

    // MARK: - Response handling

    func testFetchDecodesRows() async throws {
        transport.responseData = Data("""
        [{"id":"11111111-1111-1111-1111-111111111111",
          "date":"2026-08-17T00:52:33.123456+00:00",
          "name":"Squat Day","duration":3600,
          "exercises":[{"id":"22222222-2222-2222-2222-222222222222",
                        "name":"Back squat","sets":3,"reps":5,"weight":145}],
          "created_at":"2026-08-17T00:52:33+00:00"}]
        """.utf8)

        let workouts = try await backend.fetchWorkouts()

        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts[0].name, "Squat Day")
        XCTAssertEqual(workouts[0].exercises[0].weight, 145)
    }

    func testDateParsingAcceptsBothPrecisions() throws {
        XCTAssertNoThrow(try SupabaseBackend.parseDate("2026-08-17T00:52:33.123+00:00"))
        XCTAssertNoThrow(try SupabaseBackend.parseDate("2026-08-17T00:52:33+00:00"))
        XCTAssertNoThrow(try SupabaseBackend.parseDate("2026-08-17T00:52:33Z"))
        XCTAssertThrowsError(try SupabaseBackend.parseDate("yesterday-ish"))
    }

    func testNon2xxThrowsWithBody() async {
        transport.status = 401
        transport.responseData = Data(#"{"message":"JWT expired"}"#.utf8)

        do {
            _ = try await backend.fetchWorkouts()
            XCTFail("expected throw")
        } catch let error as SupabaseError {
            XCTAssertEqual(error, .badStatus(code: 401, body: #"{"message":"JWT expired"}"#))
            XCTAssertEqual(error.errorDescription,
                           #"Supabase returned 401: {"message":"JWT expired"}"#)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testErrorDescriptions() {
        XCTAssertEqual(SupabaseError.notHTTP.errorDescription, "Response was not HTTP")
    }

    func testDefaultConfigPointsAtMiloProject() {
        let backend = SupabaseBackend()
        XCTAssertEqual(backend.baseURL.absoluteString, "https://dytsryksedogxymdgdue.supabase.co")
        XCTAssertFalse(backend.anonKey.isEmpty)
    }

    // MARK: - URLSession transport conformance (stubbed URLProtocol, no network)

    func testURLSessionTransportReturnsHTTPResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        URLProtocolStub.result = (Data("[]".utf8), 200)

        let (data, response) = try await session.send(
            URLRequest(url: URL(string: "https://stubbed.test/rest/v1/workouts")!))

        XCTAssertEqual(data, Data("[]".utf8))
        XCTAssertEqual(response.statusCode, 200)
    }

    func testURLSessionTransportRejectsNonHTTPResponse() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        URLProtocolStub.sendNonHTTPResponse = true
        defer { URLProtocolStub.sendNonHTTPResponse = false }

        do {
            _ = try await session.send(
                URLRequest(url: URL(string: "https://stubbed.test/x")!))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SupabaseError, .notHTTP)
        }
    }
}

/// Serves canned responses so the URLSession extension is exercised offline.
final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var result: (data: Data, status: Int) = (Data(), 200)
    nonisolated(unsafe) static var sendNonHTTPResponse = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response: URLResponse
        if Self.sendNonHTTPResponse {
            response = URLResponse(url: request.url!, mimeType: nil,
                                   expectedContentLength: 0, textEncodingName: nil)
        } else {
            response = HTTPURLResponse(
                url: request.url!, statusCode: Self.result.status,
                httpVersion: nil, headerFields: nil)!
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
