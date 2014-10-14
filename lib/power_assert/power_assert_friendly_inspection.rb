# Usage:
#
# Refine inspect method in PowerAssert::PowerAssertFriendlyInspection
# before loading power_assert.
#
#   module PowerAssert
#     module PowerAssertFriendlyInspection
#       refine Array do
#         def inspect
#           "customized inspection"
#         end
#       end
#     end
#   end
#
#   require 'power_assert'

module PowerAssert
  module PowerAssertFriendlyInspection
  end
end
