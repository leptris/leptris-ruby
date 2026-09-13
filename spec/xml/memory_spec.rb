# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Memory hygiene", if: RUBY_ENGINE == "ruby" do
  # leptris-ruby#147 part 1: the last-walked document survives GC
  # because CRuby conservatively scans the native machine stack —
  # stale VALUEs from the last children/fetch C call pin exactly
  # the last-touched cluster. Overwriting those stack slots (deep
  # recursion) releases it. This spec pins residue-not-retention;
  # a plain "collects after GC" assertion would be flaky by design.
  def scribble_stack(n)
    return 0 if n.zero?
    x = [n] * 8
    scribble_stack(n - 1) + x.sum / 8
  end

  it "releases the last-walked document once the native stack is overwritten" do
    20.times do |i|
      n = i == 19 ? 5 : 50
      doc = described_module::Document.parse(
        %(<r>#{Array.new(n) { "<e/>" }.join}</r>))
      doc.root.children.each { |k| k.children.to_a }
    end
    3.times { GC.start }
    # Bounded, one-doc deep: the conservative stack pins the last
    # cluster on some platforms (observed on MRI 3.4 x86/arm
    # Linux) and releases it outright on others (macOS runners,
    # Ruby 4.0) — either way it NEVER grows past one document.
    expect(count_elements).to be <= 51

    # Same-depth C activity overwrites the stale native slots
    # deterministically (the mechanism the standalone repro shows
    # with deep Ruby recursion; under rspec the framework's own C
    # frames sit deeper, so scribble at the leptris C depth).
    5.times do
      doc = described_module::Document.parse("<r><e/><e/></r>")
      doc.root.children.to_a
    end
    3.times { GC.start }
    # The original 50-element cluster is RELEASED; what remains is
    # at most the last dummy document's own three elements (root +
    # two <e/>) — the same conservative-stack residue, one doc
    # deep, never growing. Platforms without the pin (macOS
    # runners, Ruby 4.0) release that too: 0.
    expect(count_elements).to be <= 3
  end

  private

  def described_module
    ::Leptris::XML
  end

  def count_elements
    count = 0
    ObjectSpace.each_object(::Leptris::XML::Element) { count += 1 }
    count
  end
end
