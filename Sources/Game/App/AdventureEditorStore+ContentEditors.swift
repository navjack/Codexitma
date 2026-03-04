import Foundation

extension AdventureEditorStore {
    func selectDialogue(index: Int) {
        guard !document.dialogues.isEmpty else { return }
        selectedDialogueIndex = max(0, min(index, document.dialogues.count - 1))
    }

    func addDialogue() {
        let newID = nextIdentifier(prefix: "dialogue", existing: document.dialogues.map(\.id))
        document.dialogues.append(
            DialogueNode(
                id: newID,
                speaker: "New Speaker",
                lines: ["A fresh line waits to be written."]
            )
        )
        selectedDialogueIndex = document.dialogues.count - 1
        selectedContentTab = .dialogues
        statusLine = "ADDED DIALOGUE \(newID.uppercased())."
    }

    func removeSelectedDialogue() {
        guard !document.dialogues.isEmpty else { return }
        let removed = document.dialogues.remove(at: max(0, min(selectedDialogueIndex, document.dialogues.count - 1)))
        if document.dialogues.isEmpty {
            addDialogue()
        }
        selectedDialogueIndex = max(0, min(selectedDialogueIndex, max(0, document.dialogues.count - 1)))
        let replacementID = document.dialogues.first?.id ?? "dialogue_stub"
        for index in document.npcs.indices where document.npcs[index].dialogueID == removed.id {
            document.npcs[index].dialogueID = replacementID
        }
        statusLine = "REMOVED DIALOGUE \(removed.id.uppercased())."
    }

    func updateSelectedDialogueID(_ value: String) {
        guard let index = selectedDialogueArrayIndex else { return }
        let oldID = document.dialogues[index].id
        let newID = nextIdentifier(
            prefix: value,
            existing: document.dialogues.enumerated().compactMap { offset, node in
                offset == index ? nil : node.id
            }
        )
        let dialogue = document.dialogues[index]
        document.dialogues[index] = DialogueNode(id: newID, speaker: dialogue.speaker, lines: dialogue.lines)
        for npcIndex in document.npcs.indices where document.npcs[npcIndex].dialogueID == oldID {
            document.npcs[npcIndex].dialogueID = newID
        }
    }

    func updateSelectedDialogueSpeaker(_ value: String) {
        guard let index = selectedDialogueArrayIndex else { return }
        let dialogue = document.dialogues[index]
        document.dialogues[index] = DialogueNode(id: dialogue.id, speaker: value, lines: dialogue.lines)
    }

    func updateSelectedDialogueLinesText(_ value: String) {
        guard let index = selectedDialogueArrayIndex else { return }
        let dialogue = document.dialogues[index]
        let lines = normalizeLines(from: value)
        document.dialogues[index] = DialogueNode(id: dialogue.id, speaker: dialogue.speaker, lines: lines)
    }

    func selectQuestStage(index: Int) {
        guard !document.questFlow.stages.isEmpty else { return }
        selectedQuestStageIndex = max(0, min(index, document.questFlow.stages.count - 1))
    }

    func addQuestStage() {
        let usedFlags = Set(document.questFlow.stages.map(\.completeWhenFlag))
        let nextFlag = QuestFlag.allCases.first(where: { !usedFlags.contains($0) }) ?? .metElder
        let stages = document.questFlow.stages + [
            QuestStageDefinition(
                objective: "Define the next milestone.",
                completeWhenFlag: nextFlag
            )
        ]
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
        selectedQuestStageIndex = stages.count - 1
        selectedContentTab = .questFlow
        statusLine = "ADDED QUEST STAGE \(stages.count)."
    }

    func removeSelectedQuestStage() {
        guard document.questFlow.stages.count > 1 else {
            statusLine = "KEEP AT LEAST ONE QUEST STAGE."
            return
        }
        var stages = document.questFlow.stages
        stages.remove(at: max(0, min(selectedQuestStageIndex, stages.count - 1)))
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
        selectedQuestStageIndex = max(0, min(selectedQuestStageIndex, stages.count - 1))
    }

