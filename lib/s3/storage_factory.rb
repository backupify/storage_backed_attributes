class StorageFactory

  def self.new_storage_helper(bucket_name)
    S3::S3Helper.new(bucket_name, StorageBackedAttributes.storage_endpoint_config)
  end

end