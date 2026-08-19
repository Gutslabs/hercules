import Foundation
import Testing
@testable import HerculesIslandBridge

@Test func chatRequestRoundTrips() throws {
    let value = HerculesIslandChatRequest(
        history: [
            HerculesIslandMessage(role: .user, text: "iki yumurta")
        ],
        text: "kaydet"
    )
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(HerculesIslandChatRequest.self, from: data) == value)
}

@Test func weightRequestRoundTrips() throws {
    let value = HerculesIslandWeightSaveRequest(kilograms: 85.8)
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(HerculesIslandWeightSaveRequest.self, from: data) == value)
}
