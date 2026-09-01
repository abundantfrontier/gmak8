import Gmak8Kit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("gmak8")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Cluster stopped")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
        .onAppear {
            _ = Gmak8Kit.version
        }
    }
}

#Preview {
    ContentView()
}
