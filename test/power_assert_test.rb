require 'test/unit'
require 'power_assert'
require 'ripper'
require 'set'

class TestPowerAssert < Test::Unit::TestCase
  class << self
    def t(msg='', &blk)
      loc = caller_locations(1, 1)[0]
      test("#{loc.path} --location #{loc.lineno} #{msg}", &blk)
    end
  end

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
        [[:method, "a", 0], [:method, "b", 2], [:method, "c", 5]]],

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

      ['->{}.()',
        [[:method, "call", 5]]],

      # not supported
      ['->{}.().()',
        []],

      ['a.(b)',
        [[:method, "a", 0], [:method, "b", 3], [:method, "call", 2]]],

      ['a.[](b)',
        [[:method, "a", 0], [:method, "b", 5], [:method, "[]", 2]]],

      ['a.b ? c.d : e.f',
        [[:method, "a", 0], [:method, "b", 2],
          [[[:method, "c", 6], [:method, "d", 8]],
            [[:method, "e", 12], [:method, "f", 14]]]],
        [["a", "b", "c", "d"], ["a", "b", "e", "f"]]],

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
  def test_extract_methods((expected_idents, expected_paths, source))
    pa = PowerAssert.const_get(:Context).new(-> { var = nil; -> { var } }.(), nil, TOPLEVEL_BINDING)
    pa.instance_variable_set(:@line, source)
    pa.instance_variable_set(:@assertion_method_name, 'assertion_message')
    idents = pa.send(:extract_idents, Ripper.sexp(source))
    assert_equal expected_idents, map_recursive(idents, &:to_a), source
    if expected_paths
      assert_equal expected_paths, map_recursive(pa.send(:collect_paths, idents), &:name), source
    end
  end

  def map_recursive(ary, &blk)
    ary.map {|i| Array === i ? map_recursive(i, &blk) : yield(i) }
  end

  class BasicObjectSubclass < BasicObject
    def foo
      "foo"
    end
  end

  def assertion_message(source = nil, source_binding = TOPLEVEL_BINDING, &blk)
    ::PowerAssert.start(source || blk, assertion_method: __callee__, source_binding: source_binding) do |pa|
      pa.yield
      pa.message
    end
  end

  def Assertion(&blk)
    ::PowerAssert.start(blk, assertion_method: __callee__) do |pa|
      pa.yield
      pa.message
    end
  end

  define_method(:bmethod) do
    false
  end

  sub_test_case 'lazy_inspection' do
    t do
      PowerAssert.configure do |c|
        assert !c.lazy_inspection
      end
      assert_equal <<END.chomp, assertion_message {
        'a'.sub(/./, 'b').sub!(/./, 'c')
            |             |
            |             "c"
            "b"
END
        'a'.sub(/./, 'b').sub!(/./, 'c')
      }
    end

    t do
      PowerAssert.configure do |c|
        c.lazy_inspection = true
      end
      begin
        assert_equal <<END.chomp, assertion_message {
          'a'.sub(/./, 'b').sub!(/./, 'c')
              |             |
              |             "c"
              "c"
END
          'a'.sub(/./, 'b').sub!(/./, 'c')
        }
      ensure
        PowerAssert.configure do |c|
          c.lazy_inspection = false
        end
      end
    end
  end

  sub_test_case 'assertion_message' do
    t do
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
    end

    t do
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
    end

    t do
      assert_equal '', assertion_message {
        false
      }
    end

    t do
      assert_equal <<END.chomp,
      assertion_message { "0".class }
                              |
                              String
END
      assertion_message { "0".class }
    end

    t do
      assert_equal <<END.chomp,
        "0".class
            |
            String
END
      Assertion {
        "0".class
      }
    end

    t do
      assert_equal <<END.chomp,
      Assertion { "0".class }
                      |
                      String
END
      Assertion { "0".class }
    end

    t do
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
    end

    t do
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
    end

    t do
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

    t do
      assert_equal <<END.chomp, assertion_message {
        bmethod
        |
        false
END
        bmethod
      }
    end

    t do
      a = :a
      assert_equal <<END.chomp, assertion_message {
        a == :b
        | |
        | false
        :a
END
        a == :b
      }
    end

    t do
      assert_equal <<END.chomp, assertion_message {
        ! Object
        | |
        | Object
        false
END
        ! Object
      }
    end

    t do
      # TracePoint cannot trace attributes
      # https://bugs.ruby-lang.org/issues/10470
      o = Class.new do
        attr_accessor :to_i
        def inspect; '#<Class>'; end
      end.new
      o.to_i = 0
      assert_equal <<END.chomp, assertion_message {
        o.to_i.to_i.to_s
        |           |
        |           "0"
        #<Class>
END
        o.to_i.to_i.to_s
      }
    end

    if PowerAssert.respond_to?(:clear_global_method_cache, true)
      t do
        3.times do
          assert_equal <<END.chomp, assertion_message {
            String == Array
            |      |  |
            |      |  Array
            |      false
            String
END
            String == Array
          }
        end
      end
    end
  end

  sub_test_case 'inspection_failure' do
    t do
      assert_match Regexp.new(<<END.chomp.gsub('|', "\\|")),
      assertion_message { BasicObjectSubclass.new.foo }
                          |                   |   |
                          |                   |   "foo"
                          |                   InspectionFailure: NoMethodError: .*
                          TestPowerAssert::BasicObjectSubclass
