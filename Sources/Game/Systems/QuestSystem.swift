import Foundation

enum QuestSystem {
    static func objective(for quests: QuestState, flow: QuestFlowDefinition) -> String {
        for stage in flow.stages where !quests.has(stage.completeWhenFlag) {
            return stage.objective
        }
        return flow.completionText
    }

    static func objective(for quests: QuestState, adventure: AdventureID = .ashesOfMerrow) -> String {
        objective(for: quests, flow: fallbackQuestFlow(for: adventure))
    }

    private static func fallbackQuestFlow(for adventure: AdventureID) -> QuestFlowDefinition {
        if adventure == .starfallRequiem {
            return QuestFlowDefinition(
                stages: [
                    QuestStageDefinition(objective: "Find Admiral Vey at Cinder Wharf.", completeWhenFlag: .metElder),
                    QuestStageDefinition(objective: "Prime the west capacitor on the Salt Causeway.", completeWhenFlag: .southShrineLit),
                    QuestStageDefinition(objective: "Prime the east capacitor in the Glass Marsh.", completeWhenFlag: .orchardShrineLit),
                    QuestStageDefinition(objective: "Recover the Star Core from the Reliquary Vault.", completeWhenFlag: .obtainedLensCore),
                    QuestStageDefinition(objective: "Raise a safe route through the Thunder Shoals.", completeWhenFlag: .fenCrossed),
                    QuestStageDefinition(objective: "Climb the Sky Engine and align its lenses.", completeWhenFlag: .beaconLit),
                    QuestStageDefinition(objective: "Defeat the Fallen Helmsman.", completeWhenFlag: .keeperDefeated),
                ],
                completionText: "The sky-engine sings again."
            )
        }
        return QuestFlowDefinition(
            stages: [
                QuestStageDefinition(objective: "Seek Elder Rowan in Merrow.", completeWhenFlag: .metElder),
                QuestStageDefinition(objective: "Restore the shrine in South Fields.", completeWhenFlag: .southShrineLit),
                QuestStageDefinition(objective: "Bring light to the Sunken Orchard.", completeWhenFlag: .orchardShrineLit),
                QuestStageDefinition(objective: "Recover the Lens Core in the Barrows.", completeWhenFlag: .obtainedLensCore),
                QuestStageDefinition(objective: "Cross the Black Fen.", completeWhenFlag: .fenCrossed),
                QuestStageDefinition(objective: "Ascend the Beacon Spire.", completeWhenFlag: .beaconLit),
                QuestStageDefinition(objective: "Defeat the Shaded Keeper.", completeWhenFlag: .keeperDefeated),
            ],
            completionText: "The beacon burns again."
        )
    }
}
