import Foundation

enum CombatSystem {
    static func damage(attackerAttack: Int, defenderDefense: Int, turnIndex: Int) -> Int {
        let base = max(1, attackerAttack - (defenderDefense / 2))
        let variance = (turnIndex % 3) - 1
        return max(1, base + variance)
    }
}
