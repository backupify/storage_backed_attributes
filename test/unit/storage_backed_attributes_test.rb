require File.expand_path(File.dirname(__FILE__) + '/../helper.rb')

class StorageBackedAttributesTest < ActiveSupport::TestCase
  setup do
    @datum = FactoryGirl.create(:storage_backed_datum)
    assert @datum.valid?
    assert_has_storage_backed_attribute @datum, :content
  end

  should "allow setting and retrieving content" do
    @datum.content = "my content"
    @datum.save

    assert_equal "my content", @datum.reload.content
  end

  should "configure storage backed attribute with non-default bucket" do
    bucket_creator = Fog::Storage.new(:provider => 'AWS',
                          :aws_access_key_id => StorageBackedAttributes.aws_access_key,
                          :aws_secret_access_key => StorageBackedAttributes.aws_secret_access_key)

    bucket_creator.put_bucket('some-other-bucket')


    @datum.content_on_other_bucket = "my content"
    @datum.save


    bad_s3 = ::S3::S3Helper.new(StorageBackedAttributes.default_storage_bucket)
    good_s3 = ::S3::S3Helper.new('some-other-bucket')

    assert_blank bad_s3.fetch(@datum.service.storage_path, @datum.content_on_other_bucket_filename)
    assert_present good_s3.fetch(@datum.service.storage_path, @datum.content_on_other_bucket_filename)
  end

  should "define accessor for storage backed attribute object" do
    assert_equal S3::StorageBackedAttribute, @datum.content_attribute.class
  end

  should "track when content is changed" do
    assert !@datum.content_changed?

    @datum.content = "new content"

    assert @datum.content_changed?
  end

  should "define a save_content function to save to s3" do
    assert @datum.respond_to?(:save_content)

    @datum.content = '1234'
    @datum.save

    assert_equal 4, @datum.raw_content_size

    #should pass through other attributes
    record_keeping_attributes = %w[raw_content_size raw_content_digest stored_content_size stored_content_digest]
    sba = @datum.content_attribute

    record_keeping_attributes.each do |attr|
      assert_equal sba.send(attr), @datum.send(attr)
    end
  end
end