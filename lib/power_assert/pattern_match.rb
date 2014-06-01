require 'pattern-match/core'

class << Array
  include PatternMatch::Deconstructable

  def deconstruct(val)
    accept_self_instance_only(val)
    val
  end

  private

  def accept_self_instance_only(val)
    raise PatternMatch::PatternNotMatch unless val.kind_of?(self)
  end
end
