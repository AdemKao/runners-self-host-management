class Runnerctl < Formula
  desc "Manage GitHub Actions self-hosted runners on macOS and Linux"
  homepage "https://github.com/AdemKao/runners-self-host-management"
  head "https://github.com/AdemKao/runners-self-host-management.git", branch: "main"
  license "MIT"

  depends_on "gh"

  def install
    libexec.install "runnerctl" => "runnerctl-frontend"
    libexec.install "runnerctl-base" => "runnerctl-base"
    libexec.install "bin/runnerctl" => "runnerctl-core"
    libexec.install "bin/runnerctl-cleanup" => "runnerctl-cleanup"
    libexec.install "bin/runnerctl-host" => "runnerctl-host"
    libexec.install "bin/runnerctl-ci" => "runnerctl-ci"
    libexec.install "bin/runnerctl-hooks" => "runnerctl-hooks"
    libexec.install "bin/runnerctl-queue" => "runnerctl-queue"

    chmod 0755, libexec/"runnerctl-frontend"
    chmod 0755, libexec/"runnerctl-base"
    chmod 0755, libexec/"runnerctl-core"
    chmod 0755, libexec/"runnerctl-cleanup"
    chmod 0755, libexec/"runnerctl-host"
    chmod 0755, libexec/"runnerctl-ci"
    chmod 0755, libexec/"runnerctl-hooks"
    chmod 0755, libexec/"runnerctl-queue"

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
    assert_equal "0.4.2", shell_output("#{bin}/runnerctl version").strip
    assert_match "AI AGENT", shell_output("#{bin}/runnerctl --help")
    assert_match "workspace cleanup", shell_output("#{bin}/runnerctl cleanup --help")
    assert_match "host prerequisites", shell_output("#{bin}/runnerctl host --help")
    assert_match "GitHub Actions workflows", shell_output("#{bin}/runnerctl ci --help")
    assert_match "safe job concurrency", shell_output("#{bin}/runnerctl capacity --help")
    assert_match "host-wide execution gate", shell_output("#{bin}/runnerctl queue --help")
    assert_match '"agent_ready": true', shell_output("#{bin}/runnerctl agent --json")
    assert_match '"current_version":"0.4.2"', shell_output("RUNNERCTL_LATEST_VERSION=0.4.2 RUNNERCTL_INSTALL_METHOD=homebrew #{bin}/runnerctl upgrade --check --json")
  end
end
