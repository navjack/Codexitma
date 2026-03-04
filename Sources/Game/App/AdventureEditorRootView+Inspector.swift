import AppKit
import Foundation
import SwiftUI

extension AdventureEditorRootView {
    @ViewBuilder
    var inspectorFields: some View {
        if let npc = store.selectedNPC {
            Text("NPC INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("NPC ID", text: Binding(
                get: { store.selectedNPC?.id ?? npc.id },
                set: { store.updateSelectedNPCID($0) }
            ))

            labeledField("NAME", text: Binding(
                get: { store.selectedNPC?.name ?? npc.name },
                set: { store.updateSelectedNPCName($0) }
            ))

            labeledField("DIALOGUE", text: Binding(
                get: { store.selectedNPC?.dialogueID ?? npc.dialogueID },
                set: { store.updateSelectedNPCDialogueID($0) }
            ))

            Text("SHOP \(store.selectedNPCShop?.id.uppercased() ?? "NONE")")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.82))

            Button(store.selectedNPCShop == nil ? "CREATE SHOP" : "OPEN SHOP") {
                store.ensureShopForSelectedNPC()
            }
            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
        } else if let enemy = store.selectedEnemy {
            Text("ENEMY INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("ENEMY ID", text: Binding(
                get: { store.selectedEnemy?.id ?? enemy.id },
                set: { store.updateSelectedEnemyID($0) }
            ))

            labeledField("NAME", text: Binding(
                get: { store.selectedEnemy?.name ?? enemy.name },
                set: { store.updateSelectedEnemyName($0) }
            ))

            HStack(spacing: 8) {
                labeledStepper("HP", value: Binding(
                    get: { store.selectedEnemy?.hp ?? enemy.hp },
                    set: { store.updateSelectedEnemyHP($0) }
                ), range: 1...99)

                labeledStepper("ATK", value: Binding(
                    get: { store.selectedEnemy?.attack ?? enemy.attack },
                    set: { store.updateSelectedEnemyAttack($0) }
                ), range: 0...25)

                labeledStepper("DEF", value: Binding(
                    get: { store.selectedEnemy?.defense ?? enemy.defense },
                    set: { store.updateSelectedEnemyDefense($0) }
                ), range: 0...25)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("AI", selection: Binding(
                    get: { store.selectedEnemy?.ai ?? enemy.ai },
                    set: { store.updateSelectedEnemyAI($0) }
                )) {
                    ForEach([AIKind.idle, .stalk, .guardian, .boss], id: \.self) { ai in
                        Text(ai.rawValue).tag(ai)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        } else if let interactable = store.selectedInteractable {
            Text("INTERACTABLE INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("OBJECT ID", text: Binding(
                get: { store.selectedInteractable?.id ?? interactable.id },
                set: { store.updateSelectedInteractableID($0) }
            ))

            labeledField("TITLE", text: Binding(
                get: { store.selectedInteractable?.title ?? interactable.title },
                set: { store.updateSelectedInteractableTitle($0) }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Text("KIND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Kind", selection: Binding(
                    get: { store.selectedInteractable?.kind ?? interactable.kind },
                    set: { store.updateSelectedInteractableKind($0) }
                )) {
                    ForEach(editorInteractablePalette, id: \.kind) { choice in
                        Text(choice.label).tag(choice.kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("REWARD ITEM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Reward Item", selection: Binding(
                    get: { store.selectedInteractable?.rewardItem ?? interactable.rewardItem },
                    set: { store.updateSelectedInteractableRewardItem($0) }
                )) {
                    Text("NONE").tag(Optional<ItemID>.none)
                    ForEach(ItemID.allCases, id: \.self) { itemID in
                        Text(itemID.rawValue).tag(Optional(itemID))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            labeledStepper("REWARD MARKS", value: Binding(
                get: { store.selectedInteractable?.rewardMarks ?? interactable.rewardMarks ?? 0 },
                set: { store.updateSelectedInteractableRewardMarks($0) }
            ), range: 0...999)

            VStack(alignment: .leading, spacing: 4) {
                Text("REQUIRED FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Required Flag", selection: Binding(
                    get: { store.selectedInteractable?.requiredFlag ?? interactable.requiredFlag },
                    set: { store.updateSelectedInteractableRequiredFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GRANTS FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Grants Flag", selection: Binding(
                    get: { store.selectedInteractable?.grantsFlag ?? interactable.grantsFlag },
                    set: { store.updateSelectedInteractableGrantsFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        } else if let portal = store.selectedPortal {
            Text("PORTAL INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            VStack(alignment: .leading, spacing: 4) {
                Text("DESTINATION MAP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Destination Map", selection: Binding(
                    get: { store.selectedPortal?.toMap ?? portal.toMap },
                    set: { store.updateSelectedPortalDestinationMap($0) }
                )) {
                    ForEach(store.document.maps, id: \.id) { map in
                        Text(map.name.uppercased()).tag(map.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Button("SYNC TO MAP SPAWN") {
                store.syncSelectedPortalToDestinationSpawn()
            }
            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

            VStack(alignment: .leading, spacing: 4) {
                Text("REQUIRED FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Portal Flag", selection: Binding(
                    get: { store.selectedPortal?.requiredFlag ?? portal.requiredFlag },
                    set: { store.updateSelectedPortalRequiredFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("BLOCKED TEXT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)
                TextEditor(text: Binding(
                    get: { store.selectedPortal?.blockedMessage ?? portal.blockedMessage ?? "" },
                    set: { store.updateSelectedPortalBlockedMessage($0) }
                ))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(palette.text)
                .frame(height: 72)
                .padding(6)
                .background(palette.panelAlt)
                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
            }

            HStack(spacing: 8) {
                labeledStepper("TO X", value: Binding(
                    get: { store.selectedPortal?.toPosition.x ?? portal.toPosition.x },
                    set: { store.updateSelectedPortalDestinationX($0) }
                ), range: 0...99)

                labeledStepper("TO Y", value: Binding(
                    get: { store.selectedPortal?.toPosition.y ?? portal.toPosition.y },
                    set: { store.updateSelectedPortalDestinationY($0) }
                ), range: 0...99)
            }
        } else {
            Text("NO EDITABLE OBJECT IS SELECTED.")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.80))
        }
    }
}
