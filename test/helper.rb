require 'rubygems'
require 'bundler'
require 'active_support/test_case'

begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'test/unit'
require 'shoulda'
require 'factory_girl'
require 'fog'
require 'mocha'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'storage_backed_attributes'

StorageBackedAttributes.default_storage_bucket='sba-test-bucket'
StorageBackedAttributes.aws_access_key='access-key'
StorageBackedAttributes.aws_secret_access_key='secret-key'

require 'cassandra_datum'
require 'mock_cassandra_datum'
require 'service'
require 'storage_backed_datum'
require 'active_support/core_ext/numeric/bytes'
require 'tempfile'

require 'active_model/observing'
require 'active_model/callbacks'

FactoryGirl.definition_file_paths << File.dirname(__FILE__) + '/factories'
FactoryGirl.find_definitions

require 'test_helpers/storage_backed_test_helper'

class ActiveSupport::TestCase < ::Test::Unit::TestCase

  include TestHelpers::StorageBackedTestHelper

  def fixtures_root
    @fixtures_root ||= File.expand_path(File.dirname(__FILE__) + "/fixtures")
  end

  # This allows you to redefine a constant for a given block.
  # It restores the original value to the constant after the block executes.
  # constant_name should be a string that includes the full path includes all parent classes and modules.
  # for example: "S3::S3Helper::MAX_KEYS"
  def redefine_constant(constant_name, constant_value)
    constant_class = constant_name.split(/::/)[0..-2].join('::').constantize rescue Object
    constant_variable_name = constant_name.split(/::/).last

    old_value = constant_name.constantize

    constant_class.send(:remove_const, constant_variable_name.to_sym)
    constant_class.send(:const_set, constant_variable_name.to_sym, constant_value)

    if block_given?
      begin
        yield
      ensure
        constant_class.send(:remove_const, constant_variable_name.to_sym)
        constant_class.send(:const_set, constant_variable_name.to_sym, old_value)
      end
    end
  end

end
