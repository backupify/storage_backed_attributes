require 'excon'
require 's3_helper'

module S3
  class S3Helper
    def self.new(bucket)
      S3::Helper.new(bucket, StorageBackedAttributes.storage_endpoint_config)
    end
  end
end