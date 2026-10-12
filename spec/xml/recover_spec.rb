
# libleptris 1.9.344 (#1660): recover matches XML_PARSE_RECOVER —
# the best-effort tree commits for structural malformations
# instead of returning an empty document.
RSpec.describe "recover structural semantics (1.9.344, #1660)" do
  {
    "mismatched close" => %q(<r><a><b>text</wrong></a></r>),
    "unclosed element" => %q(<r><a><b>text</b>),
  }.each do |shape, xml|
    it "commits the best-effort tree for #{shape}" do
      doc = Leptris::XML::Document.parse(xml, recover: true)
      expect(doc.root).not_to be_nil
      expect(doc.root.name).to eq("r")
      expect(doc.root.to_xml).to eq(%(<r><a><b>text</b></a></r>))
    end
  end
end
