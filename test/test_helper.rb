begin
  if ENV['COVERAGE']
    require 'simplecov'
    SimpleCov.start do
      add_filter '/test/'
      add_filter '/vendor/'
    end
  end

  require 'bundler'
  Bundler.require
rescue LoadError, Bundler::GemNotFound
end

require 'test/unit'
require 'power_assert'
require 'ripper'

module PowerAssertTestHelper
  class << self
    def included(base)
      base.extend(ClassMethods)
    end
  end

  module ClassMethods
    def t(msg='', &blk)
      loc = caller_locations(1, 1)[0]
      test("#{loc.path} --location #{loc.lineno} #{msg}", &blk)
    end
  end

  private

  def _test_parser((expected_idents, expected_paths, source))
    parser = ::PowerAssert.const_get(:Parser).new(source, '', 1, -> { var = nil; -> { var } }.().binding, 'assertion_message')
    idents = parser.idents
    assert_equal expected_idents, map_recursive(idents, &:to_a), source
    if expected_paths
      assert_equal expected_paths, map_recursive(parser.call_paths, &:name), source
    end
  end

  def map_recursive(ary, &blk)
    ary.map {|i| Array === i ? map_recursive(i, &blk) : yield(i) }
  end

  def assertion_message(source = nil, source_binding = TOPLEVEL_BINDING, &blk)
    ::PowerAssert.start(source || blk, assertion_method: __callee__, source_binding: source_binding) do |pa|
      pa.yield
      pa.message
    end
  end

  def strip_color(str)
    str.gsub(/(\001)?\e\[.*?(\d)+m(\002)?/, '')
  end
end

RubyVM::InstructionSequence.compile_option = {
  specialized_instruction: true
}
