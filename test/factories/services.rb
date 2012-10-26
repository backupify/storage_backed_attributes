# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :service do
    sequence :id
    public_id { SecureRandom.uuid }

    to_create do |instance|
      instance.class.test_cache[instance.id] = instance

      instance
    end

  end
end
