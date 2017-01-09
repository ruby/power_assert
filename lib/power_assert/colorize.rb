warn 'power_assert/colorize are experimental'

require 'power_assert/configuration'

PowerAssert.configure do |c|
  c.lazy_inspection = true
  c._colorize_message = true
  c._use_pp = true
end
