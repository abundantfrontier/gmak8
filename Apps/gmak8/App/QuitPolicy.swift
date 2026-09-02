import Gmak8XPC

enum QuitIntent: Equatable, Sendable {
    case closeLastWindow
    case quitRequested
    case stopAndQuit
}

enum QuitAction: Equatable, Sendable {
    case becomeAccessory(stopCluster: Bool)
    case showFirstQuitSheet(defaultKeepRunning: Bool)
    case hideWindowsKeepExtra
    case refuseHeadlessKeepExtra
    case stopClusterThenTerminate

    var extraRemains: Bool {
        switch self {
        case .stopClusterThenTerminate:
            return false
        case .becomeAccessory, .showFirstQuitSheet, .hideWindowsKeepExtra, .refuseHeadlessKeepExtra:
            return true
        }
    }

    var clusterStays: Bool {
        switch self {
        case .becomeAccessory(let stopCluster):
            return !stopCluster
        case .showFirstQuitSheet, .hideWindowsKeepExtra, .refuseHeadlessKeepExtra:
            return true
        case .stopClusterThenTerminate:
            return false
        }
    }

    var isHeadless: Bool {
        QuitPolicy.isHeadless(clusterStays: clusterStays, extraRemains: extraRemains)
    }
}

enum FirstQuitPrompt {
    static let message = "Keep cluster running in the background? The menu bar extra will stay."
    static let keepRunningTitle = "Keep Running"
    static let stopAndQuitTitle = "Stop and Quit"

    static func defaultKeepRunning(keepClusterRunningOnQuit: Bool) -> Bool {
        keepClusterRunningOnQuit
    }

    static func keepRunningChosen(firstButton: Bool, defaultKeepRunning: Bool) -> Bool {
        firstButton ? defaultKeepRunning : !defaultKeepRunning
    }
}

struct QuitPolicy: Equatable, Sendable {
    var keepClusterRunningOnQuit: Bool
    var hasAskedFirstQuit: Bool

    func action(for intent: QuitIntent) -> QuitAction {
        switch intent {
        case .closeLastWindow:
            return .becomeAccessory(stopCluster: !keepClusterRunningOnQuit)
        case .stopAndQuit:
            return .stopClusterThenTerminate
        case .quitRequested:
            if !hasAskedFirstQuit {
                return .showFirstQuitSheet(
                    defaultKeepRunning: FirstQuitPrompt.defaultKeepRunning(
                        keepClusterRunningOnQuit: keepClusterRunningOnQuit
                    )
                )
            }
            if keepClusterRunningOnQuit {
                return .refuseHeadlessKeepExtra
            }
            return .stopClusterThenTerminate
        }
    }

    func applyingSheetChoice(_ keepRunning: Bool) -> (policy: QuitPolicy, action: QuitAction) {
        var next = self
        next.hasAskedFirstQuit = true
        next.keepClusterRunningOnQuit = keepRunning
        let action: QuitAction = keepRunning ? .hideWindowsKeepExtra : .stopClusterThenTerminate
        return (next, action)
    }

    static func isHeadless(clusterStays: Bool, extraRemains: Bool) -> Bool {
        clusterStays && !extraRemains
    }
}

enum ClusterRestart {
    static func shouldStart(pending: Bool, state: ClusterState) -> Bool {
        pending && (state == .stopped || state == .failed)
    }
}

enum ProductWindowIdentity {
    static let sceneID = "main"
    static let title = "gmak8"
    static let recoverySceneID = "recovery"
    static let recoveryTitle = "Recovery"

    static func isProductWindow(identifier: String?, title: String, isStatusBar: Bool) -> Bool {
        if isStatusBar {
            return false
        }
        if isRecoveryWindow(identifier: identifier, title: title, isStatusBar: isStatusBar) {
            return false
        }
        if identifier == sceneID {
            return true
        }
        if isSettings(identifier: identifier, title: title) {
            return false
        }
        return title == Self.title
    }

    static func isRecoveryWindow(identifier: String?, title: String, isStatusBar: Bool) -> Bool {
        if isStatusBar {
            return false
        }
        if identifier == recoverySceneID {
            return true
        }
        return title == recoveryTitle
    }

    static func isResetSheetHost(identifier: String?, title: String, isStatusBar: Bool, isPanel: Bool) -> Bool {
        if isStatusBar || isPanel {
            return false
        }
        return isRecoveryWindow(identifier: identifier, title: title, isStatusBar: false)
            || isProductWindow(identifier: identifier, title: title, isStatusBar: false)
    }

    static func isSettings(identifier: String?, title: String) -> Bool {
        for value in [identifier ?? "", title] {
            let lower = value.lowercased()
            if lower.contains("setting") || lower.contains("preference") {
                return true
            }
        }
        return false
    }

    static func shouldHideWhenKeepingExtra(isStatusBar: Bool) -> Bool {
        !isStatusBar
    }
}
