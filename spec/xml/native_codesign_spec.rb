# frozen_string_literal: true

# leptris#1623: macOS native bundles with stale or absent
# signatures are intermittently SIGKILLed by dyld on macOS 14.x.
# The loader pre-verifies and re-stamps BEFORE dyld ever sees the
# binary (a kill cannot be rescued); the build re-signs after
# every byte-touching step. These specs pin the heal primitive.
require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "native bundle signature heal", if: RUBY_PLATFORM.include?("darwin") do
  let(:dylib) do
    built = File.expand_path("lib/libleptris.dylib", Bundler.root)
    skip "vendored engine dylib not built" unless File.exist?(built)
    tmp = File.join(Dir.mktmpdir, "libleptris.dylib")
    FileUtils.cp(built, tmp)
    tmp
  end

  def signature_valid?(path)
    system("codesign", "--verify", path, out: File::NULL, err: File::NULL)
  end

  it "re-stamps a stripped dylib so codesign --verify passes" do
    system("codesign", "--remove-signature", dylib,
           out: File::NULL, err: File::NULL)
    expect(signature_valid?(dylib)).to be false
    expect(Leptris.resign_bundle_if_needed(dylib)).to be true
    expect(signature_valid?(dylib)).to be true
  end

  it "leaves a valid signature untouched" do
    expect(signature_valid?(dylib)).to be true
    before = File.mtime(dylib)
    expect(Leptris.resign_bundle_if_needed(dylib)).to be true
    expect(File.mtime(dylib)).to eq(before)
  end

  it "answers false for a missing path" do
    expect(Leptris.resign_bundle_if_needed(
             "/no/such/bundle.dylib")).to be false
  end
end
