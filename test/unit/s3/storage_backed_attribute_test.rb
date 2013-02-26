require File.expand_path(File.dirname(__FILE__) + '/../../helper.rb')

module S3
  class StorageBackedAttributeTest < ActiveSupport::TestCase

    setup do
      @s3 = Fog::Storage.new(:provider => 'AWS', :aws_access_key_id => '', :aws_secret_access_key => '')

      @service = FactoryGirl.create(:service)

      @filename = 'some.file'
      @mime_type = 'text/plain'

      sba_attributes = FactoryGirl.attributes_for(:cassandra_datum).merge(:filename => @filename, :service => @service, :mime_type => @mime_type, :should_compress => false, :storage_bucket => StorageBackedAttributes.default_storage_bucket)

      @storage_backed_attribute = StorageBackedAttribute.new(sba_attributes)
    end

    context "content" do

      should "not reload from S3 when setting content to nil" do
        @storage_backed_attribute.content = 'something not nil'

        assert_not_nil @storage_backed_attribute.content(@filename)
        assert @storage_backed_attribute.content_changed?

        @storage_backed_attribute.content = nil

        assert_nil @storage_backed_attribute.content(@filename)
        assert @storage_backed_attribute.content_changed?
      end

      should "keep track of content changing" do
        @storage_backed_attribute.s3.store(@service.storage_path, @filename, @storage_backed_attribute.encrypt('something not nil'))

        # If we haven't read content, it hasn't changed.
        assert !@storage_backed_attribute.content_changed?

        # Even if we read content, it really hasn't changed, we just have an in-memory copy of it now.
        original_content = @storage_backed_attribute.content(@filename)
        assert !@storage_backed_attribute.content_changed?

        # Writing content changes it.
        @storage_backed_attribute.content = nil
        assert @storage_backed_attribute.content_changed?

        # We don't track whether the write operation is the same as the original content as this would require
        # reading in from S3 for every content modification.  The odds of someone assigning contents to the same
        # value that's already in there is quite small and handling it does not justify the cost of constantly hitting S3.
        #
        # This test merely documents that fact.
        @storage_backed_attribute.content = original_content
        assert @storage_backed_attribute.content_changed?
      end

      should 'accept a file handle for content' do
        assert_equal nil, @storage_backed_attribute.raw_content_size # There is no size by default.

        tf = Tempfile.new('bs3dt', :encoding => 'ascii-8bit')
        tf.write ('a' * 128)
        tf.rewind
        tf.unlink
        @storage_backed_attribute.content = tf

        #should reset size to 0 until save
        assert_equal 0, @storage_backed_attribute.raw_content_size

        @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

        # should calculate size with io wrapper
        assert_equal 128, @storage_backed_attribute.raw_content_size
      end
    end
    
    context 'direct url' do
      setup do
        @s3_helper = ::S3::S3Helper.new(@storage_backed_attribute.storage_bucket, StorageBackedAttributes.storage_endpoint_config)
      end
      
      should 'return the authenticated url for a storage backed attribute' do
        expected_url = @s3_helper.authenticated_url(@storage_backed_attribute.service.storage_path, @filename) 
        assert_equal expected_url, @storage_backed_attribute.direct_url(@filename)
      end
    end

    context 'write_content_to_s3' do

      context 'when the content is not already stored' do
        should 'write encrypted content to S3' do
          @storage_backed_attribute.content = 'something new'
          def @storage_backed_attribute.encrypt_content?; true; end

          @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

          sha = Digest::SHA256.new

          file = @s3.get_object(StorageBackedAttributes.default_storage_bucket, "#{@service.storage_path}/#{@filename}")
          assert_equal 'text/plain', file.headers['Content-Type']
          assert_equal sha.hexdigest(@storage_backed_attribute.content(@filename)), file.headers['x-amz-meta-raw-content-sha256']
          assert_equal sha.hexdigest(file.body), file.headers['x-amz-meta-stored-content-sha256']
          assert_equal @storage_backed_attribute.encrypt(@storage_backed_attribute.content(@filename)), file.body
        end

        should 'store content digests in Cassandra' do
          @storage_backed_attribute.content = 'something new'
          def @storage_backed_attribute.encrypt_content?; true; end

          @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

          sha = Digest::SHA256.new

          file = @s3.get_object(StorageBackedAttributes.default_storage_bucket, "#{@service.storage_path}/#{@filename}")
          assert_equal sha.hexdigest(@storage_backed_attribute.content(@filename)), @storage_backed_attribute.raw_content_digest
          assert_equal sha.hexdigest(file.body), @storage_backed_attribute.stored_content_digest
        end
      end
      
      context 'when the content is already stored' do
        context 'when the raw content digest is present' do
          context 'and match' do
            setup do
              @storage_backed_attribute.content = 'abc'
              @storage_backed_attribute.write_content_to_s3 @filename, @mime_type
            end

            should 'not store the content' do
              @storage_backed_attribute.content = 'abc' # Don't be tempted to remove this.  We need to set the content again to reset the content_changed? state.
              @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

              assert_equal 1, @s3.get_bucket_object_versions(StorageBackedAttributes.default_storage_bucket, 'prefix' => "#{@service.storage_path}/#{@filename}").body['Versions'].size
            end
          end

          context 'and do not match' do
            setup do
              @storage_backed_attribute.content = 'something different'
              @storage_backed_attribute.write_content_to_s3 @filename, @mime_type
            end

            should 'not store the content' do
              @storage_backed_attribute.content = 'abc'
              @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

              assert_equal 2, @s3.get_bucket_object_versions(StorageBackedAttributes.default_storage_bucket, 'prefix' => "#{@service.storage_path}/#{@filename}").body['Versions'].size
            end
          end
        end

        context 'when the raw content digest is not present' do
          context 'when the file contents are the same' do
            setup do
              @storage_backed_attribute.content = 'abc'

              @s3.put_object(StorageBackedAttributes.default_storage_bucket,
                             File.join(@service.storage_path, @filename),
                             @storage_backed_attribute.encrypt(@storage_backed_attribute.content(@filename)))
            end

            should 'not store the content' do
              @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

              assert_equal 1, @s3.get_bucket_object_versions(StorageBackedAttributes.default_storage_bucket, 'prefix' => "#{@service.storage_path}/#{@filename}").body['Versions'].size
            end
          end

          context 'when the file contents are different' do
            setup do
              @storage_backed_attribute.content = 'something different'

              @s3.put_object(StorageBackedAttributes.default_storage_bucket,
                             File.join(@service.storage_path, @filename),
                             @storage_backed_attribute.encrypt(@storage_backed_attribute.content(@filename)))
            end

            should 'store the content' do
              @storage_backed_attribute.content = 'abc'
              @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

              assert_equal 2, @s3.get_bucket_object_versions(StorageBackedAttributes.default_storage_bucket, 'prefix' => "#{@service.storage_path}/#{@filename}").body['Versions'].size
            end
          end
        end

        should 'compress contents by default' do
          @storage_backed_attribute.should_compress = true
          @storage_backed_attribute.content = 'abc'
          @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

          assert_equal @storage_backed_attribute.send(:compress, 'abc'),
                       @storage_backed_attribute.send(:decrypt, @s3.get_object(StorageBackedAttributes.default_storage_bucket, "#{@service.storage_path}/#{@filename}").body)
        end

        should 'not compress contents when should_compress is false' do
          @storage_backed_attribute.should_compress = false
          @storage_backed_attribute.content = 'abc'
          @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

          assert_equal 'abc',
                       @storage_backed_attribute.send(:decrypt, @s3.get_object(StorageBackedAttributes.default_storage_bucket, "#{@service.storage_path}/#{@filename}").body)

        end
      end

      should "clear the content_changed state on save" do
        @storage_backed_attribute.content = 'blah'

        # Saving the content out to S3 should reset the change state.
        @storage_backed_attribute.write_content_to_s3 @filename, @mime_type
        assert_false @storage_backed_attribute.content_changed?
      end

      should "not save if the contents have not changed" do
        @storage_backed_attribute.content = 'new content'
        assert @storage_backed_attribute.content_changed?

        # First write resets the content_changed? state.
        @storage_backed_attribute.write_content_to_s3 @filename, @mime_type
        assert !@storage_backed_attribute.content_changed?

        file = @s3.get_object(StorageBackedAttributes.default_storage_bucket, "#{@service.storage_path}/#{@filename}")

        # Make sure that if a new file was to be written that it would have a different modification timestamp.
        now = Time.now
        Time.stubs(:now).returns(now + 3.minutes)

        # Second write should be a no-op.
        @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

        refetched_file = @s3.get_object(StorageBackedAttributes.default_storage_bucket, "#{@service.storage_path}/#{@filename}")

        assert_equal file.headers['Last-Modified'], refetched_file.headers['Last-Modified']
      end

      should 'store the raw contents size' do
        assert_equal nil, @storage_backed_attribute.raw_content_size # There is no size by default.

        @storage_backed_attribute.content = 'a' * 128
        assert_equal 128, @storage_backed_attribute.raw_content_size

        @storage_backed_attribute.content = ''
        assert_equal 0, @storage_backed_attribute.raw_content_size
      end

      should 'store the stored contents size' do
        assert_equal nil, @storage_backed_attribute.stored_content_size # There is no stored_content_size by default.

        @storage_backed_attribute.content = 'a' * 128
        @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

        file = @storage_backed_attribute.s3.head(@service.storage_path, @filename)
        assert_equal file.content_length, @storage_backed_attribute.stored_content_size

        @storage_backed_attribute.content = ''
        @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

        file = @storage_backed_attribute.s3.head(@service.storage_path, @filename)
        assert_equal file.content_length, @storage_backed_attribute.stored_content_size
      end

      context 'when the datum is empty' do
        should 'store an empty file to S3' do
          @storage_backed_attribute.content = StringIO.new('')

          @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

          file = @s3.get_object(StorageBackedAttributes.default_storage_bucket, "#{@service.storage_path}/#{@filename}")

          assert_equal 0, file.headers['Content-Length']
          assert_equal '', file.headers['x-amz-meta-raw-content-sha256']
          assert_equal '', file.headers['x-amz-meta-stored-content-sha256']
        end
      end
    end

    context "wrap_digest_buffer" do

      should "set attribute to empty string if eof" do
        @storage_backed_attribute.content = io = StringIO.new ''

        io = @storage_backed_attribute.send(:wrap_digest_buffer, io, :raw_content_digest)
        io.read(1024) until io.eof?

        assert_equal '', @storage_backed_attribute.raw_content_digest
      end

      should "set attribute to digest if content is present" do
        content = "sweet, sweet, content"
        @storage_backed_attribute.content = io = StringIO.new content

        io = @storage_backed_attribute.send(:wrap_digest_buffer, io, :raw_content_digest)
        io.read(1024) until io.eof?

        assert_equal (Digest::SHA256.new << content).hexdigest, @storage_backed_attribute.raw_content_digest
      end
    end

    context "wrap_calculate_size_buffer" do

      should "set to 0 if eof" do
        @storage_backed_attribute.content = io = StringIO.new ''

        io = @storage_backed_attribute.send(:wrap_calculate_size_buffer, io, :raw_content_size)
        io.read(1024) until io.eof?

        assert_equal 0, @storage_backed_attribute.raw_content_size
      end

      should "set size if content is present" do
        content = "sweet, sweet, content"
        @storage_backed_attribute.content = io = StringIO.new content

        io = @storage_backed_attribute.send(:wrap_calculate_size_buffer, io, :raw_content_size)
        io.read(1024) until io.eof?

        assert_equal content.length, @storage_backed_attribute.raw_content_size
      end
    end

    context "encryption" do

      should "have different encrypted content than original content" do
        @storage_backed_attribute.content = 'blahblah'

        assert_not_equal @storage_backed_attribute.encrypt(@storage_backed_attribute.content(@filename)), @storage_backed_attribute.content(@filename)
      end

      should "not attempt to encrypt data when it's empty" do
        encrypted_blank = @storage_backed_attribute.encrypt("")
        assert_equal "", @storage_backed_attribute.decrypt(encrypted_blank)
      end

      should "allow blank file handlers as content" do
        io = Tempfile.new('blank')
        io.unlink

        @storage_backed_attribute.content = io
        @storage_backed_attribute.write_content_to_s3 @filename, @mime_type

        assert @storage_backed_attribute.content(@filename).blank?
      end

      # RSA will raise a failure for large content, whereas AES-256 will not.  This test will cause the exception to be
      # raised if our encryption algorithm can't handle sufficiently large content.
      should "encrypt and decrypt large content properly" do
        encrypted_content = @storage_backed_attribute.encrypt("blahblah" * 100000)
        @storage_backed_attribute.s3.store(@service.storage_path, @filename, encrypted_content)

        assert_equal("blahblah" * 100000, @storage_backed_attribute.content(@filename))
      end

      should "use the service's decrypted cipher key/iv to encrypt and decrypt data" do
        test_string = 'boosh'

        cipher = OpenSSL::Cipher::Cipher.new('aes-256-cbc')
        cipher.encrypt
        cipher.key = @service.decrypted_cipher_key
        cipher.iv = @service.decrypted_cipher_iv

        expected_encrypted = ''
        expected_encrypted << cipher.update(test_string)
        expected_encrypted << cipher.final


        datum_cipher = @storage_backed_attribute.encrypt_cipher

        actual_encrypted = ''
        actual_encrypted << datum_cipher.update(test_string)
        actual_encrypted << datum_cipher.final

        assert_equal expected_encrypted, actual_encrypted


        datum_cipher = @storage_backed_attribute.decrypt_cipher

        actual_decrypted = ''
        actual_decrypted << datum_cipher.update(actual_encrypted)
        actual_decrypted << datum_cipher.final

        assert_equal test_string, actual_decrypted
      end

    end

  end
end
