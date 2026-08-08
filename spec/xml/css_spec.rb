# frozen_string_literal: true

require "taurus/xml"

RSpec.describe "Taurus::XML CSS selectors (minimal Nokogiri subset)" do
  let(:doc) do
    Taurus::XML::Document.parse(<<~HTML)
      <html>
        <body>
          <div id="main" class="container">
            <h1>Title</h1>
            <p class="lead">Intro</p>
            <p>Body</p>
            <ul>
              <li class="item">A</li>
              <li class="item special">B</li>
              <li class="item">C</li>
            </ul>
            <a href="http://example.com">Link</a>
          </div>
        </body>
      </html>
    HTML
  end

  describe "tag selectors" do
    it "matches by tag name" do
      expect(doc.css("h1").map(&:content)).to eq(["Title"])
      expect(doc.css("p").length).to eq(2)
    end

    it "matches * as wildcard" do
      all = doc.css("*")
      # Every element in the tree: html, body, div, h1, p, p, ul, li, li, li, a
      expect(all.length).to be >= 11
    end
  end

  describe "class selectors" do
    it "matches .class" do
      items = doc.css(".item")
      expect(items.length).to eq(3)
      expect(items.map(&:content)).to eq(%w[A B C])
    end

    it "matches tag.class" do
      leads = doc.css("p.lead")
      expect(leads.length).to eq(1)
      expect(leads.first.content).to eq("Intro")
    end
  end

  describe "id selectors" do
    it "matches #id" do
      main = doc.css("#main")
      expect(main.length).to eq(1)
      expect(main.first["id"]).to eq("main")
    end

    it "matches tag#id" do
      div = doc.css("div#main")
      expect(div.length).to eq(1)
    end
  end

  describe "attribute selectors" do
    it "matches [attr]" do
      with_href = doc.css("[href]")
      expect(with_href.length).to eq(1)
      expect(with_href.first.name).to eq("a")
    end

    it "matches [attr=val]" do
      links = doc.css(%q{[href='http://example.com']})
      expect(links.length).to eq(1)
    end

    it "matches tag[attr=val]" do
      a = doc.css("a[href='http://example.com']")
      expect(a.first.content).to eq("Link")
    end
  end

  describe "descendant / child combinators" do
    it "matches descendant (whitespace)" do
      lis = doc.css("ul li")
      expect(lis.length).to eq(3)
    end

    it "matches direct child (>)" do
      direct = doc.css("ul > li")
      expect(direct.length).to eq(3)
      # body > p should match both <p> children of body
      body_ps = doc.css("body > div > p")
      expect(body_ps.length).to eq(2)
    end

    it "matches nested chains" do
      special = doc.css("div#main ul li.special")
      expect(special.length).to eq(1)
      expect(special.first.content).to eq("B")
    end
  end

  describe "comma-separated multi-selectors" do
    it "matches h1, h2, h3" do
      result = doc.css("h1, h2, h3")
      expect(result.map(&:name)).to eq(%w[h1])
    end

    it "matches div.container, p.lead" do
      result = doc.css("div.container, p.lead")
      expect(result.length).to eq(2)
    end
  end

  describe "pseudo-classes" do
    it "matches :first-child" do
      first = doc.css("li:first-child")
      expect(first.length).to eq(1)
      expect(first.first.content).to eq("A")
    end

    it "matches :last-child" do
      last = doc.css("li:last-child")
      expect(last.length).to eq(1)
      expect(last.first.content).to eq("C")
    end

    it "matches tag:first-child on tag" do
      first_p = doc.css("p:first-child")
      # First <p> child of body — but body's first child is div, so this
      # should return empty (no <p> is the first child of its parent).
      expect(first_p.length).to eq(0)
    end
  end

  describe "at_css (first match)" do
    it "returns the first matching node" do
      lead = doc.at_css("p.lead")
      expect(lead.content).to eq("Intro")
    end

    it "returns nil if no match" do
      expect(doc.at_css("nomatch")).to be_nil
    end
  end

  describe "search (auto-detect CSS vs XPath)" do
    it "uses CSS when input doesn't look like XPath" do
      result = doc.search("li.item")
      expect(result.length).to eq(3)
    end

    it "uses XPath when input looks like XPath" do
      result = doc.search("//li")
      expect(result.length).to eq(3)
    end
  end

  describe "unsupported selectors" do
    it "raises ArgumentError for :nth-child(n)" do
      expect { doc.css("li:nth-child(2)") }
        .to raise_error(ArgumentError, /unsupported pseudo-class/)
    end
  end
end
