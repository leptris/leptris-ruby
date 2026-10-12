# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../rakelib/audit_artifacts"

# TODO.final/04 negative proof: the gates FAIL on the two shapes
# they exist for — a tampered/unsigned macOS artifact, and an
# engine-version drift between the vendored library and the pin.
# darwin-only: codesign is the macOS packaging lane (other
# platforms skip, mirroring audit:artifacts).
RSpec.describe AuditArtifacts, if: RUBY_PLATFORM =~ /darwin/ do
  before(:all) do
    skip "codesign unavailable" unless AuditArtifacts.codesign_available?
    @lib = Dir.glob("lib/libleptris.dylib").first ||
           Dir.glob("lib/leptris/vendor/*-darwin/libleptris.dylib").first
    skip "no vendored macOS library in this checkout" unless @lib
  end

  it "detects a tampered artifact (a flipped byte breaks --strict)" do
    Dir.mktmpdir do |dir|
      copy = File.join(dir, "tampered.dylib")
      FileUtils.cp(@lib, copy)
      data = File.binread(copy)
      offset = data.bytesize / 2
      data[offset] = (data[offset].ord ^ 0xFF).chr
      File.binwrite(copy, data)
      expect(AuditArtifacts.signature_ok?(copy)).to be(false)
    end
  end

  it "detects a stripped signature" do
    Dir.mktmpdir do |dir|
      copy = File.join(dir, "unsigned.dylib")
      FileUtils.cp(@lib, copy)
      system("codesign", "--remove-signature", copy,
             out: File::NULL, err: File::NULL)
      expect(AuditArtifacts.signature_ok?(copy)).to be(false)
    end
  end

  it "accepts the shipped artifact" do
    expect(AuditArtifacts.signature_ok?(@lib)).to be(true)
  end

  it "version gate flags drift and accepts the pin" do
    lib_dir = File.dirname(@lib)
    vendored = AuditArtifacts.vendored_version(@lib, lib_dir)
    skip "vendored version unreadable" if vendored.nil? || vendored.empty?

    expect(AuditArtifacts.version_synced?(@lib, lib_dir, vendored))
      .to be(true)
    expect(AuditArtifacts.version_synced?(@lib, lib_dir, "9.9.999"))
      .to be(false)
  end
end
