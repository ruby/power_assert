require 'test/unit'
require 'power_assert'
require 'ripper'
require 'set'

class TestPowerAssert < Test::Unit::TestCase
  EXTRACT_METHODS_TEST = [
    [[[:method, "c", 4], [:method, "b", 2], [:method, "d", 8], [:method, "a", 0]],
      'a(b(c), d))'],

    [[[:method, "a", 0], [:method, "b", 2], [:method, "d", 6], [:method, "c", 4]],
      'a.b.c(d)'],

    [[[:method, "b", 2], [:method, "a", 0], [:method, "c", 5], [:method, "e", 9], [:method, "d", 7]],
      'a(b).c.d(e)'],

    [[[:method, "b", 4], [:method, "a", 2], [:method, "c", 7], [:method, "e", 13], [:method, "g", 11], [:method, "d", 9], [:method, "f", 0]],
      'f(a(b).c.d(g(e)))'],

    [[[:method, "c", 5], [:method, "e", 11], [:method, "a", 0]],
      'a(b: c, d: e)'],

    [[[:method, "b", 2], [:method, "c", 7], [:method, "d", 10], [:method, "e", 15], [:method, "a", 0]],
      'a(b => c, d => e)'],

    [[[:method, "b", 4], [:method, "d", 10]],
      '{a: b, c: d}'],

    [[[:method, "a", 1], [:method, "b", 6], [:method, "c", 9], [:method, "d", 14]],
      '{a => b, c => d}'],

    [[[:method, "a", 2], [:method, "b", 5], [:method, "c", 10], [:method, "d", 13]],
      '[[a, b], [c, d]]'],

    [[[:method, "a", 0], [:method, "b", 2], [:method, "c", 5]],
      'a b, c { d }'],

    [[[:method, "a", 20]],
      'assertion_message { a }'],

    [[[:method, "a", 0]],
      'a { b }'],

    [[[:method, "c", 4], [:method, "B", 2], [:method, "d", 8], [:method, "A", 0]],
      'A(B(c), d)'],

    [[[:method, "c", 6], [:method, "f", 17], [:method, "h", 25], [:method, "a", 0]],
      'a(b = c, (d, e = f), G = h)'],

    [[[:method, "b", 2], [:method, "c", 6], [:method, "d", 9], [:method, "e", 12], [:method, "g", 18], [:method, "i", 24], [:method, "j", 29], [:method, "a", 0]],
      'a(b, *c, d, e, f: g, h: i, **j)'],

    [[[:method, "a", 0], [:method, "b", 5], [:method, "c", 9], [:method, "+", 7], [:method, "==", 2]],
      'a == b + c'],

    [[[:ref, "var", 0], [:ref, "var", 8], [:method, "var", 4]],
      'var.var(var)'],

    [[[:ref, "B", 2], [:ref, "@c", 5], [:ref, "@@d", 9], [:ref, "$e", 14], [:method, "f", 18], [:method, "self", 20], [:ref, "self", 26], [:method, "a", 0]],
      'a(B, @c, @@d, $e, f.self, self)'],

    [[[:method, "a", 0], [:method, "c", 4], [:method, "b", 2]],
      'a.b c'],

    [[[:method, "b", 4]],
      '"a#{b}c"'],

    [[[:method, "b", 4]],
      '/a#{b}c/'],

    [[],
      '[]'],

    [[[:method, "a", 0], [:method, "[]", 1]],
      'a[0]'],

    # not supported
    [[],
      '[][]'],

    # not supported
    [[],
      '{}[]'],

    [[[:method, "a", 1], [:method, "!", 0]],
      '!a'],

    [[[:method, "a", 1], [:method, "+@", 0]],
      '+a'],

    [[[:method, "a", 1], [:method, "-@", 0]],
      '-a'],

    [[[:method, "a", 2], [:method, "!", 0], [:method, "b", 9], [:method, "+@", 8], [:method, "c", 15], [:method, "-@", 14],
        [:method, "==", 11], [:method, "==", 4]],
      '! a == (+b == -c)'],

    [[[:method, "b", 6]],
      '%x{a#{b}c}'],

    [[[:method, "a", 0], [:method, "b", 3]],
      "a..b"],

    [[[:method, "a", 0], [:method, "b", 4]],
      "a...b"],

    [[[:method, "b", 5]],
      ':"a#{b}c"'],
  ]

  EXTRACT_METHODS_TEST.each_with_index do |(expect, source), idx|
    define_method("test_extract_methods_#{'%03d' % idx}") do
      pa = PowerAssert.const_get(:Context).new(-> { var = nil; -> { var } }.(), nil)
      pa.instance_variable_set(:@line, source)
      pa.instance_variable_set(:@assertion_method_name, 'assertion_message')
      assert_equal expect, pa.send(:extract_idents, Ripper.sexp(source)).map(&:to_a), source
    end
  end

  def assertion_message(&blk)
    ::PowerAssert.start(blk, assertion_method: __callee__) do |pa|
      pa.yield
      pa.message_proc.()
    end
  end

  def test_assertion_message
    a = 0
    @b = 1
    @@c = 2
    $d = 3
    assert_equal <<END.chomp, assertion_message {
      String(a) + String(@b) + String(@@c) + String($d)
      |      |  | |      |   | |      |    | |      |
      |      |  | |      |   | |      |    | |      3
      |      |  | |      |   | |      |    | "3"
      |      |  | |      |   | |      |    "0123"
      |      |  | |      |   | |      2
      |      |  | |      |   | "2"
      |      |  | |      |   "012"
      |      |  | |      1
      |      |  | "1"
      |      |  "01"
      |      0
      "0"
END
      String(a) + String(@b) + String(@@c) + String($d)
    }


    assert_equal <<END.chomp, assertion_message {
      "0".class == "3".to_i.times.map {|i| i + 1 }.class
          |     |      |    |     |                |
          |     |      |    |     |                Array
          |     |      |    |     [1, 2, 3]
          |     |      |    #<Enumerator: 3:times>
          |     |      3
          |     false
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


    assert_equal <<END.chomp, assertion_message {
      Set.new == Set.new([0])
      |   |   |  |   |
      |   |   |  |   #<Set: {0}>
      |   |   |  Set
      |   |   false
      |   #<Set: {}>
      Set
END
      Set.new == Set.new([0])
    }


    var = [10,20]
    assert_equal <<END.chomp, assertion_message {
      var[0] == 0
      |  |   |
      |  |   false
      |  10
      [10, 20]
END
      var[0] == 0
    }

    a = 1
    assert_equal <<END.chomp, assertion_message {
      ! a != (+a == -a)
      | | |   || |  ||
      | | |   || |  |1
      | | |   || |  -1
      | | |   || false
      | | |   |1
      | | |   1
      | | false
      | 1
      false
END
      ! a != (+a == -a)
    }
  end
end
