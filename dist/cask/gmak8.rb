cask "gmak8" do
  version "0.0.1"
  sha256 :no_check

  url "https://github.com/gmak8/gmak8/releases/download/v#{version}/gmak8-#{version}.dmg"
  name "gmak8"
  desc "Local Kubernetes cluster for Apple Silicon"
  homepage "https://github.com/gmak8/gmak8"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "gmak8.app"

  zap trash: [
    "~/Library/Application Support/dev.gmak8.app",
    "~/Library/Caches/dev.gmak8.app",
    "~/Library/Logs/gmak8",
    "~/Library/Preferences/dev.gmak8.app.plist",
  ]
end
