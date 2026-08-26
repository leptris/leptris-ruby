# frozen_string_literal: true

require "spec_helper"
RSpec.describe "round V: fragments search, error position" do
  it "searches fragments with xpath/css/at_*" do
    doc = Leptris::XML.parse("<r/>")
    frag = doc.fragment(%(<a x="1"><n>one</n></a>t<b><n>two</n></b>))
    expect(frag.xpath(".//n").map(&:content)).to eq(%w[one two])
    expect(frag.at_xpath("./a")["x"]).to eq("1")
    expect(frag.css("b > n").map(&:content)).to eq(%w[two])
    expect(frag.at_css("a").name).to eq("a")
    expect(frag.search("a").length).to eq(1)
  end

  it "exposes the thread-global last-failure position" do
    # Thread-global and sticky (the C contract): it reflects the
    # most recent failure on this thread, so only the post-failure
    # shape is assertable here.
    recovered = Leptris::XML.parse("<broken", recover: true)
    expect(recovered.last_error_position).to be_a(Array)
    expect(recovered.last_error_position.length).to eq(2)
  end
end

