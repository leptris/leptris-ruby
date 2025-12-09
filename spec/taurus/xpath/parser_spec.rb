# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Taurus::XPath.parse" do
  describe "primary expressions" do
    it "parses number literals" do
      ast = Taurus::XPath.parse("42")
      expect(ast["type"]).to eq("NUMBER")
      expect(ast["number_value"]).to eq(42.0)
    end

    it "parses decimal numbers" do
      ast = Taurus::XPath.parse("3.14")
      expect(ast["type"]).to eq("NUMBER")
      expect(ast["number_value"]).to eq(3.14)
    end

    it "parses string literals with single quotes" do
      ast = Taurus::XPath.parse("'hello'")
      expect(ast["type"]).to eq("STRING")
      expect(ast["value"]).to eq("hello")
    end

    it "parses string literals with double quotes" do
      ast = Taurus::XPath.parse('"world"')
      expect(ast["type"]).to eq("STRING")
      expect(ast["value"]).to eq("world")
    end

    it "parses parenthesized expressions" do
      ast = Taurus::XPath.parse("(42)")
      expect(ast["type"]).to eq("NUMBER")
      expect(ast["number_value"]).to eq(42.0)
    end

    it "parses function calls with no arguments" do
      ast = Taurus::XPath.parse("node()")
      expect(ast["type"]).to eq("FUNCTION_CALL")
      expect(ast["value"]).to eq("node")
      expect(ast["children"]).to be_nil.or(be_empty)
    end

    it "parses function calls with one argument" do
      ast = Taurus::XPath.parse("count(//item)")
      expect(ast["type"]).to eq("FUNCTION_CALL")
      expect(ast["value"]).to eq("count")
      expect(ast["children"]).to be_an(Array)
      expect(ast["children"].size).to eq(1)
    end

    it "parses function calls with multiple arguments" do
      ast = Taurus::XPath.parse("substring('hello', 1, 3)")
      expect(ast["type"]).to eq("FUNCTION_CALL")
      expect(ast["value"]).to eq("substring")
      expect(ast["children"].size).to eq(3)
    end
  end

  describe "arithmetic operators" do
    it "parses addition" do
      ast = Taurus::XPath.parse("1 + 2")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("PLUS")
      expect(ast["children"].size).to eq(2)
    end

    it "parses subtraction" do
      ast = Taurus::XPath.parse("5 - 3")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("MINUS")
    end

    it "parses multiplication" do
      ast = Taurus::XPath.parse("2 * 3")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("MULTIPLY")
    end

    it "parses division" do
      ast = Taurus::XPath.parse("10 div 2")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("DIV")
    end

    it "parses modulo" do
      ast = Taurus::XPath.parse("10 mod 3")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("MOD")
    end

    it "parses unary negation" do
      ast = Taurus::XPath.parse("-5")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("NEGATION")
      expect(ast["children"].size).to eq(1)
    end
  end

  describe "comparison operators" do
    it "parses equality" do
      ast = Taurus::XPath.parse("@id = '123'")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("EQUAL")
    end

    it "parses inequality" do
      ast = Taurus::XPath.parse("@type != 'hidden'")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("NOT_EQUAL")
    end

    it "parses less than" do
      ast = Taurus::XPath.parse("price < 20")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("LESS")
    end

    it "parses less than or equal" do
      ast = Taurus::XPath.parse("quantity <= 10")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("LESS_EQUAL")
    end

    it "parses greater than" do
      ast = Taurus::XPath.parse("price > 100")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("GREATER")
    end

    it "parses greater than or equal" do
      ast = Taurus::XPath.parse("age >= 18")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("GREATER_EQUAL")
    end
  end

  describe "logical operators" do
    it "parses and operator" do
      ast = Taurus::XPath.parse("@enabled and @visible")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("AND")
    end

    it "parses or operator" do
      ast = Taurus::XPath.parse("@type = 'admin' or @type = 'moderator'")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("OR")
    end

    it "parses complex boolean expression" do
      ast = Taurus::XPath.parse("(@enabled and @visible) or @forced")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("OR")
    end
  end

  describe "union operator" do
    it "parses simple union" do
      ast = Taurus::XPath.parse("//book | //magazine")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("UNION")
    end

    it "parses multiple unions" do
      ast = Taurus::XPath.parse("//book | //magazine | //newspaper")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("UNION")
      # Should be left-associative: (book | magazine) | newspaper
    end
  end

  describe "operator precedence" do
    it "handles multiplication before addition" do
      ast = Taurus::XPath.parse("1 + 2 * 3")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("PLUS")
      # Right child should be multiplication
      expect(ast["children"][1]["operator"]).to eq("MULTIPLY")
    end

    it "handles comparison before and" do
      ast = Taurus::XPath.parse("@x = 1 and @y = 2")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("AND")
      # Both children should be EQUAL
      expect(ast["children"][0]["operator"]).to eq("EQUAL")
      expect(ast["children"][1]["operator"]).to eq("EQUAL")
    end

    it "handles and before or" do
      ast = Taurus::XPath.parse("@a and @b or @c")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("OR")
      # Left child should be AND
      expect(ast["children"][0]["operator"]).to eq("AND")
    end

    it "respects parentheses" do
      ast = Taurus::XPath.parse("(1 + 2) * 3")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("MULTIPLY")
      # Left child should be addition
      expect(ast["children"][0]["operator"]).to eq("PLUS")
    end
  end

  describe "simple path expressions" do
    it "parses absolute path with single step" do
      ast = Taurus::XPath.parse("/root")
      expect(ast["type"]).to eq("ABSOLUTE_PATH")
      expect(ast["children"]).to be_an(Array)
    end

    it "parses absolute path with multiple steps" do
      ast = Taurus::XPath.parse("/root/child/grandchild")
      expect(ast["type"]).to eq("ABSOLUTE_PATH")
      rel_path = ast["children"][0]
      expect(rel_path["type"]).to eq("RELATIVE_PATH")
      expect(rel_path["children"].size).to eq(3)
    end

    it "parses descendant-or-self shorthand" do
      ast = Taurus::XPath.parse("//book")
      expect(ast["type"]).to eq("ABSOLUTE_PATH")
      # Should have descendant-or-self step
      expect(ast["children"].size).to eq(2)
    end

    it "parses relative path" do
      ast = Taurus::XPath.parse("child/grandchild")
      expect(ast["type"]).to eq("RELATIVE_PATH")
      expect(ast["children"].size).to eq(2)
    end

    it "parses self abbreviation" do
      ast = Taurus::XPath.parse(".")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("self")
    end

    it "parses parent abbreviation" do
      ast = Taurus::XPath.parse("..")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("parent")
    end

    it "parses attribute with @ abbreviation" do
      ast = Taurus::XPath.parse("@id")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("attribute")
    end
  end

  describe "axis specifiers" do
    it "parses child axis" do
      ast = Taurus::XPath.parse("child::book")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("child")
    end

    it "parses descendant axis" do
      ast = Taurus::XPath.parse("descendant::item")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("descendant")
    end

    it "parses parent axis" do
      ast = Taurus::XPath.parse("parent::book")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("parent")
    end

    it "parses ancestor axis" do
      ast = Taurus::XPath.parse("ancestor::section")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("ancestor")
    end

    it "parses following-sibling axis" do
      ast = Taurus::XPath.parse("following-sibling::chapter")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("following-sibling")
    end

    it "parses attribute axis" do
      ast = Taurus::XPath.parse("attribute::id")
      expect(ast["type"]).to eq("STEP")
      expect(ast["value"]).to eq("attribute")
    end
  end

  describe "node tests" do
    it "parses wildcard" do
      ast = Taurus::XPath.parse("//*")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      node_test = step["children"][0]
      expect(node_test["type"]).to eq("NODE_TEST_ALL")
    end

    it "parses name test" do
      ast = Taurus::XPath.parse("//book")
      # Navigate to node test
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      node_test = step["children"][0]
      expect(node_test["type"]).to eq("NODE_TEST_NAME")
      expect(node_test["value"]).to eq("book")
    end

    it "parses text() node test" do
      ast = Taurus::XPath.parse("//text()")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      node_test = step["children"][0]
      expect(node_test["type"]).to eq("NODE_TEST_TYPE")
      expect(node_test["value"]).to eq("text")
    end

    it "parses comment() node test" do
      ast = Taurus::XPath.parse("//comment()")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      node_test = step["children"][0]
      expect(node_test["type"]).to eq("NODE_TEST_TYPE")
      expect(node_test["value"]).to eq("comment")
    end

    it "parses node() node test" do
      ast = Taurus::XPath.parse("//node()")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      node_test = step["children"][0]
      expect(node_test["type"]).to eq("NODE_TEST_TYPE")
      expect(node_test["value"]).to eq("node")
    end
  end

  describe "predicates" do
    it "parses simple predicate with position" do
      ast = Taurus::XPath.parse("//book[1]")
      # Navigate through structure
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      # Step should have node test and predicate as children
      expect(step["children"].size).to eq(2)
      predicate = step["children"][1]
      expect(predicate["type"]).to eq("NUMBER")
    end

    it "parses predicate with attribute test" do
      ast = Taurus::XPath.parse("//book[@id='123']")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      expect(step["children"].size).to eq(2)
      predicate = step["children"][1]
      expect(predicate["type"]).to eq("OPERATOR")
      expect(predicate["operator"]).to eq("EQUAL")
    end

    it "parses multiple predicates" do
      ast = Taurus::XPath.parse("//book[@lang='en'][1]")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      # Should have node test + 2 predicates
      expect(step["children"].size).to eq(3)
    end

    it "parses nested predicates" do
      ast = Taurus::XPath.parse("//section[chapter[@published='true']]")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      expect(step["children"].size).to eq(2)
    end
  end

  describe "complex expressions" do
    it "parses path with multiple steps and predicates" do
      ast = Taurus::XPath.parse("/library/books/book[@category='fiction'][1]/title")
      expect(ast["type"]).to eq("ABSOLUTE_PATH")
    end

    it "parses expression with function calls" do
      ast = Taurus::XPath.parse("count(//book[price > 20])")
      expect(ast["type"]).to eq("FUNCTION_CALL")
      expect(ast["value"]).to eq("count")
    end

    it "parses complex predicate with operators" do
      ast = Taurus::XPath.parse("//book[price > 10 and price < 50]")
      rel_path = ast["children"][1]
      step = rel_path["children"][0]
      predicate = step["children"][1]
      expect(predicate["operator"]).to eq("AND")
    end

    it "parses union with predicates" do
      ast = Taurus::XPath.parse("//book[@type='new'] | //magazine[@type='new']")
      expect(ast["type"]).to eq("OPERATOR")
      expect(ast["operator"]).to eq("UNION")
    end

    it "parses path continuing after filter expression" do
      ast = Taurus::XPath.parse("(//book)[1]/title")
      expect(ast["type"]).to eq("PATH_EXPR")
    end
  end

  describe "error handling" do
    it "raises error for unterminated string" do
      expect { Taurus::XPath.parse("'unterminated") }.to raise_error(RuntimeError, /Unterminated string/)
    end

    it "raises error for unexpected token" do
      expect { Taurus::XPath.parse("@") }.to raise_error(RuntimeError, /parsing error/)
    end

    it "raises error for unmatched parenthesis" do
      expect { Taurus::XPath.parse("(1 + 2") }.to raise_error(RuntimeError, /Expected '\)'/)
    end

    it "raises error for unmatched bracket" do
      expect { Taurus::XPath.parse("//book[1") }.to raise_error(RuntimeError, /Expected '\]'/)
    end
  end
end