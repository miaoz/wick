import AppKit
import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` for open-at-login (macOS 13+).
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> SMAppService.Status {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .enabled {
                return service.status
            }
            try service.register()
        } else if service.status != .notRegistered {
            try service.unregister()
        }
        return service.status
    }

    /// Opens System Settings → Login Items when the user needs to approve the item.
    static func openSystemLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.users?LoginItems") {
            NSWorkspace.shared.open(url)
        }
    }
}
