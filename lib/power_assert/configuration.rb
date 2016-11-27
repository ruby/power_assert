module PowerAssert
  class << self
    def configuration
      @configuration ||= Configuration[false, false]
    end

    def configure
      yield configuration
    end
  end

  SUPPORT_ALIAS_METHOD = TracePoint.public_method_defined?(:callee_id)
  private_constant :SUPPORT_ALIAS_METHOD

  class Configuration < Struct.new(:lazy_inspection, :_trace_alias_method)
    def _trace_alias_method=(bool)
      super
      if SUPPORT_ALIAS_METHOD
        warn '_trace_alias_method option is obsolete. You no longer have to set it.'
      end
    end
  end
  private_constant :Configuration
end
