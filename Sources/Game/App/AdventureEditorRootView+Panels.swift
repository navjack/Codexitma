#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

extension AdventureEditorRootView {
    var dialogueListPanel: some View {
        EditorPanel(title: "DIALOGUES", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.dialogues.enumerated()), id: \.element.id) { index, dialogue in
                            Button {
                                store.selectDialogue(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dialogue.id.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(dialogue.speaker)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedDialogueIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addDialogue()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedDialogue()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    var dialogueEditorPanel: some View {
        EditorPanel(title: "DIALOGUE EDITOR", palette: palette) {
            if let dialogue = store.selectedDialogue {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("DIALOGUE ID", text: Binding(
                        get: { store.selectedDialogue?.id ?? dialogue.id },
                        set: { store.updateSelectedDialogueID($0) }
                    ))

                    labeledField("SPEAKER", text: Binding(
                        get: { store.selectedDialogue?.speaker ?? dialogue.speaker },
                        set: { store.updateSelectedDialogueSpeaker($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("LINES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        TextEditor(text: Binding(
                            get: { (store.selectedDialogue?.lines ?? dialogue.lines).joined(separator: "\n") },
                            set: { store.updateSelectedDialogueLinesText($0) }
                        ))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.text)
                        .frame(minHeight: 180)
                        .padding(6)
                        .background(palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }
                }
            } else {
                emptyEditorLabel("NO DIALOGUE IS AVAILABLE.")
            }
        }
    }

    var questStageListPanel: some View {
        EditorPanel(title: "QUEST STAGES", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.questFlow.stages.enumerated()), id: \.offset) { index, stage in
                            Button {
                                store.selectQuestStage(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("STAGE \(index + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(stage.objective)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .lineLimit(2)
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedQuestStageIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addQuestStage()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedQuestStage()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    var questFlowEditorPanel: some View {
        EditorPanel(title: "QUEST FLOW", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                if let stage = store.selectedQuestStage {
                    labeledField("OBJECTIVE", text: Binding(
                        get: { store.selectedQuestStage?.objective ?? stage.objective },
                        set: { store.updateSelectedQuestObjective($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMPLETE WHEN FLAG")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)

                        Picker("Quest Flag", selection: Binding(
                            get: { store.selectedQuestStage?.completeWhenFlag ?? stage.completeWhenFlag },
                            set: { store.updateSelectedQuestFlag($0) }
                        )) {
                            ForEach(QuestFlag.allCases, id: \.self) { flag in
                                Text(flag.rawValue).tag(flag)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("COMPLETION TEXT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    TextEditor(text: Binding(
                        get: { store.document.questFlow.completionText },
                        set: { store.updateQuestCompletionText($0) }
                    ))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(palette.text)
                    .frame(minHeight: 140)
                    .padding(6)
                    .background(palette.panelAlt)
                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                }
            }
        }
    }

    var encounterListPanel: some View {
        EditorPanel(title: "ENCOUNTERS", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.encounters.enumerated()), id: \.element.id) { index, encounter in
                            Button {
                                store.selectEncounter(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(encounter.id.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(encounter.enemyID)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedEncounterIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addEncounter()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedEncounter()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    var encounterEditorPanel: some View {
        EditorPanel(title: "ENCOUNTER EDITOR", palette: palette) {
            if let encounter = store.selectedEncounter {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("ENCOUNTER ID", text: Binding(
                        get: { store.selectedEncounter?.id ?? encounter.id },
                        set: { store.updateSelectedEncounterID($0) }
                    ))

                    labeledField("ENEMY ID", text: Binding(
                        get: { store.selectedEncounter?.enemyID ?? encounter.enemyID },
                        set: { store.updateSelectedEncounterEnemyID($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("INTRO LINE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        TextEditor(text: Binding(
                            get: { store.selectedEncounter?.introLine ?? encounter.introLine },
                            set: { store.updateSelectedEncounterIntro($0) }
                        ))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.text)
                        .frame(minHeight: 140)
                        .padding(6)
                        .background(palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }
                }
            } else {
                emptyEditorLabel("NO ENCOUNTER IS AVAILABLE.")
            }
        }
    }

    var shopListPanel: some View {
        EditorPanel(title: "SHOPS", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.shops.enumerated()), id: \.element.id) { index, shop in
                            Button {
                                store.selectShop(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shop.id.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(shop.merchantName)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedShopIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addShop()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedShop()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    var shopEditorPanel: some View {
        EditorPanel(title: "SHOP EDITOR", palette: palette) {
            if let shop = store.selectedShop {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("SHOP ID", text: Binding(
                        get: { store.selectedShop?.id ?? shop.id },
                        set: { store.updateSelectedShopID($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MERCHANT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        Picker("Merchant", selection: Binding(
                            get: { store.selectedShop?.merchantID ?? shop.merchantID },
                            set: { store.updateSelectedShopMerchantID($0) }
                        )) {
                            ForEach(store.document.npcs, id: \.id) { npc in
                                Text(npc.name.uppercased()).tag(npc.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("INTRO LINE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        TextEditor(text: Binding(
                            get: { store.selectedShop?.introLine ?? shop.introLine },
                            set: { store.updateSelectedShopIntro($0) }
                        ))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.text)
                        .frame(height: 72)
                        .padding(6)
                        .background(palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }

                    Text("OFFERS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            shopOfferListPanel
                                .frame(width: 200)
                            shopOfferDetailsPanel
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            shopOfferListPanel
                            shopOfferDetailsPanel
                        }
                    }

                    HStack(spacing: 8) {
                        Button("ADD OFFER") {
                            store.addShopOffer()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                        Button("DROP OFFER") {
                            store.removeSelectedShopOffer()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                    }
                }
            } else {
                emptyEditorLabel("NO SHOP IS AVAILABLE.")
            }
        }
    }

    var shopOfferListPanel: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array((store.selectedShop?.offers ?? []).enumerated()), id: \.element.id) { index, offer in
                    Button {
                        store.selectShopOffer(index: index)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(offer.id.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Text("\(offer.itemID.rawValue)  \(offer.price)M")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .opacity(0.78)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(store.selectedShopOfferIndex == index ? palette.selection : palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    var shopOfferDetailsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let offer = store.selectedShopOffer {
                labeledField("OFFER ID", text: Binding(
                    get: { store.selectedShopOffer?.id ?? offer.id },
                    set: { store.updateSelectedShopOfferID($0) }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("ITEM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    Picker("Item", selection: Binding(
                        get: { store.selectedShopOffer?.itemID ?? offer.itemID },
                        set: { store.updateSelectedShopOfferItemID($0) }
                    )) {
                        ForEach(ItemID.allCases, id: \.self) { itemID in
                            Text(itemID.rawValue).tag(itemID)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                labeledStepper("PRICE", value: Binding(
                    get: { store.selectedShopOffer?.price ?? offer.price },
                    set: { store.updateSelectedShopOfferPrice($0) }
                ), range: 0...99)

                VStack(alignment: .leading, spacing: 4) {
                    Text("BLURB")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    TextEditor(text: Binding(
                        get: { store.selectedShopOffer?.blurb ?? offer.blurb },
                        set: { store.updateSelectedShopOfferBlurb($0) }
                    ))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(palette.text)
                    .frame(height: 64)
                    .padding(6)
                    .background(palette.panelAlt)
                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                }

                Toggle(isOn: Binding(
                    get: { store.selectedShopOffer?.repeatable ?? offer.repeatable },
                    set: { store.updateSelectedShopOfferRepeatable($0) }
                )) {
                    Text("REPEATABLE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                }
                .toggleStyle(.checkbox)
            } else {
                emptyEditorLabel("NO OFFER IS SELECTED.")
            }
        }
    }

    var npcRosterListPanel: some View {
        EditorPanel(title: "NPC ROSTER", palette: palette) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.document.npcs, id: \.id) { npc in
                        Button {
                            store.focusNPC(id: npc.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(npc.name.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text("\(npc.id)  @ \(npc.mapID)")
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .opacity(0.78)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(store.selectedNPC?.id == npc.id ? palette.selection : palette.panelAlt)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    var enemyRosterListPanel: some View {
        EditorPanel(title: "ENEMY ROSTER", palette: palette) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.document.enemies, id: \.id) { enemy in
                        Button {
                            store.focusEnemy(id: enemy.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(enemy.name.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text("\(enemy.id)  @ \(enemy.mapID)")
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .opacity(0.78)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(store.selectedEnemy?.id == enemy.id ? palette.selection : palette.panelAlt)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }
}
#endif
