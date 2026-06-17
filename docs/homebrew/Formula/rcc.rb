class Rcc < Formula
  desc "macOS companion toolkit — system info, audit, automation"
  homepage "https://github.com/thousandflowers/Raccoon"
  url "https://github.com/thousandflowers/Raccoon/archive/refs/tags/v0.8.0.tar.gz"
  sha256 "PLACEHOLDER_AUTO_UPDATED_BY_RELEASE_WORKFLOW"
  version "0.8.0"
  license "MIT"

  depends_on :macos

  def install
    libexec.install "rcc"
    libexec.install Dir["lib"]
    libexec.install Dir["bin"]
    libexec.install Dir["completions"]

    (bin/"rcc").write_env_script libexec/"rcc"

    man1.install Dir["man/man1/*"]
  end

  def caveats
    <<~EOS
      Raccoon is installed to:
        #{libexec}

      Completions for bash and zsh are available:
        rcc completion bash > /usr/local/etc/bash_completion.d/rcc
        rcc completion zsh  > /usr/local/share/zsh/site-functions/_rcc
    EOS
  end

  test do
    assert_match "Raccoon version #{version}", shell_output("#{bin}/rcc --version")
  end
end
