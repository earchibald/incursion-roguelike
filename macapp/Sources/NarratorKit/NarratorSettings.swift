// See the Incursion LICENSE file for copyright information.
//
// All narrator configuration. Non-secrets in UserDefaults under
// "narrator.*"; the API token only ever touches the Keychain. There are
// no config files anywhere in this feature.
import Foundation
import Security
import Combine

public enum KeychainStore {
    static let service = "Incursion Narrator"
    public static let account = "api-token"

    static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static func saveToken(_ t: String, account: String = KeychainStore.account) {
        deleteToken(account: account)
        var q = query(account: account)
        q[kSecValueData as String] = Data(t.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    public static func loadToken(account: String = KeychainStore.account) -> String? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deleteToken(account: String = KeychainStore.account) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
}

public final class NarratorSettings: ObservableObject {
    private let d: UserDefaults

    @Published public var baseURLString: String {
        didSet { d.set(baseURLString, forKey: "narrator.baseURL") }
    }
    @Published public var model: String {
        didSet { d.set(model, forKey: "narrator.model") }
    }
    @Published public var voice: PromptKey {
        didSet { d.set(voice.rawValue, forKey: "narrator.voice") }
    }
    @Published public var customStyle: String {
        didSet { d.set(customStyle, forKey: "narrator.customStyle") }
    }
    @Published public var enabledMilestones: Set<Milestone> {
        didSet { d.set(enabledMilestones.map(\.rawValue).sorted(),
                       forKey: "narrator.milestones") }
    }
    @Published public var cooldownTurns: Int {
        didSet { d.set(cooldownTurns, forKey: "narrator.cooldownTurns") }
    }
    @Published public var length: NarrationLength {
        didSet { d.set(length.rawValue, forKey: "narrator.length") }
    }
    @Published public var temperature: Double {
        didSet { d.set(temperature, forKey: "narrator.temperature") }
    }
    @Published public var maxTokens: Int {
        didSet { d.set(maxTokens, forKey: "narrator.maxTokens") }
    }
    @Published public var askEnabled: Bool {
        didSet { d.set(askEnabled, forKey: "narrator.askEnabled") }
    }
    @Published public var includeWiki: Bool {
        didSet { d.set(includeWiki, forKey: "narrator.includeWiki") }
    }
    /// Bumps whenever a prompt override changes, so SwiftUI refreshes.
    @Published public private(set) var promptEdition = 0

    public init(defaults: UserDefaults = .standard) {
        d = defaults
        baseURLString = d.string(forKey: "narrator.baseURL") ?? "https://api.openai.com/v1"
        model = d.string(forKey: "narrator.model") ?? ""
        voice = PromptKey(rawValue: d.string(forKey: "narrator.voice") ?? "")
            ?? .voiceChronicler
        customStyle = d.string(forKey: "narrator.customStyle") ?? ""
        if let raw = d.stringArray(forKey: "narrator.milestones") {
            enabledMilestones = Set(raw.compactMap(Milestone.init(rawValue:)))
        } else {
            enabledMilestones = Set(Milestone.allCases)
        }
        cooldownTurns = d.object(forKey: "narrator.cooldownTurns") as? Int ?? 150
        length = NarrationLength(rawValue: d.string(forKey: "narrator.length") ?? "")
            ?? .beat
        temperature = d.object(forKey: "narrator.temperature") as? Double ?? 0.8
        maxTokens = d.object(forKey: "narrator.maxTokens") as? Int ?? 220
        askEnabled = d.object(forKey: "narrator.askEnabled") as? Bool ?? true
        includeWiki = d.object(forKey: "narrator.includeWiki") as? Bool ?? true
    }

    // MARK: prompt overrides

    private func promptKey(_ k: PromptKey) -> String { "narrator.prompt." + k.rawValue }

    public func promptText(_ k: PromptKey) -> String {
        d.string(forKey: promptKey(k)) ?? k.defaultText
    }

    public func setPromptText(_ k: PromptKey, _ text: String) {
        if text == k.defaultText {
            d.removeObject(forKey: promptKey(k))
        } else {
            d.set(text, forKey: promptKey(k))
        }
        promptEdition += 1
    }

    public func isPromptModified(_ k: PromptKey) -> Bool {
        d.string(forKey: promptKey(k)) != nil
    }

    public func restorePromptDefault(_ k: PromptKey) {
        d.removeObject(forKey: promptKey(k))
        promptEdition += 1
    }
}
