class Runnerctl < Formula
  desc "Manage GitHub Actions self-hosted runners on macOS and Linux"
  homepage "https://github.com/AdemKao/runners-self-host-management"
  head "https://github.com/AdemKao/runners-self-host-management.git", branch: "main"
  license "MIT"

  depends_on "gh"

  def install
    bin.install "runnerctl"
    chmod 0755, bin/"runnerctl"
    libexec.install "bin/runnerctl" => "runnerctl-core"
    chmod 0755, libexec/"runnerctl-core"
  end

  test do
    assert_equal "0.3.0", shell_output("#{bin}/runnerctl version").strip
    assert_match "AI AGENT", shell_output("#{bin}/runnerctl --help")
    assert_match '"agent_ready": true', shell_output("#{bin}/runnerctl agent --json")
  end
end
