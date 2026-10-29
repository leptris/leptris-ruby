# frozen_string_literal: true

# leptris#1874 binding wiring: Element#namespace_declarations_snapshot
# exposes the engine's bulk in-scope declaration snapshot (libleptris
# 1.9.388) as {path:, prefix:, href:} rows — the exact contract
# lutaml-model#1054's plan hydrator consumes, replacing the per-node
# namespace_definitions union walk (lutaml-model#1018).

require "spec_helper"

RSpec.describe "Element#namespace_declarations_snapshot" do
  let(:doc) do
    Leptris::XML::Document.parse(<<~XML)
      <w:doc xmlns:w="urn:root" xmlns:x="urn:x">
        <w:sec xmlns:w="urn:s1">
          <w:p xmlns:x="urn:p1"><w:t>body</w:t></w:p>
        </w:sec>
        <plain>no declarations here</plain>
      </w:doc>
    XML
  end
  let(:root) { doc.root }

  it "is defined (the engine pin carries the 1.9.388 face)" do
    expect(root).to respond_to(:namespace_declarations_snapshot)
  end

  it "returns the root's own declarations with an empty path" do
    rows = root.namespace_declarations_snapshot
    own = rows.select { |r| r[:path].empty? }
    expect(own).to contain_exactly(
      { path: [], prefix: "w", href: "urn:root" },
      { path: [], prefix: "x", href: "urn:x" },
    )
  end

  it "reports descendants ancestor-first with their element paths" do
    rows = root.namespace_declarations_snapshot
    sec = rows.find { |r| r[:path] == %w[sec] && r[:prefix] == "w" }
    expect(sec[:href]).to eq("urn:s1")

    p1 = rows.find { |r| r[:path] == %w[sec p] && r[:prefix] == "x" }
    expect(p1[:href]).to eq("urn:p1")
  end

  it "walks in document order and never repeats the root at depth 0" do
    rows = root.namespace_declarations_snapshot
    expect(rows.first[:path]).to eq([])
    depths = rows.map { |r| r[:path].size }
    expect(depths).to eq(depths.sort)
  end

  it "returns an empty array for a declaration-free subtree" do
    plain = root.children.find { |c| c.name == "plain" }
    expect(plain.namespace_declarations_snapshot).to eq([])
  end

  it "rows agree with the per-node namespace_definitions union" do
    # The parity contract: the snapshot must be exactly what walking
    # every element and unioning namespace_definitions produces.
    walked = []
    stack = [[root, []]]
    until stack.empty?
      elem, path = stack.pop
      elem.namespace_definitions.each do |ns|
        walked << { path: path, prefix: ns.prefix, href: ns.href }
      end
      elem.children.reverse_each do |c|
        stack.push([c, path + [c.name]]) if c.is_a?(Leptris::XML::Element)
      end
    end
    expect(root.namespace_declarations_snapshot).to contain_exactly(*walked)
  end
end
