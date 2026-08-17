import XCTest
@testable import NarratorKit

final class SettingsTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "narrator-tests")!
        defaults.removePersistentDomain(forName: "narrator-tests")
    }

    func testDefaultsAreSane() {
        let s = NarratorSettings(defaults: defaults)
        XCTAssertEqual(s.baseURLString, "https://api.openai.com/v1")
        XCTAssertEqual(s.enabledMilestones, Set(Milestone.allCases))
        XCTAssertEqual(s.cooldownTurns, 150)
        XCTAssertEqual(s.length, .beat)
    }

    func testValuesPersistAcrossInstances() {
        let s1 = NarratorSettings(defaults: defaults)
        s1.model = "llama-3.3-70b"
        s1.cooldownTurns = 400
        s1.enabledMilestones = [.death]
        let s2 = NarratorSettings(defaults: defaults)
        XCTAssertEqual(s2.model, "llama-3.3-70b")
        XCTAssertEqual(s2.cooldownTurns, 400)
        XCTAssertEqual(s2.enabledMilestones, [.death])
    }

    func testPromptOverrideAndRestore() {
        let s = NarratorSettings(defaults: defaults)
        XCTAssertFalse(s.isPromptModified(.narratorSystem))
        XCTAssertEqual(s.promptText(.narratorSystem), PromptKey.narratorSystem.defaultText)
        s.setPromptText(.narratorSystem, "Be terse.")
        XCTAssertTrue(s.isPromptModified(.narratorSystem))
        XCTAssertEqual(s.promptText(.narratorSystem), "Be terse.")
        s.restorePromptDefault(.narratorSystem)
        XCTAssertFalse(s.isPromptModified(.narratorSystem))
        XCTAssertEqual(s.promptText(.narratorSystem), PromptKey.narratorSystem.defaultText)
    }

    func testKeychainRoundTrip() {
        defer { KeychainStore.deleteToken(account: "api-token-tests") }
        KeychainStore.deleteToken(account: "api-token-tests")
        XCTAssertNil(KeychainStore.loadToken(account: "api-token-tests"))
        KeychainStore.saveToken("sk-abc123", account: "api-token-tests")
        XCTAssertEqual(KeychainStore.loadToken(account: "api-token-tests"), "sk-abc123")
        KeychainStore.saveToken("sk-updated", account: "api-token-tests")
        XCTAssertEqual(KeychainStore.loadToken(account: "api-token-tests"), "sk-updated")
        KeychainStore.deleteToken(account: "api-token-tests")
        XCTAssertNil(KeychainStore.loadToken(account: "api-token-tests"))
    }
}
