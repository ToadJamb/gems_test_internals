gem_name = File.basename(__FILE__, '.rb')

require 'test/unit'
require 'app_mode'

require_relative File.join(gem_name, gem_name)
require_relative File.join(gem_name, 'test_case')
