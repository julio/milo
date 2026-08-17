import XCTest
@testable import WorkoutTracker

final class MockRenameBackend: RenameBackend, @unchecked Sendable {
    var stored: [String: String] = [:]
    var failNext: Error?
    private(set) var calls: [String] = []

    private func check(_ call: String) throws {
        calls.append(call)
        if let error = failNext {
            failNext = nil
            throw error
        }
    }

    func fetchRenames() async throws -> [ExerciseRename] {
        try check("fetch")
        return stored.map { ExerciseRename(original: $0.key, custom: $0.value) }
    }

    func upsert(_ rename: ExerciseRename) async throws {
        try check("upsert")
        stored[rename.original] = rename.custom
    }

    func deleteRename(original: String) async throws {
        try check("delete")
        stored[original] = nil
    }
}

@MainActor
final class RenameStoreTests: XCTestCase {
    var backend: MockRenameBackend!
    var store: RenameStore!

    override func setUp() {
        super.setUp()
        backend = MockRenameBackend()
        store = RenameStore(backend: backend)
    }

    func testDisplayNameFallsBackToOriginal() {
        XCTAssertEqual(store.displayName(for: "Back squat"), "Back squat")
    }

    func testRefreshLoadsRenames() async {
        backend.stored = ["DB Romanian deadlift": "RDL"]

        await store.refresh()

        XCTAssertEqual(store.displayName(for: "DB Romanian deadlift"), "RDL")
        XCTAssertNil(store.errorMessage)
    }

    func testRenamePersistsAndApplies() async {
        await store.rename(original: "Back squat", to: "Squat")

        XCTAssertEqual(store.displayName(for: "Back squat"), "Squat")
        XCTAssertEqual(backend.stored["Back squat"], "Squat")
        XCTAssertEqual(backend.calls, ["upsert"])
    }

    func testRenameTrimsWhitespace() async {
        await store.rename(original: "Back squat", to: "  Squat  ")

        XCTAssertEqual(store.displayName(for: "Back squat"), "Squat")
    }

    func testEmptyNameClearsOverride() async {
        await store.rename(original: "Back squat", to: "Squat")
        await store.rename(original: "Back squat", to: "   ")

        XCTAssertEqual(store.displayName(for: "Back squat"), "Back squat")
        XCTAssertNil(backend.stored["Back squat"])
        XCTAssertEqual(backend.calls, ["upsert", "delete"])
    }

    func testRenamingBackToOriginalClearsOverride() async {
        await store.rename(original: "Back squat", to: "Squat")
        await store.rename(original: "Back squat", to: "Back squat")

        XCTAssertEqual(store.displayName(for: "Back squat"), "Back squat")
        XCTAssertNil(backend.stored["Back squat"])
    }

    func testRenameFailureKeepsOldNameAndSetsError() async {
        backend.failNext = TestError()

        await store.rename(original: "Back squat", to: "Squat")

        XCTAssertEqual(store.displayName(for: "Back squat"), "Back squat")
        XCTAssertEqual(store.errorMessage, "backend exploded")

        await store.refresh()
        XCTAssertNil(store.errorMessage)
    }

    func testDefaultInitUsesSupabaseBackend() {
        XCTAssertNotNil(RenameStore())
    }
}

final class SupabaseRenameBackendTests: XCTestCase {
    var transport: MockTransport!
    var backend: SupabaseBackend!

    override func setUp() {
        super.setUp()
        transport = MockTransport()
        backend = SupabaseBackend(
            baseURL: URL(string: "https://example.supabase.co")!,
            anonKey: "test-key", transport: transport)
    }

    var lastRequest: URLRequest { transport.requests.last! }

    func testFetchRequestAndDecoding() async throws {
        transport.responseData = Data(#"[{"original":"Back squat","custom":"Squat"}]"#.utf8)

        let renames = try await backend.fetchRenames()

        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/exercise_renames?select=original,custom")
        XCTAssertEqual(renames, [ExerciseRename(original: "Back squat", custom: "Squat")])
    }

    func testUpsertRequestUsesMergeDuplicates() async throws {
        try await backend.upsert(ExerciseRename(original: "Back squat", custom: "Squat"))

        XCTAssertEqual(lastRequest.httpMethod, "POST")
        XCTAssertEqual(lastRequest.value(forHTTPHeaderField: "Prefer"),
                       "resolution=merge-duplicates")
        let body = try JSONSerialization.jsonObject(with: lastRequest.httpBody!) as! [String: String]
        XCTAssertEqual(body, ["original": "Back squat", "custom": "Squat"])
    }

    func testDeleteRequestEncodesSpecialCharacters() async throws {
        try await backend.deleteRename(
            original: "90/90 Hip Lift L Hip Pullback R Foot Lift Off")

        XCTAssertEqual(lastRequest.httpMethod, "DELETE")
        XCTAssertEqual(lastRequest.url?.absoluteString,
                       "https://example.supabase.co/rest/v1/exercise_renames?original=eq.90%2F90%20Hip%20Lift%20L%20Hip%20Pullback%20R%20Foot%20Lift%20Off")
    }

    func testEncodeQueryValue() {
        XCTAssertEqual(SupabaseBackend.encodeQueryValue("simple"), "simple")
        XCTAssertEqual(SupabaseBackend.encodeQueryValue("a b/c(d)"), "a%20b%2Fc%28d%29")
        XCTAssertEqual(SupabaseBackend.encodeQueryValue("Bridges (Marches)"),
                       "Bridges%20%28Marches%29")
    }
}
