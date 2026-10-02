import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Detects whether the app has "Full Disk Access" (macOS privacy permission).
/// Without it, folders such as Mail, Messages, Safari and other apps' containers can't be read.
public enum FullDiskAccess {
    public enum ProbeResult: Equatable { case readable, denied, missing }

    /// Files that only processes with Full Disk Access can open.
    public static func probePaths(home: String = NSHomeDirectory()) -> [String] {
        [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Safari/CloudTabs.db",
            "\(home)/Library/Safari/Bookmarks.plist",
            "\(home)/Library/Mail",
        ]
    }

    public static func probe(_ path: String) -> ProbeResult {
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return .readable
        }
        return errno == ENOENT ? .missing : .denied
    }

    /// Granted when any protected file can be opened; denied when one exists but is blocked.
    public static func isGranted(home: String = NSHomeDirectory(), probe: (String) -> ProbeResult = FullDiskAccess.probe) -> Bool {
        #if os(macOS)
        var sawDenied = false
        for path in probePaths(home: home) {
            switch probe(path) {
            case .readable: return true
            case .denied: sawDenied = true
            case .missing: continue
            }
        }
        return !sawDenied
        #else
        return true
        #endif
    }

    /// Deep link to System Settings › Privacy & Security › Full Disk Access.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
