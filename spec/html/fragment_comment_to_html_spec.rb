# frozen_string_literal: true

require "spec_helper"

# moxml#389 follow-up: Fragment#to_html maps fragment children
# through to_html — every node kind that can survive in a fragment
# must answer it. Comments join the set with the #389 fix (an
# in-body comment now survives parse_fragment); Text is special-
# cased (raw content) in Fragment#to_html itself.
RSpec.describe "Leptris::HTML::Fragment#to_html node-kind coverage" do
  it "serializes a fragment whose children include a comment" do
    frag = Leptris::HTML.parse_fragment(
      "<!-- c --><p>Test</p>", context: :body
    )
    expect(frag.to_html).to include("<!-- c -->")
    expect(frag.to_html).to include("<p>Test</p>")
  end

  it "answers to_html on the comment node itself" do
    frag = Leptris::HTML.parse_fragment(
      "<!-- c --><p>Test</p>", context: :body
    )
    comment = frag.children.first
    expect(comment.to_html).to eq("<!-- c -->")
  end
end
