class TestParserMultiline < Test::Unit::TestCase
  def setup
    ::PowerAssert.public_constant :Parser
  end

  def teardown
    ::PowerAssert.private_constant :Parser
  end

  def test_valid
    path   = "#{File.dirname(__FILE__)}/fixtures/valid_multiline_assertion.rb"
    lineno = 0
    line   = open(path).each_line.first
    assert parsed_as_valid_syntax?(line, path, lineno)
  end

  def test_invalid
    path   = "#{File.dirname(__FILE__)}/fixtures/invalid_multiline_assertion.rb"
    lineno = 0
    line   = open(path).each_line.first
    assert_false parsed_as_valid_syntax?(line, path, lineno)
  end

  private

  def parsed_as_valid_syntax?(line, path, lineno)
    parser = ::PowerAssert::Parser.new(line, path, lineno, TOPLEVEL_BINDING, nil, nil)
    parser.send(:valid_syntax?)
  end
end
