import Foundation
import NIO
import SwiftkubeClient

enum SwiftkubeClientFactory {
    /// Swiftkube defaults to `.shared(MultiThreadedEventLoopGroup(numberOfThreads: 1))` per
    /// client. Cluster/Workloads/KubeVirt poll every 8s and `syncShutdown()` does not stop a
    /// `.shared` group, so the UI leaked thousands of threads and failed kubeconfig reads with
    /// Cocoa error 256. Use NIO's process singleton instead.
    static func make(kubeConfig: KubeConfig, contextName: String) -> KubernetesClient? {
        KubernetesClient(
            kubeConfig: kubeConfig,
            contextName: contextName,
            provider: .shared(MultiThreadedEventLoopGroup.singleton)
        )
    }
}
