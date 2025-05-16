if ! RubyVM::InstructionSequence.compile_option[:specialized_instruction]
  warn "#{__FILE__}: specialized_instruction is set to false"
end

require_relative 'test_helper'

class TestDynaSymbolKey < Test::Unit::TestCase
  include PowerAssertTestHelper

  data do
    [
      ['{"a": b}',
        [[:method, "b", 6]]],
    ].each_with_object({}) {|(source, expected_idents, expected_paths), h| h[source] = [expected_idents, expected_paths, source] }
  end
  def test_parser(*args)
    _test_parser(*args)
  end

  t do
    assert_equal <<END.chomp, assertion_message {
      {"a": 1.to_s}.nil?
              |     |
              |     false
              "1"
END
      {"a": 1.to_s}.nil?
    }
  end
end
