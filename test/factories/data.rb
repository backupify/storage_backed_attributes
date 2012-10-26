# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :mock_cassandra_datum, :aliases => [:cassandra_datum] do
    row_id { SecureRandom.hex(8) }
    document_id { SecureRandom.hex(8) }
    timestamp { Time.now }
    sequence(:payload) {|n| "data payload #{n}"}

    to_create do |instance|
      instance.class.test_cache[instance.id] = instance

      instance
    end
  end

  factory :storage_backed_datum do
    service_id { FactoryGirl.create(:service).id }
    document_id { SecureRandom.hex(8) }

    to_create do |instance|
      instance.class.test_cache[instance.id] = instance

      instance
    end
  end

end