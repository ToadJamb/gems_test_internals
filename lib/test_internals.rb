gem_name = File.basename(__FILE__, '.rb')

require 'app_mode'
require 'test/unit'

require_relative File.join(gem_name, 'app_state')
require_relative File.join(gem_name, 'kernel')
require_relative File.join(gem_name, 'test_case')
