require_relative 'test_helper'

class TestNilPathLocation < Test::Unit::TestCase
  include PowerAssertTestHelper

  t do
    obj = []
    def obj.foo; self; end
    enum = Enumerator.new {|y| y << obj.foo }
    def enum.inspect; '#<Enumerator>'; end
    assert_equal <<END.chomp, assertion_message {
      enum.next.foo
      |    |    |
      |    |    []
      |    []
      #<Enumerator>
END
      enum.next.foo
    }
  end

  t do
    # Yielding on a non-target thread keeps the `TracePoint` for `:call` and `:c_call` events enabled while
    # the `Enumerator`'s fiber runs, so that `app_context?` walks caller locations containing a frame without a path.
    enum = Enumerator.new {|y| y << 1 }
    message = ::PowerAssert.start(-> { enum.next }) do |pa|
      Thread.new { pa.yield }.join
      pa.message
    end
    assert_equal '', message
  end
end
