# frozen_string_literal: true

require "spec_helper"
require_relative "../ext/check_bundle_linkage"

# The #1739/ruby#481 gate: shipped native bundles must resolve Ruby
# symbols from the loading interpreter — never a linked libruby (the
# 1.9.36x trains recorded the GHA runner's absolute hostedtoolcache
# path in every per-minor artifact, which dlopen-fails on any other
# machine) — and on darwin every load command stays inside the
# loader allowlist. The vectors below are the exact shapes that
# shipped broken.
RSpec.describe CheckBundleLinkage do
  describe ".load_command_violations" do
    it "accepts the loader allowlist (libSystem, @rpath, @loader_path)" do
      otool = "native.bundle:\n" \
              "\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)\n" \
              "\t@rpath/libutf8proc.3.dylib (compatibility version 3.0.0, current version 3.11.0)\n" \
              "\t@loader_path/../liblibleptris.dylib (compatibility version 0.0.0, current version 0.0.0)\n"
      expect(described_class.load_command_violations(otool)).to be_empty
    end

    it "fails the runner-absolute libruby load that shipped in 1.9.36x" do
      otool = "native_3_4.bundle:\n" \
              "\t/Users/runner/hostedtoolcache/Ruby/3.4.11/arm64/lib/libruby.3.4.dylib " \
              "(compatibility version 3.4.0, current version 3.4.11)\n" \
              "\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)\n"
      expect(described_class.load_command_violations(otool))
        .to eq(["/Users/runner/hostedtoolcache/Ruby/3.4.11/arm64/lib/libruby.3.4.dylib"])
    end

    it "fails build-host paths outside the allowlist (Homebrew, /opt, /tmp)" do
      otool = "x.bundle:\n" \
              "\t/opt/homebrew/opt/lzma/lib/liblzma.5.dylib (compatibility version 6.0.0, current version 6.4.0)\n" \
              "\t/tmp/scratch/libevil.dylib (compatibility version 0.0.0, current version 0.0.0)\n"
      expect(described_class.load_command_violations(otool))
        .to contain_exactly("/opt/homebrew/opt/lzma/lib/liblzma.5.dylib",
                            "/tmp/scratch/libevil.dylib")
    end
  end

  describe ".libruby_references" do
    it "is empty for clean linkage output" do
      expect(described_class.libruby_references("libSystem.B.dylib\nlibutf8proc.3.dylib\n")).to be_empty
    end

    it "detects the ELF DT_NEEDED soname recorded on linux artifacts" do
      expect(described_class.libruby_references("libruby.so.3.1\nlibc.so.6\nlibm.so.6\n"))
        .to eq(["libruby.so.3.1"])
    end

    it "detects versioned darwin spellings" do
      expect(described_class.libruby_references("x libruby.3.4.dylib y libruby.dylib z"))
        .to contain_exactly("libruby.3.4.dylib", "libruby.dylib")
    end
  end
end
