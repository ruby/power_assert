require 'byebug'
require 'byebug/core'

class << PowerAssert
  prepend Module.new {
    def internal_file?(file)
      super or file == __FILE__
    end
  }
end

module PowerAssertTestHelper
  class TestProcessor < Byebug::CommandProcessor
    attr_reader :pa_context

    def at_line
      super
      @pa_context ||= PowerAssert.trace(frame)
    end
  end
end
