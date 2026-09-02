import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("gmak8")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(StatusText.displayName(session.status.state))
                .foregroundStyle(.secondary)
            if let step = session.status.step {
                Text(step)
                    .foregroundStyle(.secondary)
            }
            Text(StatusPresentation.productLine())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(StatusPresentation.nestedVirtLine(session.status.nestedVirt))
                .font(.caption)
            if let error = session.connectionError {
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            } else if let lastError = session.status.lastError, !lastError.isEmpty {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            HStack {
                if session.canStart {
                    Button("Start") {
                        session.startCluster()
                    }
                } else {
                    Button("Stop") {
                        session.stopCluster()
                    }
                    .disabled(!session.canStop)
                }
            }
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            appDelegate.bindOpenWindow(openWindow)
        }
    }
}
