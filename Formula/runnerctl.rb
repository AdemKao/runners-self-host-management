class Runnerctl < Formula
  desc "Manage GitHub Actions self-hosted runners on macOS and Linux"
  homepage "https://github.com/AdemKao/runners-self-host-management"
  head "https://github.com/AdemKao/runners-self-host-management.git", branch: "main"
  license "MIT"

  depends_on "gh"

  def install
    libexec.install "runnerctl" => "runnerctl-frontend"
    libexec.install "runnerctl-base" => "runnerctl-base"
    libexec.install "runnerctl-base-v07" => "runnerctl-base-v07"
    libexec.install "runnerctl-base-v06" => "runnerctl-base-v06"
    libexec.install "runnerctl-base-v05" => "runnerctl-base-v05"
    libexec.install "runnerctl-base-legacy" => "runnerctl-base-legacy"
    libexec.install "bin/runnerctl" => "runnerctl-core"
    libexec.install "bin/runnerctl-v07" => "runnerctl-core-v07"
    libexec.install "bin/runnerctl-legacy" => "runnerctl-core-legacy"
    libexec.install "bin/runnerctl-cleanup" => "runnerctl-cleanup"
    libexec.install "bin/runnerctl-host" => "runnerctl-host"
    libexec.install "bin/runnerctl-ci" => "runnerctl-ci"
    libexec.install "bin/runnerctl-hooks" => "runnerctl-hooks"
    libexec.install "bin/runnerctl-queue" => "runnerctl-queue"
    libexec.install "bin/runnerctl-queue-legacy" => "runnerctl-queue-legacy"
    libexec.install "bin/runnerctl-scheduler" => "runnerctl-scheduler"
    libexec.install "bin/runnerctl-scheduler-core" => "runnerctl-scheduler-core"
    libexec.install "bin/runnerctl-notify" => "runnerctl-notify"
    libexec.install "bin/runnerctl-notify-provider-telegram" => "runnerctl-notify-provider-telegram"
    libexec.install "bin/runnerctl-notify-provider-line" => "runnerctl-notify-provider-line"
    libexec.install "bin/runnerctl-notify-provider-webhook" => "runnerctl-notify-provider-webhook"
    libexec.install "bin/runnerctl-bot" => "runnerctl-bot"
    libexec.install "bin/runnerctl-bot-controller.py" => "runnerctl-bot-controller.py"
    libexec.install "bin/runnerctl-monitor" => "runnerctl-monitor"

    %w[runnerctl-frontend runnerctl-base runnerctl-base-v07 runnerctl-base-v06 runnerctl-base-v05 runnerctl-base-legacy runnerctl-core runnerctl-core-v07 runnerctl-core-legacy runnerctl-cleanup runnerctl-host runnerctl-ci runnerctl-hooks runnerctl-queue runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core runnerctl-notify runnerctl-notify-provider-telegram runnerctl-notify-provider-line runnerctl-notify-provider-webhook runnerctl-bot runnerctl-bot-controller.py runnerctl-monitor].each do |name|
      chmod 0755, libexec/name
    end

    (libexec/"bin").mkpath
    %w[runnerctl-host runnerctl-ci runnerctl-hooks runnerctl-queue runnerctl-queue-legacy runnerctl-scheduler runnerctl-scheduler-core runnerctl-notify runnerctl-notify-provider-telegram runnerctl-notify-provider-line runnerctl-notify-provider-webhook runnerctl-bot runnerctl-bot-controller.py runnerctl-monitor].each do |name|
      (libexec/"bin").install_symlink libexec/name
    end

    (bin/"runnerctl").write_env_script(
      libexec/"runnerctl-frontend",
      RUNNERCTL_CORE: libexec/"runnerctl-core"
    )

    generate_completions_from_executable(bin/"runnerctl", "completion")
  end

  test do
    assert_equal "0.8.0", shell_output("#{bin}/runnerctl version").strip
    assert_match "AI AGENT", shell_output("#{bin}/runnerctl --help")
    assert_match "GitHub-native scheduling", shell_output("#{bin}/runnerctl --help")
    assert_match "Notifications and integrations", shell_output("#{bin}/runnerctl --help")
    assert_match "Read-only Bot/API controller", shell_output("#{bin}/runnerctl --help")
    assert_match "Authoritative job outcome monitoring", shell_output("#{bin}/runnerctl --help")
    assert_match "Legacy host-side admission gate", shell_output("#{bin}/runnerctl queue --help")
    assert_match "GitHub-native scheduler", shell_output("#{bin}/runnerctl scheduler --help")
    assert_match "Notification providers", shell_output("#{bin}/runnerctl notify providers")
    assert_match '"enabled":false', shell_output("#{bin}/runnerctl scheduler status --json")
    assert_match '"history_count":0', shell_output("#{bin}/runnerctl monitor status --json")
    assert_match '"current_version":"0.8.0"', shell_output("RUNNERCTL_LATEST_VERSION=0.8.0 RUNNERCTL_INSTALL_METHOD=homebrew #{bin}/runnerctl upgrade --check --json")
  end
end