# Originally defined in the cassandra_datum gem.  We just reopen the class here to give it a test_cache so we don't actually have to write to
# cassandra/postgresql

class MockCassandraDatum < CassandraDatum::Base

  include ActiveModel::Observing
  extend ActiveModel::Callbacks

  define_model_callbacks :save
  define_model_callbacks :destroy

  def save!
    _run_save_callbacks do
      self.class.test_cache[self.id] = self
    end
  end

  def self.test_cache
    @test_cache ||= {}
  end

end