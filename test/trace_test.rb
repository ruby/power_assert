if defined?(RubyVM) and ! RubyVM::InstructionSequence.compile_option[:specialized_instruction]
  warn "#{__FILE__}: specialized_instruction is set to false"
end

require_relative 'test_helper'
require 'byebug'

class TestTraceContext < Test::Unit::TestCase
  include PowerAssertTestHelper

  class TestInterface < Byebug::Interface
    def readline(prompt)
      'next'
    end

    def do_nothing(*)
    end

    alias puts do_nothing
    alias print do_nothing
    alias errmsg do_nothing
  end

  class << self
    def startup
      Byebug::Context.interface = TestInterface.new
      Byebug::Context.processor = PowerAssertTestHelper::TestProcessor
      Byebug::Setting[:autosave] = false
    end

    def iseq
      :iseq
    end

    define_method(:bmethod) do
      :bmethod
    end
  end

  setup do
    Byebug.start
  end

  teardown do
    Byebug.stop
  end

  def trace_test(expected_message, file, lineno, binding = TOPLEVEL_BINDING)
    code = "byebug\n#{expected_message.each_line.first}\n"
    lineno -= 1 # For 'byebug' at the first line
    eval(code, binding, file, lineno)
    pa = Byebug.current_context.__send__(:processor).pa_context
    assert_equal(expected_message, pa.message)
    assert_true(pa.enabled?)
    pa.disable
    assert_false(pa.enabled?)
  end

  def test_iseq
    trace_test(<<END.chomp, __FILE__, __LINE__ + 1)
      TestTraceContext.iseq
      |                |
      |                :iseq
      TestTraceContext
END
  end

  def test_bmethod
    trace_test(<<END.chomp, __FILE__, __LINE__ + 1)
      TestTraceContext.bmethod
      |                |
      |                :bmethod
      TestTraceContext
END
  end

  def test_cfunc
    trace_test(<<END.chomp, __FILE__, __LINE__ + 1)
      0 == 0
        |
        true
END
  end

  def test_all_refs
    a, b, c, = 0, 1, 2, a, b, c # suppress "assigned but unused variable" warning
    trace_test(<<END.chomp, __FILE__, __LINE__ + 1, binding)
      a ? b : c
      |   |   |
      |   |   2
      |   1
      0
END
  end
end