    func updateSelectedQuestObjective(_ value: String) {
        guard let index = selectedQuestStageArrayIndex else { return }
        var stages = document.questFlow.stages
        let stage = stages[index]
        stages[index] = QuestStageDefinition(
            objective: value,
            completeWhenFlag: stage.completeWhenFlag
        )
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
    }

    func updateSelectedQuestFlag(_ flag: QuestFlag) {
        guard let index = selectedQuestStageArrayIndex else { return }
        var stages = document.questFlow.stages
        let stage = stages[index]
        stages[index] = QuestStageDefinition(
            objective: stage.objective,
            completeWhenFlag: flag
        )
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
    }

    func updateQuestCompletionText(_ value: String) {
        document.questFlow = QuestFlowDefinition(
            stages: document.questFlow.stages,
            completionText: value
        )
    }

    func selectEncounter(index: Int) {
        guard !document.encounters.isEmpty else { return }
        selectedEncounterIndex = max(0, min(index, document.encounters.count - 1))
    }

    func addEncounter() {
        let enemyID = document.enemies.first?.id ?? "enemy"
        let newID = nextIdentifier(prefix: "encounter", existing: document.encounters.map(\.id))
        document.encounters.append(
            EncounterDefinition(
                id: newID,
                enemyID: enemyID,
                introLine: "A fresh threat enters the path."
            )
        )
        selectedEncounterIndex = document.encounters.count - 1
        selectedContentTab = .encounters
        statusLine = "ADDED ENCOUNTER \(newID.uppercased())."
    }

    func removeSelectedEncounter() {
        guard !document.encounters.isEmpty else { return }
        document.encounters.remove(at: max(0, min(selectedEncounterIndex, document.encounters.count - 1)))
        if document.encounters.isEmpty {
            addEncounter()
        } else {
            selectedEncounterIndex = max(0, min(selectedEncounterIndex, document.encounters.count - 1))
        }
    }

    func updateSelectedEncounterID(_ value: String) {
        guard let index = selectedEncounterArrayIndex else { return }
        let newID = nextIdentifier(
            prefix: value,
            existing: document.encounters.enumerated().compactMap { offset, encounter in
                offset == index ? nil : encounter.id
            }
        )
        let encounter = document.encounters[index]
        document.encounters[index] = EncounterDefinition(id: newID, enemyID: encounter.enemyID, introLine: encounter.introLine)
    }

    func updateSelectedEncounterEnemyID(_ value: String) {
        guard let index = selectedEncounterArrayIndex else { return }
        let encounter = document.encounters[index]
        document.encounters[index] = EncounterDefinition(
            id: encounter.id,
            enemyID: sanitizeIdentifier(value),
            introLine: encounter.introLine
        )
    }

    func updateSelectedEncounterIntro(_ value: String) {
        guard let index = selectedEncounterArrayIndex else { return }
        let encounter = document.encounters[index]
        document.encounters[index] = EncounterDefinition(
            id: encounter.id,
            enemyID: encounter.enemyID,
            introLine: value
        )
    }

    func selectShop(index: Int) {
        guard !document.shops.isEmpty else { return }
        selectedShopIndex = max(0, min(index, document.shops.count - 1))
        selectedShopOfferIndex = 0
    }

    func addShop() {
        let merchant = document.npcs.first
        let merchantID = merchant?.id ?? "merchant"
        let merchantName = merchant?.name ?? "New Merchant"
        let newID = nextIdentifier(prefix: "shop", existing: document.shops.map(\.id))
        document.shops.append(
            ShopDefinition(
                id: newID,
                merchantID: merchantID,
                merchantName: merchantName,
                introLine: "A fresh ledger waits to be stocked.",
                offers: [
                    ShopOffer(
                        id: "\(newID)_offer",
                        itemID: .healingTonic,
                        price: 2,
                        blurb: "A dependable staple.",
                        repeatable: true
                    )
                ]
            )
        )
        selectedShopIndex = document.shops.count - 1
        selectedShopOfferIndex = 0
        selectedContentTab = .shops
        statusLine = "ADDED SHOP \(newID.uppercased())."
    }

