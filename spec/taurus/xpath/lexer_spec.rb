# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Taurus::XPath.tokenize" do
  describe "basic tokenization" do
    it "tokenizes simple path expressions" do
      tokens = Taurus::XPath.tokenize("/root/child")

      expect(tokens.size).to eq(4)
      expect(tokens[0]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[1]).to include("type" => "NCNAME", "value" => "root")
      expect(tokens[2]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[3]).to include("type" => "NCNAME", "value" => "child")
    end

    it "tokenizes descendant-or-self axis" do
      tokens = Taurus::XPath.tokenize("//child")

      expect(tokens.size).to eq(2)
      expect(tokens[0]).to include("type" => "DOUBLE_SLASH", "value" => "//")
      expect(tokens[1]).to include("type" => "NCNAME", "value" => "child")
    end

    it "tokenizes attribute access" do
      tokens = Taurus::XPath.tokenize("/root/@attr")

      expect(tokens.size).to eq(5)
      expect(tokens[0]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[1]).to include("type" => "NCNAME", "value" => "root")
      expect(tokens[2]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[3]).to include("type" => "AT", "value" => "@")
      expect(tokens[4]).to include("type" => "NCNAME", "value" => "attr")
    end

    it "tokenizes self and parent references" do
      tokens = Taurus::XPath.tokenize("./..")

      expect(tokens.size).to eq(3)
      expect(tokens[0]).to include("type" => "DOT", "value" => ".")
      expect(tokens[1]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[2]).to include("type" => "DOUBLE_DOT", "value" => "..")
    end
  end

  describe "operators" do
    it "tokenizes comparison operators" do
      tokens = Taurus::XPath.tokenize("a = b != c < d <= e > f >= g")

      expect(tokens.size).to eq(13)
      expect(tokens[0]).to include("type" => "NCNAME", "value" => "a")
      expect(tokens[2]).to include("type" => "NCNAME", "value" => "b")
      expect(tokens[3]).to include("type" => "NOT_EQUALS", "value" => "!=")
      expect(tokens[4]).to include("type" => "NCNAME", "value" => "c")
      expect(tokens[5]).to include("type" => "LT", "value" => "<")
      expect(tokens[7]).to include("type" => "LE", "value" => "<=")
      expect(tokens[6]).to include("type" => "NCNAME", "value" => "d")
    end

    it "tokenizes arithmetic operators" do
      tokens = Taurus::XPath.tokenize("a + b - c * d div e mod f")

      expect(tokens.size).to eq(11)
      expect(tokens[0]).to include("type" => "NCNAME", "value" => "a")
      expect(tokens[1]).to include("type" => "PLUS", "value" => "+")
      expect(tokens[2]).to include("type" => "NCNAME", "value" => "b")
      expect(tokens[3]).to include("type" => "MINUS", "value" => "-")
      expect(tokens[4]).to include("type" => "NCNAME", "value" => "c")
      expect(tokens[5]).to include("type" => "STAR", "value" => "*")
      expect(tokens[6]).to include("type" => "NCNAME", "value" => "d")
      expect(tokens[7]).to include("type" => "DIV", "value" => "div")
      expect(tokens[8]).to include("type" => "NCNAME", "value" => "e")
      expect(tokens[9]).to include("type" => "MOD", "value" => "mod")
      expect(tokens[10]).to include("type" => "NCNAME", "value" => "f")
    end

    it "tokenizes logical operators" do
      tokens = Taurus::XPath.tokenize("a and b or c")

      expect(tokens.size).to eq(5)
      expect(tokens[1]).to include("type" => "AND", "value" => "and")
      expect(tokens[3]).to include("type" => "OR", "value" => "or")
    end
  end

  describe "literals" do
    it "tokenizes numbers" do
      tokens = Taurus::XPath.tokenize("123 45.67")

      expect(tokens.size).to eq(2)
      expect(tokens[0]).to include("type" => "NUMBER", "value" => "123")
      expect(tokens[1]).to include("type" => "NUMBER", "value" => "45.67")
    end

    it "tokenizes strings" do
      tokens = Taurus::XPath.tokenize("'hello' \"world\"")

      expect(tokens.size).to eq(2)
      expect(tokens[0]).to include("type" => "STRING", "value" => "'hello'")
      expect(tokens[1]).to include("type" => "STRING", "value" => "\"world\"")
    end
  end

  describe "names and qnames" do
    it "tokenizes NCNames" do
      tokens = Taurus::XPath.tokenize("root child _private")

      expect(tokens.size).to eq(3)
      expect(tokens[0]).to include("type" => "NCNAME", "value" => "root")
      expect(tokens[1]).to include("type" => "NCNAME", "value" => "child")
      expect(tokens[2]).to include("type" => "NCNAME", "value" => "_private")
    end

    it "tokenizes QNames" do
      tokens = Taurus::XPath.tokenize("ns:root prefix:child")

      expect(tokens.size).to eq(2)
      expect(tokens[0]).to include("type" => "QNAME", "value" => "ns:root")
      expect(tokens[1]).to include("type" => "QNAME", "value" => "prefix:child")
    end
  end

  describe "axes" do
    it "tokenizes axis names" do
      tokens = Taurus::XPath.tokenize("ancestor:: descendant-or-self:: following-sibling::")

      expect(tokens.size).to eq(6)
      expect(tokens[0]).to include("type" => "ANCESTOR", "value" => "ancestor")
      expect(tokens[1]).to include("type" => "DOUBLE_COLON", "value" => "::")
      expect(tokens[2]).to include("type" => "DESCENDANT_OR_SELF", "value" => "descendant-or-self")
      expect(tokens[3]).to include("type" => "DOUBLE_COLON", "value" => "::")
      expect(tokens[4]).to include("type" => "FOLLOWING_SIBLING", "value" => "following-sibling")
      expect(tokens[5]).to include("type" => "DOUBLE_COLON", "value" => "::")
    end

    it "tokenizes all axis types" do
      xpath = "ancestor:: ancestor-or-self:: attribute:: child:: descendant:: descendant-or-self:: following:: following-sibling:: namespace:: parent:: preceding:: preceding-sibling:: self::"
      tokens = Taurus::XPath.tokenize(xpath)

      axis_types = tokens.select { |t| t["type"].end_with?("::") }.map { |t| t["type"] }
      expect(axis_types).to be_empty # Should be DOUBLE_COLON

      axis_names = tokens.select { |t| xpath_token_is_axis_name?(t["type"]) }
      expected_axes = %w[ANCESTOR ANCESTOR_OR_SELF ATTRIBUTE CHILD DESCENDANT DESCENDANT_OR_SELF FOLLOWING FOLLOWING_SIBLING NAMESPACE PARENT PRECEDING PRECEDING_SIBLING SELF]
      expect(axis_names.map { |t| t["type"] }).to eq(expected_axes)
    end
  end

  describe "node types" do
    it "tokenizes node type tests" do
      tokens = Taurus::XPath.tokenize("comment() text() processing-instruction() node()")

      expect(tokens.size).to eq(12)
      expect(tokens[0]).to include("type" => "COMMENT", "value" => "comment")
      expect(tokens[1]).to include("type" => "LPAREN", "value" => "(")
      expect(tokens[2]).to include("type" => "RPAREN", "value" => ")")
      expect(tokens[3]).to include("type" => "TEXT", "value" => "text")
      expect(tokens[4]).to include("type" => "LPAREN", "value" => "(")
      expect(tokens[5]).to include("type" => "RPAREN", "value" => ")")
      expect(tokens[6]).to include("type" => "PROCESSING_INSTRUCTION", "value" => "processing-instruction")
      expect(tokens[7]).to include("type" => "LPAREN", "value" => "(")
      expect(tokens[8]).to include("type" => "RPAREN", "value" => ")")
      expect(tokens[9]).to include("type" => "NODE", "value" => "node")
      expect(tokens[10]).to include("type" => "LPAREN", "value" => "(")
      expect(tokens[11]).to include("type" => "RPAREN", "value" => ")")
    end
  end

  describe "complex expressions" do
    it "tokenizes function calls" do
      tokens = Taurus::XPath.tokenize("count(/root/child)")

      expect(tokens.size).to eq(7)
      expect(tokens[0]).to include("type" => "NCNAME", "value" => "count")
      expect(tokens[1]).to include("type" => "LPAREN", "value" => "(")
      expect(tokens[2]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[3]).to include("type" => "NCNAME", "value" => "root")
      expect(tokens[4]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[5]).to include("type" => "NCNAME", "value" => "child")
      expect(tokens[6]).to include("type" => "RPAREN", "value" => ")")
    end

    it "tokenizes predicates" do
      tokens = Taurus::XPath.tokenize("/root/child[1]/@attr")

      expect(tokens.size).to eq(10)
      expect(tokens[0]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[1]).to include("type" => "NCNAME", "value" => "root")
      expect(tokens[2]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[3]).to include("type" => "NCNAME", "value" => "child")
      expect(tokens[4]).to include("type" => "LBRACKET", "value" => "[")
      expect(tokens[5]).to include("type" => "NUMBER", "value" => "1")
      expect(tokens[6]).to include("type" => "RBRACKET", "value" => "]")
      expect(tokens[7]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[8]).to include("type" => "AT", "value" => "@")
      expect(tokens[9]).to include("type" => "NCNAME", "value" => "attr")
    end

    it "tokenizes complex XPath expressions" do
      xpath = "/library/book[@price < 20 and contains(title, 'Programming')]/author"
      tokens = Taurus::XPath.tokenize(xpath)

      # Should have reasonable number of tokens
      expect(tokens.size).to be > 10

      # Should include various token types
      token_types = tokens.map { |t| t["type"] }
      expect(token_types).to include("SLASH")
      expect(token_types).to include("NCNAME")
      expect(token_types).to include("AT")
      expect(token_types).to include("LT")
      expect(token_types).to include("AND")
      expect(token_types).to include("LBRACKET")
      expect(token_types).to include("RBRACKET")
    end
  end

  describe "error handling" do
    it "handles invalid characters" do
      expect { Taurus::XPath.tokenize("invalid$char") }.to raise_error(RuntimeError)
    end

    it "handles unterminated strings" do
      expect { Taurus::XPath.tokenize("'unterminated") }.to raise_error(RuntimeError)
    end
  end

  describe "whitespace handling" do
    it "ignores whitespace between tokens" do
      tokens = Taurus::XPath.tokenize("  /  root  /  child  ")

      expect(tokens.size).to eq(4)
      expect(tokens[0]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[1]).to include("type" => "NCNAME", "value" => "root")
      expect(tokens[2]).to include("type" => "SLASH", "value" => "/")
      expect(tokens[3]).to include("type" => "NCNAME", "value" => "child")
    end
  end

  describe "position information" do
    it "provides line and column information" do
      tokens = Taurus::XPath.tokenize("/root\n/child")

      expect(tokens.size).to eq(4)
      expect(tokens[0]).to include("line" => 1, "column" => 1)
      expect(tokens[1]).to include("line" => 1, "column" => 2)
      expect(tokens[2]).to include("line" => 2, "column" => 1)
      expect(tokens[3]).to include("line" => 2, "column" => 2)
    end
  end
end

# Helper method for testing axis names
def xpath_token_is_axis_name?(type)
  %w[ANCESTOR ANCESTOR_OR_SELF ATTRIBUTE CHILD DESCENDANT DESCENDANT_OR_SELF FOLLOWING FOLLOWING_SIBLING NAMESPACE PARENT PRECEDING PRECEDING_SIBLING SELF].include?(type)
end