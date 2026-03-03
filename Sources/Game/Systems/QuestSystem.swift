import Foundation

enum QuestSystem {
    static func objective(for quests: QuestState, text: ObjectiveTextSet) -> String {
        if !quests.has(.metElder) { return text.seekElder }
        if !quests.has(.southShrineLit) { return text.restoreFirstRelay }
        if !quests.has(.orchardShrineLit) { return text.restoreSecondRelay }
        if !quests.has(.obtainedLensCore) { return text.recoverCore }
        if !quests.has(.fenCrossed) { return text.crossHazard }
        if !quests.has(.beaconLit) { return text.ascendSpire }
        if !quests.has(.keeperDefeated) { return text.defeatKeeper }
        return text.completion
    }

    static func objective(for quests: QuestState, adventure: AdventureID = .ashesOfMerrow) -> String {
        objective(for: quests, text: fallbackObjectiveText(for: adventure))
    }

    private static func fallbackObjectiveText(for adventure: AdventureID) -> ObjectiveTextSet {
        switch adventure {
        case .ashesOfMerrow:
            return ObjectiveTextSet(
                seekElder: "Seek Elder Rowan in Merrow.",
                restoreFirstRelay: "Restore the shrine in South Fields.",
                restoreSecondRelay: "Bring light to the Sunken Orchard.",
                recoverCore: "Recover the Lens Core in the Barrows.",
                crossHazard: "Cross the Black Fen.",
                ascendSpire: "Ascend the Beacon Spire.",
                defeatKeeper: "Defeat the Shaded Keeper.",
                completion: "The beacon burns again."
            )
        case .starfallRequiem:
            return ObjectiveTextSet(
                seekElder: "Find Admiral Vey at Cinder Wharf.",
                restoreFirstRelay: "Prime the west capacitor on the Salt Causeway.",
                restoreSecondRelay: "Prime the east capacitor in the Glass Marsh.",
                recoverCore: "Recover the Star Core from the Reliquary Vault.",
                crossHazard: "Raise a safe route through the Thunder Shoals.",
                ascendSpire: "Climb the Sky Engine and align its lenses.",
                defeatKeeper: "Defeat the Fallen Helmsman.",
                completion: "The sky-engine sings again."
            )
        }
    }
}
