import Combine
import ServiceManagement

enum LaunchAtLoginServiceStatus {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
    func openLoginItemsSettings()
}

@MainActor
final class NativeLaunchAtLoginService: LaunchAtLoginServicing {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginServiceStatus {
        switch service.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var notice: String?

    private let service: LaunchAtLoginServicing

    init(service: LaunchAtLoginServicing) {
        self.service = service
        refresh()
    }

    func refresh() {
        apply(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
            refresh()
        } catch {
            refresh()
            let action = enabled ? "enabled" : "disabled"
            notice = "Open at start could not be \(action): \(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }

    private func apply(_ status: LaunchAtLoginServiceStatus) {
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
        switch status {
        case .requiresApproval:
            notice = "Approval required in System Settings before Open Ratio can open at login."
        case .unavailable:
            notice = "Open at start is unavailable on this Mac."
        case .notRegistered, .enabled:
            notice = nil
        }
    }
}
