class Runnerctl < Formula
  desc "Manage GitHub Actions self-hosted runners on macOS and Linux"
  homepage "https://github.com/AdemKao/runners-self-host-management"
  head "https://github.com/AdemKao/runners-self-host-management.git", branch: "main"
  license "MIT"

  depends_on "gh"

  def install
    libexec.install "runnerctl" => "runnerctl-frontend"
    libexec.install "bin/runnerctl" => "runnerctl-core"

    chmod 0755, libexec/"runnerctl-frontend"
    chmod 0755, libexec/"runnerctl-core"

    (bin/"runnerctl").write_env_script(
      libexec/"runnerctl-frontend",
      RUNNERCTL_CORE: libexec/"runnerctl-core"
    )

    generate_completions_from_executable(
      bin/"runnerctl",
      "completion"
    )
  end

  test do
    assert_equal "0.3.1", shell_output("#{bin}/runnerctl version").strip
    assert_match "AI AGENT", shell_output("#{bin}/runnerctl --help")
    assert_match '"agent_ready": true', shell_output("#{bin}/runnerctl agent --json")
    assert_match '"current_version":"0.3.1"', shell_output("RUNNERCTL_LATEST_VERSION=0.3.1 RUNNERCTL_INSTALL_METHOD=homebrew #{bin}/runnerctl upgrade --check --json")
  end
end
