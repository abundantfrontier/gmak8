import Gmak8Kit
import SwiftUI

struct ClusterAssetsView: View {
    @ObservedObject var assets: ClusterAssetSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.assetsTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Text(OnboardingCopy.assetsBody)
                .foregroundStyle(.secondary)
            Text(OnboardingCopy.k3sAirgapHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            if GuestAssetPin.bundled.signed.hasStubDigest {
                Text(OnboardingCopy.guestDigestUnpublished)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(OnboardingCopy.guestLocalFileHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(assets.visibleAssets, id: \.self) { kind in
                assetRow(kind)
            }
        }
    }

    private func assetRow(_ kind: OnboardingAssetKind) -> some View {
        let status = assets.assetStatus[kind] ?? .missing
        let canDownload = OnboardingAssets.remoteDownloadEnabled(kind)
        let canChoose = OnboardingAssets.chooseFileEnabled(kind)
        return VStack(alignment: .leading, spacing: 6) {
            Text(kind.title)
                .fontWeight(.semibold)
            Text(kind.defaultSource)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(kind.fileName)  \(kind.sizeBudget)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(statusText(status, kind: kind))
                .font(.caption)
                .foregroundStyle(statusColor(status))
                .textSelection(.enabled)
            HStack {
                if canDownload {
                    Button(OnboardingCopy.downloadThisPack) {
                        assets.download(kind)
                    }
                    .disabled(status == .working || status == .ready)
                }
                if canChoose {
                    Button(OnboardingCopy.useLocalFile) {
                        assets.chooseFile(kind)
                    }
                    .disabled(status == .working)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusText(_ status: AssetRowStatus, kind: OnboardingAssetKind) -> String {
        switch status {
        case .missing:
            if OnboardingAssets.remoteDownloadEnabled(kind) {
                return "Ready to download"
            }
            if kind == .guest {
                return "Pick a Linux .img or .raw"
            }
            if !OnboardingAssets.isRequiredToContinue(kind) {
                return "Optional for this step"
            }
            return "Needed"
        case .ready:
            return "Verified"
        case .working:
            return "Downloading…"
        case .failed(let message):
            return message
        }
    }

    private func statusColor(_ status: AssetRowStatus) -> Color {
        switch status {
        case .failed:
            return .red
        case .missing, .working, .ready:
            return .secondary
        }
    }
}
