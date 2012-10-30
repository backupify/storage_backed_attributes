require 'active_support/concern'
require 'active_support/core_ext/module'

require 's3/storage_backed_attribute'
require 's3_helper'

require 'test_helpers/storage_backed_test_helper'

module StorageBackedAttributes
  extend ActiveSupport::Concern

  mattr_accessor :default_storage_bucket
  mattr_accessor :storage_endpoint_config
  mattr_accessor :logger

  included do
    raise "Please define a default s3 bucket via StorageBackedAttributes.default_storage_bucket=" unless StorageBackedAttributes.default_storage_bucket
    raise "Please define storage endpoint configurations via StorageBackedAttributes.storage_endpoint_config=" unless StorageBackedAttributes.storage_endpoint_config

    # keep track of the storage backed attribute names so we know which attributes to translate below in #translate_storage_accounting_attributes
    class_attribute :storage_backed_attribute_names
    self.storage_backed_attribute_names = []
  end

  module ClassMethods
    # define a new s3-backed attribute.  dynamically generates several methods on the class.
    # for every storaged_back_attribute defined, the class must also define a method "#{name}_filename", which must accept a revision as an argument
    # if the object supports revisions
    #
    # @param [String] name the attribute name
    # @param [Hash] options
    # @option options [String] :mime_type required - the mime type of the content to be stored
    # @option options [Symbol] :filename required - the function name to invoke on the attribute owner to generate a filename.  must accept a revision parameter if revisioning is to be supported for this particular attribute
    # @option options [Boolean] :compress optional - defaults to true, whether or not to compress the data when saving to s3
    # @option options [String] :bucket optional - s3 bucket to save to.  defaults to FacebookServiceConfig.aws.services_storage_bucket
    #
    # @scope class
    # @visibility protected
    #
    # given the call, "storage_backed_attribute :content", the following protected methods will be created:
    #
    #    __content_filename - invokes the method provided in options.  starts with "__" to avoid collisions
    #    content_attribute - accessor for a S3::StorageBackedAttribute object
    #    content(revision=nil)                - s3 getter.  accepts an optional block for streaming
    #    content=                                 - s3 setter
    #    content_changed?                    - starts as false, gets set to true when content is set, set to false again when saved
    #    save_content                          - ActiveModel before_save callback method that writes the content to s3
    #
    # and the class must define a method:
    #
    # def content_filename
    #   "some_filename.jpg"
    # end
    #
    # or, if revisioning is enabled:
    #
    # def content_filename(rev=nil)
    #   "some_filename_#{rev}.jpg"
    # end
    #
    # additionally, the accessors :content_size, :raw_content_digest, :stored_content_size, :stored_content_digest will be defined for book-keeping
    #
    def storage_backed_attribute(name, options={})
      options = {:compress => true, :mime_type => 'text/plain'}.merge(options)

      name = name.to_sym

      unless self.storage_backed_attribute_names.include?(name)

        # because this is a class_attribute, we need to do a += instead of a << so that subclasses won't modify the list of names of the base class
        self.storage_backed_attribute_names += [name]

        # lazy load the StorageBackedAttribute object for this particular attribute
        define_method "#{name}_attribute" do                                                                            # def content_attribute
          unless storage_backed_attributes[name]
            storage_bucket = options[:storage_bucket].present? ? options[:storage_bucket] :
                                                              StorageBackedAttributes.default_storage_bucket
            sba_attrs = self.attributes.merge(:service => respond_to?(:service) ? service : self,                         #   unless storage_backed_attributes['content']
                                            :should_compress => options[:compress],
                                            :storage_bucket => storage_bucket)
            attr = S3::StorageBackedAttribute.new(sba_attrs)                                                               #     attr = S3::StorageBackedAttribute.new(self.attributes.merge(:service => service))
            storage_backed_attributes[name] = attr                                                                       #     storage_backed_attributes['content'] = attr
          end

          storage_backed_attributes[name]                                                                               #    storage_backed_attributes['content']
        end                                                                                                             # end

        # getter for the attribute.  accepts an optional revision as well as an optional block for streaming
        define_method name do |*args, &block|                                                                           # def content(*args, &block)
          rev = args.first                                                                                              #    rev = args.virst

          if rev.present?                                                                                               #   if rev.present?
            self.send("#{name}_attribute").content(self.send("#{name}_filename", rev), &block)                           #      content_attribute.content(content_filename(rev), &block)
          else                                                                                                          #   else
            self.send("#{name}_attribute").content(self.send("#{name}_filename"), &block)                               #       content_attribute.content(content_filename, &block)
          end                                                                                                           #   end
        end                                                                                                             # end

        # setter for the attribute
        define_method "#{name}=" do |val|                                                                               # def content=(val)
          self.send("#{name}_attribute").send(:content=, val)                                                           #    content_attribute.content = val
        end                                                                                                             # end

        # ActiveRecord-esque changed? method for the attribute
        define_method "#{name}_changed?" do                                                                             # def content_changed?
          self.send("#{name}_attribute").content_changed?                                                               #   content_attribute.content_changed?
        end                                                                                                             # end

        # before_save callback.  writes the content to s3 and updates all of this object's book-keeping attributes
        # (size, digest, etc)
        define_method "save_#{name}" do                                                                                 # def save_content
          attr = self.send("#{name}_attribute")                                                                         #   attr = content_attribute
          attr.write_content_to_s3 self.send("#{name}_filename"), options[:mime_type]                                    #   attr.write_content_to_s3(__content_filename, options[:mime_type])

          self.send("raw_#{name}_size=", attr.raw_content_size)                                                         #   self.raw_content_size = attr.size
          self.send("raw_#{name}_digest=", attr.raw_content_digest)                                                     #   self.raw_content_digest = attr.raw_content_digest
          self.send("stored_#{name}_size=", attr.stored_content_size)                                                   #   self.stored_content_size = attr.stored_content_size
          self.send("stored_#{name}_digest=", attr.stored_content_digest)                                               #   self.stored_content_digest = attr.stored_content_digest
        end                                                                                                             # end

        before_save "save_#{name}"                                                                                      # before_save "save_content"

        # define book-keeping accessors
        if respond_to?(:attribute)
          attribute "raw_#{name}_size"                                                                                    # attribute "raw_content_size"
          attribute "raw_#{name}_digest"                                                                                  # attribute "raw_content_digest"
          attribute "stored_#{name}_size"                                                                                 # attribute "stored_content_size"
          attribute "stored_#{name}_digest"                                                                               # attribute "stored_content_digest"
        end
      end
    end
  end

  #  used to store StorageBackedAttribute data for each call to the class method :storage_backed_attribute
  #
  # @visibility protected
  #
  # @return [Hash] hash of attribute_name => Services::Base::StorageBackAttribute
  def storage_backed_attributes
    @storage_backed_attributes ||= {}
  end

  # invoked by #translate_attributes, translates all size values associated with storage backed attributes to integers
  #
  # @visibility protected
  def translate_storage_accounting_attributes
    self.class.storage_backed_attribute_names.each do |attribute_name|
      raw_size = self.send("raw_#{attribute_name}_size")
      stored_size = self.send("stored_#{attribute_name}_size")

      self.send("raw_#{attribute_name}_size=", raw_size.to_i) unless raw_size.blank?
      self.send("stored_#{attribute_name}_size=", stored_size.to_i) unless stored_size.blank?
    end
  end
end