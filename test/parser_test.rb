require_relative 'test_helper'

class TestParser < Test::Unit::TestCase
  include PowerAssertTestHelper

  data do
    [
      ['a(b(c), d)',
        [[:method, "c", 4], [:method, "b", 2], [:method, "d", 8], [:method, "a", 0]]],

      ['a.b.c(d)',
        [[:method, "a", 0], [:method, "b", 2], [:method, "d", 6], [:method, "c", 4]]],

      ['a(b).c.d(e)',
        [[:method, "b", 2], [:method, "a", 0], [:method, "c", 5], [:method, "e", 9], [:method, "d", 7]]],

      ['f(a(b).c.d(g(e)))',
        [[:method, "b", 4], [:method, "a", 2], [:method, "c", 7], [:method, "e", 13], [:method, "g", 11], [:method, "d", 9], [:method, "f", 0]]],

      ['a(b: c, d: e)',
        [[:method, "c", 5], [:method, "e", 11], [:method, "a", 0]]],

      ['a(b => c, d => e)',
        [[:method, "b", 2], [:method, "c", 7], [:method, "d", 10], [:method, "e", 15], [:method, "a", 0]]],

      ['{a: b, c: d}',
        [[:method, "b", 4], [:method, "d", 10]]],

      ['{a => b, c => d}',
        [[:method, "a", 1], [:method, "b", 6], [:method, "c", 9], [:method, "d", 14]]],

      ['[[a, b], [c, d]]',
        [[:method, "a", 2], [:method, "b", 5], [:method, "c", 10], [:method, "d", 13]]],

      ['a b, c { d }',
        [[:method, "b", 2], [:method, "c", 5], [:method, "a", 0]]],

      ['assertion_message { a }',
        [[:method, "a", 20]]],

      ['a { b }',
        [[:method, "a", 0]]],

      ['A(B(c), d)',
        [[:method, "c", 4], [:method, "B", 2], [:method, "d", 8], [:method, "A", 0]]],

      ['a(b = c, (d, e = f), G = h)',
        [[:method, "c", 6], [:method, "f", 17], [:method, "h", 25], [:method, "a", 0]]],

      ['a(b, *c, d, e, f: g, h: i, **j)',
        [[:method, "b", 2], [:method, "c", 6], [:method, "d", 9], [:method, "e", 12], [:method, "g", 18], [:method, "i", 24], [:method, "j", 29], [:method, "a", 0]]],

      ['a == b + c',
        [[:method, "a", 0], [:method, "b", 5], [:method, "c", 9], [:method, "+", 7], [:method, "==", 2]]],

      ['var.var(var)',
        [[:ref, "var", 0], [:ref, "var", 8], [:method, "var", 4]]],

      ['a(B, @c, @@d, $e, f.self, self)',
        [[:ref, "B", 2], [:ref, "@c", 5], [:ref, "@@d", 9], [:ref, "$e", 14], [:method, "f", 18], [:method, "self", 20], [:ref, "self", 26], [:method, "a", 0]]],

      ['a.b c',
        [[:method, "a", 0], [:method, "c", 4], [:method, "b", 2]]],

      ['"a#{b}c"',
        [[:method, "b", 4]]],

      ['/a#{b}c/',
        [[:method, "b", 4]]],

      ['[]',
        []],

      ['a[0]',
        [[:method, "a", 0], [:method, "[]", 1]]],

      # not supported
      ['[][]',
        []],

      ['{}[]',
        [[:method, "[]", 2]]],

      ['!a',
        [[:method, "a", 1], [:method, "!", 0]]],

      ['+a',
        [[:method, "a", 1], [:method, "+@", 0]]],

      ['-a',
        [[:method, "a", 1], [:method, "-@", 0]]],

      ['! a == (+b == -c)',
        [[:method, "a", 2], [:method, "!", 0], [:method, "b", 9], [:method, "+@", 8], [:method, "c", 15], [:method, "-@", 14],
          [:method, "==", 11], [:method, "==", 4]]],

      ['%x{a#{b}c}',
        [[:method, "b", 6]]],

      ["a..b",
        [[:method, "a", 0], [:method, "b", 3]]],

      ["a...b",
        [[:method, "a", 0], [:method, "b", 4]]],

      [':"a#{b}c"',
        [[:method, "b", 5]]],

      ['return a, b',
        [[:method, "a", 7], [:method, "b", 10]]],

      ['->{}.()',
        [[:method, "call", 5]]],

      # not supported
      ['->{}.().()',
        []],

      ['a.(b)',
        [[:method, "a", 0], [:method, "b", 3], [:method, "call", 2]]],

      ['a.[](b)',
        [[:method, "a", 0], [:method, "b", 5], [:method, "[]", 2]]],

      ['a += b',
        [[:method, "b", 5], [:method, "+", 2]]],

      ['a if b',
        [[:method, "b", 5], [[[:method, "a", 0]], []]],
        [["b", "a"], ["b"]]],

      ['a unless b',
        [[:method, "b", 9], [[[:method, "a", 0]], []]],
        [["b", "a"], ["b"]]],

      ['a.b ? c.d : e.f',
        [[:method, "a", 0], [:method, "b", 2],
          [[[:method, "c", 6], [:method, "d", 8]],
            [[:method, "e", 12], [:method, "f", 14]]]],
        [["a", "b", "c", "d"], ["a", "b", "e", "f"]]],

      ['a.b ? (c ? d : e) : f.g',
        [[:method, "a", 0], [:method, "b", 2],
          [[[:method, "c", 7],
              [[[:method, "d", 11]], [[:method, "e", 15]]]],
            [[:method, "f", 20], [:method, "g", 22]]]],
        [["a", "b", "c", "d"], ["a", "b", "c", "e"], ["a", "b", "f", "g"]]],

      ['a ? 0 : 0',
        [[:method, "a", 0], [[], []]],
        [["a"]]],

      ['a && b || c',
        [[:method, "a", 0], [[[:method, "b", 5]], []], [[[:method, "c", 10]], []]],
        [["a", "b", "c"], ["a", "c"], ["a", "b"], ["a"]]],

      ['a and b or c',
        [[:method, "a", 0], [[[:method, "b", 6]], []], [[[:method, "c", 11]], []]],
        [["a", "b", "c"], ["a", "c"], ["a", "b"], ["a"]]],
    ].each_with_object({}) {|(source, expected_idents, expected_paths), h| h[source] = [expected_idents, expected_paths, source] }
  end
  def test_valid_syntax(*args)
    _test_parser(*args)
  end

  data do
    [
      ['if a',
        [[:method, "a", 3]]],

      ['end.a',
        [[:method, "a", 4]]],

      ['a.',
        [[:method, "a", 0]]],

      ['a&&',
        [[:method, "a", 0]]],

      ['a||',
        [[:method, "a", 0]]],

      ['a do',
        [[:method, "a", 0]]],
    ].each_with_object({}) {|(source, expected_idents, expected_paths), h| h[source] = [expected_idents, expected_paths, source] }
  end
  def test_recoverable_invalid_syntax(*args)
    _test_parser(*args)
  end
end
