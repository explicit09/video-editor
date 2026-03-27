import Testing
import Foundation
@testable import AIServices

@Suite("AI Services Tests")
struct AIServicesTests {

    @Test("AIMessage encodes correctly")
    func messageEncoding() throws {
        let message = AIMessage(role: "user", content: "Hello")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AIMessage.self, from: data)
        #expect(decoded.role == "user")
        #expect(decoded.content == "Hello")
    }

    @Test("CostTier values are correct")
    func costTiers() {
        #expect(CostTier.local.rawValue == "local")
        #expect(CostTier.frequent.rawValue == "frequent")
        #expect(CostTier.expensive.rawValue == "expensive")
    }
}
