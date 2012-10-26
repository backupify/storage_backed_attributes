class StorageBackedDatum
  include ActiveAttr::Model

  include ActiveModel::Observing
  extend ActiveModel::Callbacks

  attribute :service_id
  attribute! :document_id

  alias_method :id, :document_id

  define_model_callbacks :save
  define_model_callbacks :destroy

  include StorageBackedAttributes

  storage_backed_attribute :content
  storage_backed_attribute :content_on_other_bucket, :storage_bucket => 'some-other-bucket'


  def service
    Service.test_cache[service_id]
  end

  def content_filename
    document_id
  end

  def content_on_other_bucket_filename
    "#{document_id}-on-other-bucket"
  end

  def self.test_cache
    @test_cache ||= {}
  end

  def reload
    reloaded = self.class.test_cache[self.id]
    reloaded.attributes.keys.each do |attribute_name|
      self.send("#{attribute_name}=", reloaded.send(attribute_name))
    end

    self
  end

  def save!
    _run_save_callbacks do
      self.class.test_cache[self.id] = self
    end
  end

  def save
    save!
  end
end
