cask "codex-quota-pet" do
  version "0.2.4"
  sha256 "82e9cbcdccf928d5aac8313d4b8db53c26a91929e6d096d143fcbe7b4e30d6f0"

  url "https://github.com/HZGuoo/codex-quota-pet/releases/download/v#{version}/CodexQuotaPet-#{version}-macos-universal.zip"
  name "Codex Quota Pet"
  desc "Privacy-first local usage and workflow monitor for Codex"
  homepage "https://github.com/HZGuoo/codex-quota-pet"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "Codex Quota Pet.app"

  zap trash: [
    "~/Library/Preferences/io.github.HZGuoo.CodexQuotaPet.plist",
  ]
end
