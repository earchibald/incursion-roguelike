// See the Incursion LICENSE file for copyright information.
//
// Every prompt the narrator uses, with its shipped default. The settings
// window shows these for editing; overrides live in UserDefaults keyed by
// "narrator.prompt.<rawValue>" and fall back to defaultText.
import Foundation

public enum PromptKey: String, CaseIterable {
    case narratorSystem, voiceChronicler, voiceBard, voiceCompanion
    case askIndex, askAnswer, summarize

    public var title: String {
        switch self {
        case .narratorSystem:  return "Narrator system prompt"
        case .voiceChronicler: return "Voice: Dry Chronicler"
        case .voiceBard:       return "Voice: Doomful Bard"
        case .voiceCompanion:  return "Voice: Wry Companion"
        case .askIndex:        return "Ask-the-GM: topic selection"
        case .askAnswer:       return "Ask-the-GM: answer"
        case .summarize:       return "Journal summarization"
        }
    }

    public var defaultText: String {
        switch self {
        case .narratorSystem: return """
You are the narrator of a run of Incursion, a difficult fantasy roguelike. \
You observe milestones of one adventurer's descent and respond with prose. \
Never give tactical advice, never reveal game mechanics or numbers, never \
address the player as "you the player" — narrate the character in the third \
person. Stay grounded in the events you are shown; invent atmosphere, not \
facts. If the events are unclear, be brief rather than wrong.
"""
        case .voiceChronicler: return """
Voice: a dry chronicler writing a terse historical record long after the \
fact. Understatement over drama. No exclamation marks.
"""
        case .voiceBard: return """
Voice: a doomful bard who suspects this tale ends badly and relishes saying \
so. Ominous, musical, a little grand.
"""
        case .voiceCompanion: return """
Voice: a wry companion walking one step behind, fond of the adventurer but \
unable to resist a raised eyebrow. Warm, lightly ironic.
"""
        case .askIndex: return """
You are the gamemaster's librarian for the roguelike Incursion. Below is an \
index of help topics. Given the player's question, reply with ONLY a JSON \
array of the ids of the topics (at most 4) most likely to contain the \
answer, e.g. ["combat","saving-throws"]. No other text.
"""
        case .askAnswer: return """
You are the gamemaster for the roguelike Incursion. Answer the player's \
question using ONLY the reference text provided. Quote rules accurately; \
if the text does not answer the question, say so plainly. End with a line \
"Sources:" listing the topic titles you used. Do not spoil late-game \
content beyond what the question requires.
"""
        case .summarize: return """
Condense the narration journal below into a compact "story so far" of at \
most 150 words, keeping character identity, notable deeds, and tone. \
Reply with the summary only.
"""
        }
    }
}

public enum NarrationLength: String, CaseIterable {
    case line, beat, paragraph

    public var instruction: String {
        switch self {
        case .line:      return "Reply with a single sentence."
        case .beat:      return "Reply with two or three sentences."
        case .paragraph: return "Reply with one short paragraph, five sentences at most."
        }
    }

    public var title: String {
        switch self {
        case .line: return "One line"
        case .beat: return "A beat"
        case .paragraph: return "A paragraph"
        }
    }
}
