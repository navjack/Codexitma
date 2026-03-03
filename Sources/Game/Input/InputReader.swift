import Darwin
import Foundation

enum InputMode {
    case raw
    case line
}

enum InputError: Error {
    case terminalSetupFailed
}

struct InputParser {
    static func parse(bytes: [UInt8]) -> ActionCommand? {
        if bytes == [27, 91, 65] { return .move(.up) }
        if bytes == [27, 91, 66] { return .move(.down) }
        if bytes == [27, 91, 67] { return .move(.right) }
        if bytes == [27, 91, 68] { return .move(.left) }
        guard let char = bytes.first else { return nil }
        return parse(character: Character(UnicodeScalar(char)))
    }

    static func parse(character: Character) -> ActionCommand? {
        switch character.lowercased().first {
        case "w": return .move(.up)
        case "s": return .move(.down)
        case "a": return .move(.left)
        case "d": return .move(.right)
        case "e", " ": return .interact
        case "i": return .openInventory
        case "j", "h": return .help
        case "q": return .cancel
        case "x": return .quit
        case "n": return .newGame
        case "l": return .load
        case "k": return .save
        case "\u{1B}": return .cancel
        default: return nil
        }
    }
}

final class InputReader {
    private var originalTermios = termios()
    private(set) var mode: InputMode = .line
    private var rawActive = false

    func beginCapture() throws {
        guard isatty(STDIN_FILENO) == 1 else { return }
        guard tcgetattr(STDIN_FILENO, &originalTermios) == 0 else {
            throw InputError.terminalSetupFailed
        }
        var raw = originalTermios
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw InputError.terminalSetupFailed
        }
        rawActive = true
        mode = .raw
    }

    func endCapture() {
        guard rawActive else { return }
        var restore = originalTermios
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &restore)
        rawActive = false
        mode = .line
    }

    func readCommand(mode gameMode: GameMode) -> ActionCommand? {
        switch mode {
        case .raw:
            return readRawCommand()
        case .line:
            return readLineCommand(gameMode: gameMode)
        }
    }

    private func readRawCommand() -> ActionCommand? {
        var buffer = [UInt8](repeating: 0, count: 3)
        let count = read(STDIN_FILENO, &buffer, 1)
        guard count > 0 else { return nil }
        if buffer[0] == 27 {
            let next = read(STDIN_FILENO, &buffer[1], 2)
            let total = max(1, 1 + next)
            return InputParser.parse(bytes: Array(buffer.prefix(total)))
        }
        return InputParser.parse(bytes: [buffer[0]])
    }

    private func readLineCommand(gameMode: GameMode) -> ActionCommand? {
        let prompt = gameMode == .title ? "Choice> " : "Action> "
        print(prompt, terminator: "")
        fflush(stdout)
        guard let line = readLine(), let char = line.first else { return nil }
        return InputParser.parse(character: char) ?? ActionCommand.none
    }
}
