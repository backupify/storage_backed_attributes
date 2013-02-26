require 'filter_io'
require 'logger_helper'

module S3
  class StorageBackedAttribute

    attr_accessor :raw_content_size
    attr_accessor :stored_content_size
    attr_accessor :raw_content_digest
    attr_accessor :stored_content_digest
    attr_accessor :service
    attr_accessor :should_compress
    attr_accessor :storage_bucket

    include LoggerHelper

    # create a new StorageBackedAttribute.  accepts an attributes hash.  any keys which don't correspond to a valid attribute will be ignored safely
    #
    # @param [Hash] attributes
    # @option attributes [Integer] :size
    # @option attributes [Integer] :stored_content_size
    # @option attributes [String] :raw_content_digest
    # @option attributes [String] :stored_content_digest
    # @option attributes [Object] :service a service is any object that responds to storage_path, decrypted_cipher_key, and decrypted_cipher_iv
    # @option attributes [Boolean] :should_compress
    # @option attributes [String] :storage_bucket
    #
    # @return [S3::StorageBackedAttribute] a newly initialized StorageBackedAttribute
    def initialize(attributes = {})
      attributes.each do |attr_name, value|
        self.send("#{attr_name}=", value) if self.respond_to?("#{attr_name}=")
      end
    end

    # set the content to be saved
    #
    # @param [String]  data.  can also be a stream or anything that responds to :read
    def content=(data)
      @in_content = nil
      @content = nil
      @content_changed = true

      if data.respond_to?(:read)
        @in_content = data
        self.raw_content_size = 0
      else
        @content = data
        self.raw_content_size = data.to_s.size
      end
    end

    # fetch the content from s3
    #
    # @param [String] filename filename, not including storage path
    #
    # @yield [String] raw_chunk if a block is passed, the content will be yielded in chunks
    #
    # @return [String] content from s3.  if a block is passed, nothing is returned
    def content(filename, &block)
      if @content.nil? && !content_changed?
        compressed = compressed?(filename)
        if block_given?
          cipher = decrypt_cipher
          zi = Zlib::Inflate.new

          s3.fetch(service.storage_path, filename) do |raw_chunk|
            chunk = cipher.update(raw_chunk)
            chunk = zi.inflate(chunk) if compressed
            block.call chunk
          end

          final = cipher.final
          final = zi.inflate(final) if compressed
          block.call final
        else

          decrypted_content = decrypt(s3.fetch(service.storage_path, filename))
          @content = compressed ? decompress(decrypted_content) : decrypted_content
        end

      elsif @in_content
        @content = @in_content.read
        @in_content = nil
      end

      @content
    end

    # has the content changed since initialization?
    #
    # @return [Boolean] whether the content has been updated
    def content_changed?
      @content_changed == true
    end

    # save the content to s3
    #
    # @param [String] filename filename to write to, not including storage path
    # @param [String] mime_type MIME type of the content, as a string
    def write_content_to_s3(filename, mime_type)
      if content_changed? && (@in_content.present? || @content.present?)
        io = @in_content.blank? ? StringIO.new(@content) : @in_content

        io = wrap_digest_buffer(io, :raw_content_digest)
        io = wrap_calculate_size_buffer(io, :raw_content_size)

        io = wrap_compress_buffer(io) if self.should_compress
        io = wrap_encrypt_buffer(io)
        io = wrap_calculate_size_buffer(io, :stored_content_size)
        io = wrap_digest_buffer(io, :stored_content_digest)

        io.read(1024) until io.eof?
        io.rewind

        opts = {
            'x-amz-meta-raw-content-sha256'     => self.raw_content_digest,
            'x-amz-meta-stored-content-sha256'  => self.stored_content_digest
        }

        opts[:content_type] = mime_type
        opts['x-amz-meta-compressed'] = 'true' if self.should_compress

        file = s3.head(service.storage_path, filename)

        if file && !file.metadata.has_key?('x-amz-meta-raw-content-sha256')
          sha = Digest::SHA256.new
          s3.fetch(service.storage_path, filename) { |chunk| sha << chunk }

          # A few notes on this codepath:
          # - This is for data already in S3 that doesn't have the metadata header we're looking for.
          # - We don't want to update the headers for the existing object because we'd have to issue a COPY command to do
          #   so.  Since we use bucket versioning, we'd end up with two copies of the object, which is the very thing we're
          #   trying to prevent.  As it turns out, GET requests are 1/10 the cost of COPY, so it's cheaper to just grab
          #   the object and check the digest of the fetched object.
          # - We will write out the metadata for the new object on save and that will be used the next time we try to save
          #   out an object with the same filename.

          if sha.hexdigest != opts['x-amz-meta-stored-content-sha256']
            s3.store(service.storage_path, filename, io, opts)
            log :warn, "Stored a new copy of existing content. Path: #{service.storage_path}; File: #{filename}; Byte cost: #{self.stored_content_size}"
          else
            log :warn, "Attempting to save duplicate content. Path: #{service.storage_path}; File: #{filename}; Bytes saved: #{self.stored_content_size}"
          end

        elsif file.nil? || (file.metadata['x-amz-meta-raw-content-sha256'] != opts['x-amz-meta-raw-content-sha256'])
          s3.store(service.storage_path, filename, io, opts)

          if file
            log :warn, "Storing duplicate; Old SHA: #{file.metadata['x-amz-meta-raw-content-sha256']}; New SHA: #{opts['x-amz-meta-raw-content-sha256']}; File: #{filename}; Byte cost: #{self.stored_content_size}"
          else
            log :debug, "Storing completely new content; Path: #{service.storage_path}; File: #{filename}; Byte cost: #{self.stored_content_size}"
          end
        else
          log :warn,  "Attempting to save duplicate content -- digest matched. Path: #{service.storage_path}; File: #{filename}; Bytes saved: #{self.stored_content_size}"
        end

        io.close

        @in_content = nil
      end

      @content_changed = false
    end
    
    # gets the authenticated url for a storage backed attribute
    #
    # @oarams [String] filename the filename to get the direct link for
    # @params [Hash] opts options to control authenticated url thats generated. Valid options are [:expires, :expires_in]
    # @return [String] url for the attribute
    def direct_url(filename, opts = {})
      s3.authenticated_url(service.storage_path, filename, opts) 
    end

    # get an s3 helper
    #
    # @return [::S3::Helper] Backupify S3 Helper
    def s3
      @s3 ||= ::S3::S3Helper.new(storage_bucket, StorageBackedAttributes.storage_endpoint_config)
    end

    private

    # encrypt an output stream
    #
    # @param [Data] io io stream to encrypt
    #
    # @visibility private
    def wrap_encrypt_buffer(io)
      return io if io.eof?

      cipher = encrypt_cipher
      FilterIO.new(io) do |data|
        out = cipher.update(data)

        if io.eof?
          out << cipher.final
          cipher = encrypt_cipher
        end

        out
      end
    end

    # compress an output stream
    #
    # @param [Data] io io stream to compress
    #
    # @visibility private
    def wrap_compress_buffer(io)
      return io if io.eof?

      zd = Zlib::Deflate.new(Zlib::BEST_COMPRESSION)
      FilterIO.new(io) do |data|
        out = zd.deflate(data)

        if io.eof?
          out << zd.finish
          zd = Zlib::Deflate.new(Zlib::BEST_COMPRESSION)
        end

        out
      end
    end

    # calculate the size of the data within an output stream
    #
    # @param [Data] io io stream to calculate size for
    #
    # @visibility private
    def wrap_calculate_size_buffer(io, attr)
      if io.eof?
        # Special case for empty data.
        self.send("#{attr}=", 0)
        io
      else
        counter = 0
        FilterIO.new(io) do |data|
          counter += data.size

          if io.eof?
            self.send("#{attr}=", counter)
            counter = 0
          end

          data
        end
      end

    end

    # calculate a SHA hash for the data within an output stream
    #
    # @param [Data] io io stream to calculate digest for
    #
    # @visibility private
    def wrap_digest_buffer(io, attr)
      if io.eof?
        # Special case for empty data.
        self.send("#{attr}=", '')
        io
      else
        sha = Digest::SHA256.new

        FilterIO.new(io) do |data|
          sha << data

          if io.eof?
            self.send("#{attr}=", sha.hexdigest)
            sha = Digest::SHA256.new
          end

          data
        end
      end

    end

    # is the content in the given file compressed?
    # this only checks the s3 head metadata, doesn't actually read the file, rescuing nil because if the datum doesn't exist, we don't want to throw an exception here
    #
    # @param [String] filename, not including path
    #
    # @visibility private
    #
    # @return [Boolean] whether or not the content is compressed
    def compressed?(filename)
      file = s3.head(service.storage_path, filename)
      file.present? && file.metadata['x-amz-meta-compressed'] == "true"
    end

    # compress the given content using zlib
    #
    # @param [String] content data to compress
    #
    # @visibility private
    #
    # @return [String] compressed content
    def compress(content)
      Zlib::Deflate.deflate(content, Zlib::BEST_COMPRESSION)
    end

    # decompress the given compressed content using zlib
    #
    # @param [String] content compressed content
    #
    # @visibility private
    #
    # @return [String] decompressed content
    def decompress(content)
      Zlib::Inflate.inflate(content)
    end

    [:encrypt, :decrypt].each do |method_name|
      define_method "#{method_name}_cipher" do
        cipher = OpenSSL::Cipher::Cipher.new('aes-256-cbc')
        cipher.send(method_name)
        cipher.key = service.decrypted_cipher_key
        cipher.iv = service.decrypted_cipher_iv
        return cipher
      end

      define_method method_name do |str|
        return str if str.blank?
        cipher = send("#{method_name}_cipher")
        ret = ''
        ret << cipher.update(str)
        ret << cipher.final
        ret
      end
    end

  end
end
