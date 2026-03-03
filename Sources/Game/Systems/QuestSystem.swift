import Foundation

enum QuestSystem {
    static func objective(for quests: QuestState) -> String {
        if !quests.has(.metElder) { return "Seek Elder Rowan in Merrow." }
        if !quests.has(.southShrineLit) { return "Restore the shrine in South Fields." }
        if !quests.has(.orchardShrineLit) { return "Bring light to the Sunken Orchard." }
        if !quests.has(.obtainedLensCore) { return "Recover the Lens Core in the Barrows." }
        if !quests.has(.fenCrossed) { return "Cross the Black Fen." }
        if !quests.has(.beaconLit) { return "Ascend the Beacon Spire." }
        if !quests.has(.keeperDefeated) { return "Defeat the Shaded Keeper." }
        return "The beacon burns again."
    }
}
