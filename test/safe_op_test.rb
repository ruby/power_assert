require_relative 'test_helper'

class TestSafeOp < Test::Unit::TestCase
  include PowerAssertTestHelper

  data do
    [
      ['a&.b(c) + d',
        [[:method, "a", 0],
          [[[:method, "c", 5], [:method, "b", 3]], []],
          [:method, "d", 10], [:method, "+", 8]],
        [["a", "c", "b", "d", "+"], ["a", "d", "+"]]],

      ['a&.b.c',
        [[:method, "a", 0], [[[:method, "b", 3]], []], [:method, "c", 5]],
        [["a", "b", "c"], ["a", "c"]]],

      ['a&.(b)',
        [[:method, "a", 0], [[[:method, "b", 4], [:method, "call", 3]], []]],
        [["a", "b", "call"], ["a"]]],
    ].each_with_object({}) {|(source, expected_idents, expected_paths), h| h[source] = [expected_idents, expected_paths, source] }
  end
  def test_extract_methods(*args)
    _test_extract_methods(*args)
  end

  sub_test_case 'branch' do
    t do
      assert_equal <<END.chomp, assertion_message {
        nil&.to_i&.to_s("10".to_i).to_i
                                   |
                                   0
END
        nil&.to_i&.to_s("10".to_i).to_i
      }
    end

    t do
      assert_equal <<END.chomp, assertion_message {
        1&.to_i&.to_s("10".to_i).to_i
           |     |         |     |
           |     |         |     1
           |     |         10
           |     "1"
           1
END
        1&.to_i&.to_s("10".to_i).to_i
      }
    end
  end
end
