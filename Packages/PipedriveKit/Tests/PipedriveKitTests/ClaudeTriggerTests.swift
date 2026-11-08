import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipedriveKit

/// Déclenchement de la tâche Claude quand Yves envoie une « Note pour Claude » (données fictives, aucun vrai jeton).
final class ClaudeTriggerTests: XCTestCase {
    let fireURL = "https://api.anthropic.com/v1/claude_code/routines/trig_TEST123/fire"

    func testURLValidation() {
        XCTAssertNotNil(ClaudeTrigger.validURL(fireURL))
        XCTAssertNotNil(ClaudeTrigger.validURL("  \(fireURL)\n"))
        XCTAssertNil(ClaudeTrigger.validURL("https://example.com/v1/claude_code/routines/trig_TEST123/fire"))
        XCTAssertNil(ClaudeTrigger.validURL("http://api.anthropic.com/v1/claude_code/routines/trig_TEST123/fire"))
        XCTAssertNil(ClaudeTrigger.validURL("https://api.anthropic.com/v1/claude_code/routines/trig_TEST123"))
        XCTAssertThrowsError(try ClaudeTrigger(fireURL: "pas une adresse", token: "jeton-de-test"))
        XCTAssertThrowsError(try ClaudeTrigger(fireURL: fireURL, token: "  "))
    }

    func testPayloadCarriesOnlyIdentifiers() {
        XCTAssertEqual(ClaudeTrigger.payload(noteID: 42, dealID: 100), "note_id=42 deal_id=100")
        XCTAssertEqual(ClaudeTrigger.payload(noteID: 42, dealID: nil), "note_id=42 deal_id=aucune")
    }

    func testFireSendsBearerVersionAndText() async throws {
        let transport = MockTransport([
            "POST /v1/claude_code/routines/trig_TEST123/fire": .init(status: 200, body: """
            {"type":"routine_fire","claude_code_session_id":"session_x","claude_code_session_url":"https://claude.ai/code/session_x"}
            """),
        ])
        let trigger = try ClaudeTrigger(fireURL: fireURL, token: "jeton-de-test", transport: transport)
        let url = try await trigger.fire(text: ClaudeTrigger.payload(noteID: 42, dealID: 100))
        XCTAssertEqual(url, "https://claude.ai/code/session_x")
        let recorded = await transport.recorded
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jeton-de-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let data = try XCTUnwrap(request.httpBody)
        let body = try decode(String(decoding: data, as: UTF8.self))
        XCTAssertEqual(body["text"].stringValue, "note_id=42 deal_id=100")
    }

    func testFireErrors() async throws {
        let refused = MockTransport(["POST /v1/claude_code/routines/trig_TEST123/fire": .init(status: 401, body: "{}")])
        do {
            try await ClaudeTrigger(fireURL: fireURL, token: "jeton-de-test", transport: refused).fire(text: "x")
            XCTFail("401 attendu")
        } catch {
            XCTAssertEqual(error as? ClaudeTrigger.TriggerError, .unauthorized)
        }
        let busy = MockTransport(["POST /v1/claude_code/routines/trig_TEST123/fire": .init(status: 429, body: "{}")])
        do {
            try await ClaudeTrigger(fireURL: fireURL, token: "jeton-de-test", transport: busy).fire(text: "x")
            XCTFail("429 attendu")
        } catch {
            XCTAssertEqual(error as? ClaudeTrigger.TriggerError, .rateLimited)
        }
        let paused = MockTransport(["POST /v1/claude_code/routines/trig_TEST123/fire": .init(status: 400, body: """
        {"type":"error","error":{"type":"invalid_request_error","message":"routine is paused"}}
        """)])
        do {
            try await ClaudeTrigger(fireURL: fireURL, token: "jeton-de-test", transport: paused).fire(text: "x")
            XCTFail("400 attendu")
        } catch {
            XCTAssertEqual(error as? ClaudeTrigger.TriggerError, .rejected(status: 400, message: "routine is paused"))
        }
    }
}
