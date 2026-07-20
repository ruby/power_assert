require 'diff/lcs'

module PowerAssert
  module Diagnostics
    CAPTURE_KEY = :__power_assert_diagnostics__
    private_constant :CAPTURE_KEY

    class << self
      def capture
        Thread.current[CAPTURE_KEY]
      end

      def capture=(value)
        Thread.current[CAPTURE_KEY] = value
      end
    end

    refine String do
      def ==(other)
        Diagnostics.capture = [self, other]
        super
      end
    end
  end
  private_constant :Diagnostics
end
