import Foundation
import Gmak8Kit
import Testing

@testable import Gmak8XPC

struct TranslocationTests {
    @Test func applicationsBundleIsAllowed() {
        let checker = TranslocationChecker()
        let url = URL(fileURLWithPath: "/Applications/gmak8.app")
        #expect(!checker.shouldRefuseRegister(bundleURL: url))
        #expect(checker.isInsideApplications(url))
        #expect(!checker.isTranslocated(url))
    }

    @Test func downloadsAndHomeCopiesAreRefused() {
        let checker = TranslocationChecker()
        #expect(
            checker.shouldRefuseRegister(
                bundleURL: URL(fileURLWithPath: "/Users/tester/Downloads/gmak8.app")
            )
        )
        #expect(
            checker.shouldRefuseRegister(
                bundleURL: URL(fileURLWithPath: "/Users/tester/Applications/gmak8.app")
            )
        )
    }

    @Test func quarantineTranslocationPathIsRefused() {
        let checker = TranslocationChecker()
        let url = URL(
            fileURLWithPath:
                "/private/var/folders/xx/yyyy/T/AppTranslocation/ABCDEF/d/gmak8.app"
        )
        #expect(checker.isTranslocated(url))
        #expect(checker.shouldRefuseRegister(bundleURL: url))
    }

    @Test func onboardingPermissionsRefuseTranslocatedAndDownloads() {
        let checker = TranslocationChecker()
        let downloads = URL(fileURLWithPath: "/Users/tester/Downloads/gmak8.app")
        let translocated = PermissionsProbe.evaluate(
            virtualizationSupported: true,
            nestedVirtualizationSupported: true,
            shouldRefuseLaunchAgent: checker.shouldRefuseRegister(bundleURL: downloads)
        )
        #expect(translocated == .translocated)
        #expect(!translocated.canContinue)
        #expect(PermissionsProbe.message(translocated) == OnboardingCopy.moveToApplications)

        let applications = URL(fileURLWithPath: "/Applications/gmak8.app")
        let ready = PermissionsProbe.evaluate(
            virtualizationSupported: true,
            nestedVirtualizationSupported: false,
            shouldRefuseLaunchAgent: checker.shouldRefuseRegister(bundleURL: applications)
        )
        #expect(ready == .ready(nestedVirtualizationSupported: false))
        #expect(ready.canContinue)
    }
}

struct CoreLaunchAgentTests {
    @Test func labelsMatchLaunchdContract() {
        #expect(CoreLaunchAgent.label == "dev.gmak8.core")
        #expect(CoreLaunchAgent.plistName == "dev.gmak8.core.plist")
        #expect(CoreLaunchAgent.bundleProgram == "Contents/MacOS/gmak8-core")
    }

    @Test func twoLoginItemsCopyNamesAgentAndMenuExtra() {
        let copy = CoreLaunchAgent.twoLoginItemsExplanation
        #expect(copy.contains("two Login Items"))
        #expect(copy.contains("gmak8-core"))
        #expect(copy.contains("LaunchAgent"))
        #expect(copy.contains("menu extra"))
    }

    @Test func registerRefusesTranslocatedApp() throws {
        let service = MockLaunchAgent()
        #expect(throws: EngineErrorCode.translocated) {
            try CoreLaunchAgent.register(
                bundleURL: URL(fileURLWithPath: "/Users/tester/Downloads/gmak8.app"),
                service: service
            )
        }
        #expect(service.registerCount == 0)
    }

    @Test func registerSucceedsFromApplications() throws {
        let service = MockLaunchAgent()
        try CoreLaunchAgent.register(
            bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"),
            service: service
        )
        #expect(service.registerCount == 1)
        try CoreLaunchAgent.unregister(service: service)
        #expect(service.unregisterCount == 1)
    }
}

struct ExtraLoginItemTests {
    @Test func registerRefusesTranslocatedApp() throws {
        let service = MockLaunchAgent()
        #expect(throws: EngineErrorCode.translocated) {
            try ExtraLoginItem.register(
                bundleURL: URL(fileURLWithPath: "/Users/tester/Downloads/gmak8.app"),
                service: service
            )
        }
        #expect(service.registerCount == 0)
    }

    @Test func registerSucceedsFromApplications() throws {
        let service = MockLaunchAgent()
        try ExtraLoginItem.register(
            bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"),
            service: service
        )
        #expect(service.registerCount == 1)
        try ExtraLoginItem.unregister(service: service)
        #expect(service.unregisterCount == 1)
    }
}

struct LaunchAtLoginPolicyTests {
    @Test func enablingRegistersExtraAndAgent() {
        let mutation = LaunchAtLoginPolicy.mutation(enabling: true)
        #expect(mutation.extra == .register)
        #expect(mutation.agent == .register)
    }

    @Test func disablingUnregistersExtraOnly() {
        let mutation = LaunchAtLoginPolicy.mutation(enabling: false)
        #expect(mutation.extra == .unregister)
        #expect(mutation.agent == .keep)
    }

    @Test func extraLaunchRegistersAgentNotExtra() {
        let mutation = LaunchAtLoginPolicy.extraDidLaunch()
        #expect(mutation.extra == .keep)
        #expect(mutation.agent == .register)
    }
}

private final class MockLaunchAgent: LaunchAgentRegistering, @unchecked Sendable {
    var registerCount = 0
    var unregisterCount = 0

    func register() throws {
        registerCount += 1
    }

    func unregister() throws {
        unregisterCount += 1
    }
}