    func removeSelectedShop() {
        guard !document.shops.isEmpty else { return }
        document.shops.remove(at: max(0, min(selectedShopIndex, document.shops.count - 1)))
        if document.shops.isEmpty {
            addShop()
        } else {
            selectedShopIndex = max(0, min(selectedShopIndex, document.shops.count - 1))
            selectedShopOfferIndex = 0
        }
    }

    func updateSelectedShopID(_ value: String) {
        guard let index = selectedShopArrayIndex else { return }
        let newID = nextIdentifier(
            prefix: value,
            existing: document.shops.enumerated().compactMap { offset, shop in
                offset == index ? nil : shop.id
            }
        )
        let shop = document.shops[index]
        document.shops[index] = ShopDefinition(
            id: newID,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: shop.introLine,
            offers: shop.offers.enumerated().map { offerIndex, offer in
                ShopOffer(
                    id: offerIndex == 0 ? "\(newID)_offer" : offer.id.replacingOccurrences(of: shop.id, with: newID),
                    itemID: offer.itemID,
                    price: offer.price,
                    blurb: offer.blurb,
                    repeatable: offer.repeatable
                )
            }
        )
    }

    func updateSelectedShopIntro(_ value: String) {
        guard let index = selectedShopArrayIndex else { return }
        let shop = document.shops[index]
        document.shops[index] = ShopDefinition(
            id: shop.id,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: value,
            offers: shop.offers
        )
    }

    func updateSelectedShopMerchantID(_ merchantID: String) {
        guard let index = selectedShopArrayIndex else { return }
        let npc = document.npcs.first(where: { $0.id == merchantID })
        let shop = document.shops[index]
        document.shops[index] = ShopDefinition(
            id: shop.id,
            merchantID: merchantID,
            merchantName: npc?.name ?? shop.merchantName,
            introLine: shop.introLine,
            offers: shop.offers
        )
    }

    func addShopOffer() {
        guard let index = selectedShopArrayIndex else { return }
        let shop = document.shops[index]
        let offerID = nextIdentifier(prefix: "\(shop.id)_offer", existing: shop.offers.map(\.id))
        let offers = shop.offers + [
            ShopOffer(
                id: offerID,
                itemID: .healingTonic,
                price: 2,
                blurb: "A new item waits for a description.",
                repeatable: true
            )
        ]
        document.shops[index] = ShopDefinition(
            id: shop.id,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: shop.introLine,
            offers: offers
        )
        selectedShopOfferIndex = offers.count - 1
    }

    func removeSelectedShopOffer() {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        var offers = document.shops[shopIndex].offers
        guard offers.count > 1 else {
            statusLine = "KEEP AT LEAST ONE SHOP OFFER."
            return
        }
        offers.remove(at: offerIndex)
        let shop = document.shops[shopIndex]
        document.shops[shopIndex] = ShopDefinition(
            id: shop.id,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: shop.introLine,
            offers: offers
        )
        selectedShopOfferIndex = max(0, min(selectedShopOfferIndex, offers.count - 1))
    }

    func selectShopOffer(index: Int) {
        guard let shop = selectedShop, !shop.offers.isEmpty else { return }
        selectedShopOfferIndex = max(0, min(index, shop.offers.count - 1))
    }

    func updateSelectedShopOfferID(_ value: String) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        let shop = document.shops[shopIndex]
        let newID = nextIdentifier(
            prefix: value,
            existing: shop.offers.enumerated().compactMap { offset, offer in
                offset == offerIndex ? nil : offer.id
            }
        )
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: newID,
                itemID: offer.itemID,
                price: offer.price,
                blurb: offer.blurb,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferItemID(_ value: ItemID) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: value,
                price: offer.price,
                blurb: offer.blurb,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferPrice(_ value: Int) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: offer.itemID,
                price: max(0, value),
                blurb: offer.blurb,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferBlurb(_ value: String) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: offer.itemID,
                price: offer.price,
                blurb: value,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferRepeatable(_ value: Bool) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: offer.itemID,
                price: offer.price,
                blurb: offer.blurb,
                repeatable: value
            )
        }
    }
}
