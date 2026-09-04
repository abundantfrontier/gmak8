import Foundation
import Testing

@testable import Gmak8Kubernetes

struct WorkloadsTests {
    @Test func emptyCopyMatchesDesign() {
        #expect(WorkloadsCopy.empty == "Apply a manifest, or gmak8 build an image and deploy.")
        #expect(!WorkloadsCopy.empty.lowercased().contains("nginx"))
        #expect(WorkloadsCopy.pods == "Pods")
        #expect(WorkloadsCopy.noShell.contains("distroless"))
        #expect(WorkloadsCopy.noShell.contains("Logs"))
        #expect(WorkloadKind.allCases.first == .pod)
    }

    @Test func fakeListsPodsInOneNamespace() async throws {
        let client = FakeWorkloadsClient()
        let all = try await client.list(kind: .pod, scope: .all)
        #expect(all.count == 1)
        let filtered = try await client.list(kind: .pod, scope: .named("default"))
        #expect(filtered.isEmpty)
        let system = try await client.list(kind: .pod, scope: .named("kube-system"))
        #expect(system.map(\.name) == ["coredns"])
        let deploys = try await client.list(kind: .deployment, scope: .all)
        #expect(deploys.isEmpty)
    }

    @Test func logCapKeepsLastTenThousandLines() {
        let lines = (1...10_005).map { "line \($0)" }.joined(separator: "\n")
        let clipped = PodLogCap.clipped(lines)
        let clippedLines = clipped.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(clippedLines.count == PodLogCap.maxLines)
        #expect(clippedLines.first == "line 6")
        #expect(clippedLines.last == "line 10005")
    }

    @Test func secretRedactorHidesEnvValuesAndKeepsSecretRefs() throws {
        struct Sample: Encodable {
            var env: [[String: String]]
            var data: [String: String]
        }
        let yaml = try SecretRedactor.yaml(
            Sample(
                env: [["name": "TOKEN", "value": "super-secret"]],
                data: ["password": "hunter2"]
            )
        )
        #expect(!yaml.contains("super-secret"))
        #expect(!yaml.contains("hunter2"))
        #expect(yaml.contains(WorkloadsCopy.secretValue))
        #expect(
            SecretRedactor.envDisplay(
                value: "x",
                secretName: nil,
                secretKey: nil
            ) == WorkloadsCopy.secretValue
        )
        #expect(
            SecretRedactor.envDisplay(
                value: nil,
                secretName: "db",
                secretKey: "password"
            ) == "secret db/password"
        )
    }

    @Test func ageFormatsSecondsMinutesHoursDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(WorkloadAge.format(from: now, now: now) == "0s")
        #expect(WorkloadAge.format(from: now.addingTimeInterval(-90), now: now) == "1m")
        #expect(WorkloadAge.format(from: now.addingTimeInterval(-7200), now: now) == "2h")
        #expect(WorkloadAge.format(from: now.addingTimeInterval(-172_800), now: now) == "2d")
        #expect(WorkloadAge.format(from: nil, now: now) == "—")
    }
}