END
      assertion_message { BasicObjectSubclass.new.foo }
    end

    t do
      o = Object.new
      def o.inspect
        raise
      end
      assert_equal <<END.chomp.b, assertion_message {
        o.class
        | |
        | Object
        InspectionFailure: RuntimeError:
END
        o.class
      }
    end
  end

  sub_test_case 'alias_method' do
    def setup
      begin
        PowerAssert.configure do |c|
          c._trace_alias_method = true
        end unless PowerAssert.const_get(:SUPPORT_ALIAS_METHOD)
        @o = Class.new do
          def foo
            :foo
          end
          alias alias_of_iseq foo
          alias alias_of_cfunc to_s
        end
        yield
      ensure
        PowerAssert.configure do |c|
          c._trace_alias_method = false
        end unless PowerAssert.const_get(:SUPPORT_ALIAS_METHOD)
      end
    end

    t do
      assert_match Regexp.new(<<END.chomp.gsub('|', "\\|")),
        assertion_message { @o.new.alias_of_iseq }
                            |  |   |
                            |  |   :foo
                            |  #<#<Class:.*>:.*>
                            #<Class:.*>
END
        assertion_message { @o.new.alias_of_iseq }
    end

    t do
      unless PowerAssert.const_get(:SUPPORT_ALIAS_METHOD)
        omit 'alias of cfunc is not supported yet'
      end
      assert_match Regexp.new(<<END.chomp.gsub('|', "\\|")),
        assertion_message { @o.new.alias_of_cfunc }
                            |  |   |
                            |  |   "#<#<Class:.*>:.*>"
                            |  #<#<Class:.*>:.*>
                            #<Class:.*>
END
        assertion_message { @o.new.alias_of_cfunc }
    end
  end

  sub_test_case 'assertion_message_with_incompatible_encodings' do
    if Encoding.default_external == Encoding::UTF_8
      t do
        a = "\u3042"
        def a.inspect
          super.encode('utf-16le')
        end
        assert_equal <<END.chomp, assertion_message {
          a + a
          | | |
          | | "\u3042"(UTF-16LE)
          | "\u3042\u3042"
          "\u3042"(UTF-16LE)
END
          a + a
        }
      end
    end

    t do
      a = "\xFF"
      def a.inspect
        "\xFF".force_encoding('ascii-8bit')
      end
      assert_equal <<END.chomp.b, assertion_message {
        a.length
        | |
        | 1
        \xFF
END
        a.length
      }.b
    end
  end

  sub_test_case 'branch' do
    t do
      a, b, = 0, 1
      assert_equal <<END.chomp, assertion_message {
        a == 0 ? b.to_s : b.to_i
        | |      | |
        | |      | "1"
        | |      1
        | true
        0
END
        a == 0 ? b.to_s : b.to_i
      }
    end

    t do
      a, b, = 0, 1
      assert_equal <<END.chomp, assertion_message {
        a == 1 ? b.to_s : b.to_i
        | |               | |
        | |               | 1
        | |               1
        | false
        0
END
        a == 1 ? b.to_s : b.to_i
      }
    end

    t do
      assert_equal <<END, assertion_message {
        false ? 0.to_s : 0.to_s
END
        false ? 0.to_s : 0.to_s
      }
    end

    t do
      assert_equal <<END.chomp, assertion_message {
        false ? 0.to_s.to_i : 0.to_s
                                |
                                "0"
END
        false ? 0.to_s.to_i : 0.to_s
      }
    end

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

  def test_assertion_message_with_string
    a, = 0, a # suppress "assigned but unused variable" warning
    @b = 1
    @@c = 2
    $d = 3
    assert_equal <<ENDA.chomp, assertion_message(<<ENDB, binding)
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
ENDA
      String(a) + String(@b) + String(@@c) + String($d)
ENDB
  end

  def test_workaround_for_ruby_2_2
    assert_nothing_raised do
      assertion_message { Thread.new {}.join }
    end
  end

  class H < Hash
    alias aref []
    protected :aref
  end

  def test_workaround_for_bug11182
    assert_nothing_raised do
      {}[:a]
    end
  end
end
