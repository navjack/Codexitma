#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif
import Foundation

enum PlatformRuntimeSupport {
    static func writeError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    static func exitFailure(_ code: Int32 = 1) -> Never {
#if canImport(WinSDK)
        ExitProcess(UInt32(max(code, 0)))
        fatalError("ExitProcess returned unexpectedly.")
#else
        exit(code)
#endif
    }
}
