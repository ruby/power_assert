require 'test/unit'
require 'power_assert'
require 'ripper'

class TestPowerAssert < Test::Unit::TestCase
  EXTRACT_METHODS_TEST = [
    [[["c", [1, 4]], ["b", [1, 2]], ["d", [1, 8]], ["a", [1, 0]]],
      'a(b(c), d))'],

    [[["a", [1, 0]], ["b", [1, 2]], ["d", [1, 6]], ["c", [1, 4]]],
      'a.b.c(d)'],

    [[["b", [1, 2]], ["a", [1, 0]], ["c", [1, 5]], ["e", [1, 9]], ["d", [1, 7]]],
      'a(b).c.d(e)'],

    [[["b", [1, 4]], ["a", [1, 2]], ["c", [1, 7]], ["e", [1, 13]], ["g", [1, 11]], ["d", [1, 9]], ["f", [1, 0]]],
      'f(a(b).c.d(g(e)))'],

    [[["c", [1, 5]], ["e", [1, 11]], ["a", [1, 0]]],
      'a(b: c, d: e)'],

    [[["b", [1, 2]], ["c", [1, 7]], ["d", [1, 10]], ["e", [1, 15]], ["a", [1, 0]]],
      'a(b => c, d => e)'],

    [[["b", [1, 4]], ["d", [1, 10]]],
      '{a: b, c: d}'],

    [[["a", [1, 1]], ["b", [1, 6]], ["c", [1, 9]], ["d", [1, 14]]],
      '{a => b, c => d}'],

    [[["a", [1, 2]], ["b", [1, 5]], ["c", [1, 10]], ["d", [1, 13]]],
      '[[a, b], [c, d]]'],

    [[["a", [1, 0]], ["b", [1, 2]], ["c", [1, 5]]],
      'a b, c { d }'],

    [[["a", [1, 20]]],
      'assertion_message { a }'],

    [[["a", [1, 0]]],
      'a { b }'],

    [[["c", [1, 4]], ["B", [1, 2]], ["d", [1, 8]], ["A", [1, 0]]],
      'A(B(c), d)'],

    [[["c", [1, 6]], ["f", [1, 17]], ["h", [1, 25]], ["a", [1, 0]]],
      'a(b = c, (d, e = f), G = h)']
  ]

  EXTRACT_METHODS_TEST.each_with_index do |(expect, actual), idx|
    define_method("test_extract_methods_#{idx}") do
      assert_equal expect, PowerAssert::Context.new(nil).send(:extract_methods, Ripper.sexp(actual), :assertion_message)
    end
  end

  def assertion_message(&blk)
    ::PowerAssert.start(assertion_method: __method__) do |pa|
      pa.yield(&blk)
      pa.message_proc.()
    end
  end

  def test_assertion_message
    assert_equal <<END.chomp, assertion_message {
      "0".class == "3".to_i.times.map {|i| i + 1 }.class
          |            |    |     |                |
          |            |    |     |                Array
          |            |    |     [1, 2, 3]
          |            |    #<Enumerator: 3:times>
          |            3
          String
END
      "0".class == "3".to_i.times.map {|i| i + 1 }.class
    }
    assert_equal '', assertion_message {
      false
    }
    assert_equal <<END.chomp,
    assertion_message { "0".class }
                            |
                            String
END
    assertion_message { "0".class }
  end
end
