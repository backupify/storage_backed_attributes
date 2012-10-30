require 'fog'

module TestHelpers
  module StorageBackedTestHelper
    extend ActiveSupport::Concern

    included do

      Fog.mock!

      setup do
        # Make sure our storage bucket is created before tests start trying to write to it.
        s3 = Fog::Storage.new(:provider => 'AWS',
                              :aws_access_key_id => '',
                              :aws_secret_access_key => '')
        s3.put_bucket(StorageBackedAttributes.default_storage_bucket)
        s3.put_bucket_versioning(StorageBackedAttributes.default_storage_bucket, 'Enabled')
      end

      teardown do
        Fog::Mock.reset
      end
    end

    def dump_s3(bucket, prefix=nil)
      result = {}
      s3 = S3::S3Helper.new(bucket, StorageBackedAttributes.storage_endpoint_config)
      s3.walk_tree(prefix) do |f|
        result[f.key] = f
      end
      return result
    end


    # assert whether the given object has a StorageBackedAttribute with the given name and set up properly with the given options
    #
    # @param [Object] object any ol' object that responds to :save!, :reload, and the proper s3/storage book-keeping attribute methods
    # @param [Symbol] attribute_name the name of the StorageBackedAttribute the that object should have
    # @param [Hash] options
    # @option options [Boolean] :compress whether the given StorageBackedAttribute should compress content.  Defaults to true
    def assert_has_storage_backed_attribute(object, attribute_name, options={})
      options = {:compress => true}.merge(options)

      assert object.respond_to?(attribute_name), "object should respond to :#{attribute_name}"
      assert object.respond_to?("#{attribute_name}="), "object should respond to :#{attribute_name}="
      assert object.respond_to?("#{attribute_name}_changed?"), "object should respond to :#{attribute_name}_changed?"
      assert object.respond_to?("#{attribute_name}_attribute"), "object should respond to protected method :#{attribute_name}_attribute"

      storage_backed_attribute = object.send("#{attribute_name}_attribute")
      assert_kind_of S3::StorageBackedAttribute, storage_backed_attribute, "object##{attribute_name}_attribute should be a S3::StorageBackedAttribute, but its a #{object.class.name}"

      object.send("#{attribute_name}=", 'some value')
      assert_equal 'some value', storage_backed_attribute.content(object.send("#{attribute_name}_filename"))
      assert object.send("#{attribute_name}_changed?"), "object##{attribute_name}_changed? should be true"
      assert_equal 'some value', object.send(attribute_name)

      object.save!
      assert_equal "some value", object.reload.send(attribute_name)

      assert_equal object.send("raw_#{attribute_name}_size"), storage_backed_attribute.raw_content_size, "raw_#{attribute_name}_size mismatch"
      assert_equal object.send("stored_#{attribute_name}_size"), storage_backed_attribute.stored_content_size, "stored_#{attribute_name}_size mismatch"
      assert_equal object.send("raw_#{attribute_name}_digest"), storage_backed_attribute.raw_content_digest, "raw_#{attribute_name}_digest mismatch"
      assert_equal object.send("stored_#{attribute_name}_digest"), storage_backed_attribute.stored_content_digest, "stored_#{attribute_name}_digest mismatch"

      assert_equal options[:compress], storage_backed_attribute.should_compress, "wrong #should_compress value for storage backed attribute"
    end

  end
end
