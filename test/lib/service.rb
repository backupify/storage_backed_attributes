class Service
  PUBLIC_KEY_STRING = <<-KEY
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5zwbMbBlXcxQQkztpRyk
yvtMXhkshKFH2GQIfsziEhWTQlfpdeA+qOIWsQPIcxoRmvPzh0kpwtfCJAefXkhK
oArBw6/qDIIUQ8efs1reyTkFqUxu7KUezB13UXC88F7CIwjjyR8UCm5XI0kk1Q01
mzLoETi7Ukj+YspW13e2nu5qCTeyCvxG9ri5Bc55XMbYlFcDK2EICxQLpEXa8qjv
rWwFs7QxZkO/6FZwwQYk6w2dNnUoaVfSRxXS1lSAxfLv43iQydY36O0FLNEOaTvx
IcuCLTnkNeN9BrkPj+t27bEoDryOSUjzg7yWodaQX2SXH48vjEAeZ+yDunFs9TZF
gwIDAQAB
-----END PUBLIC KEY-----
  KEY

  PRIVATE_KEY_STRING = <<-KEY
-----BEGIN RSA PRIVATE KEY-----
Proc-Type: 4,ENCRYPTED
DEK-Info: DES-EDE3-CBC,F61487380AD535D5

mtBdDo2dzmknSz+7Dw8mSr2oqYdv4GjljX2EjVjUCmbeAb2N0D0yF5+eZo9Al7bW
hIexpQC4eiNEvBPKrQIEycBMYmdpxQ233cYKiFc4d1WO7go5rup/Af93thDCSmL3
Yy4fA4ZrkoTAQukmoSb1vYgARLhn15dLSkuouyLLrbJ8zP6jBNpfdwNxzpXCcCJR
fem+mVFSFEzEP0dvO1QlWVBkRKgALyYtfY3NaPaYpQPJYZ54zOMygqXOzd/CBtzU
A5m4Y411Bh5bemzQMO20ZaFutQio0VdNiXbMdVMgkQIiak+RRVDUdQbQZpZrkT8J
T9dC4vOO3MfiFUa5NBdOR7d0nWTc8++sixdNrFpRyzi/iyZgIV86am2IQteiHUt8
EAk4cE5Ob8H27AAFvK86oIgmZCVbG8DPrOUufEHdj5i64FdLMGagNDgaFQBPJM8+
rPqSPspCySIU5eigeooK9Z5nVDwW3IW+HMUz1QSWqSv03NvtHZ4/SmfwOcaNCupv
+RTHXUpK+4bx8ieCvDKf/4UaxoqrVC3WJo8Jl5PwZA3aj9kpA/3iRACbgB2CVaDt
yaHPT084wG/F5amZVCOOGUr3KUnPW7O5E2YgaOsq81hbZUuPpLRtAOz5V7Qk99AJ
lyQtM3kS3NMPLKzNL3klDZDH2Vvl0sVOMv07BEr9VxQzHFII6jlGB1gJRLeUJfZE
ZjKJGNJGM1wxGfWxCftbLDWpxBQBXdowr3kRzTB8pVDq8Edp5frhCFpVOpTn/wXe
Q7uoVtVx679yG9dR/GQY0iG3gLCtQlYJDuJwBaLzEXNc59tj9RNwLRjMCsABxDgX
0MeXfzqI82GHwV+Vfn2KXCnc0eyG6AcJ5M4hHQz0yt/eMuT+J+XncxhUs2lWj1wP
odqasFq1NiPcJdL3Avp9Ur1pSeE9GSf8HJ/9HxL9/4D4FHj3xUZQzP9PHiKFJ8mL
C/JDd54z+h4jzC74INbx0hXfefIP5OuteoAxCNCYfuiPf+bA3nmmlVhzNdPhFUcc
5sWGdBBQrGTD6pF52Ojf5FZsIWHIa6Hv2PqzkG2d6CVqzxrllYiwhUcUHapqjwZ7
ex9/UmBgSAessbVGhfOD8lleJsWwbQMkpE8XiFuwnDvYijVZjxPULeOQsn+Y+lM7
M0+g0yfxR6SzyIhMN5qwZtOwN7I3a/WlLsyvy97SCYsTZcFMLoBQVRCgnbGS+3CD
GMyUQcf+AhLLzOLOpOChdG9BqdZ8+FMltf57A4vGGSRmvpnOjJEMGmbhkCq0p+s9
wQs74ksS/ywtR00EEcm4mWBesdj04LamNBN9s4QhlovUKQQyIEQUf5HRU6XXaT9c
GpXvVOMyQJpZ2xxbJQ5ZFA7S/L6fIWnIwSqIDBO/5ow15pJKz6m3FynIgV7tIvpo
Gu9KWiILBiE8jGhvI6SWenEsHQB+tPqGcpXYSmPZqijMpsIoWSQMcTE2KxbFGWex
4I4CizPfV4hqfkIK1qEEeX7VZejjKR82zg5RNTbwDZNVnCIHOnssiRAqZpcidbpW
PRe/eVgZurIfkgKUFyRX3d9mDT35Zh0pislhw8a/vH0K8vDIW3ivAGm2uNvIC0IN
-----END RSA PRIVATE KEY-----
  KEY

  PUBLIC_KEY = OpenSSL::PKey::RSA.new(PUBLIC_KEY_STRING, "backupify")
  PRIVATE_KEY = OpenSSL::PKey::RSA.new(PRIVATE_KEY_STRING, "backupify")

  include ActiveAttr::Model

  include ActiveModel::Observing
  extend ActiveModel::Callbacks

  define_model_callbacks :save
  define_model_callbacks :destroy

  attribute :id
  attribute :public_id

  attribute :cipher_key
  attribute :cipher_iv

  alias_method :_cipher_key, :cipher_key
  def cipher_key
    generate_encryption_keys

    _cipher_key
  end


  alias_method :_cipher_iv, :cipher_iv
  def cipher_iv
    generate_encryption_keys

    _cipher_iv
  end

  def save!
    _run_save_callbacks do
      self.class.test_cache[self.id] = self
    end
  end

  def generate_encryption_keys
    if self._cipher_key.blank?
      cipher = OpenSSL::Cipher::Cipher.new('aes-256-cbc')
      cipher.encrypt

      iv = cipher.random_iv
      key = cipher.random_key

      self.cipher_key = Base64.encode64(PUBLIC_KEY.public_encrypt(key)).strip
      self.cipher_iv = Base64.encode64(PUBLIC_KEY.public_encrypt(iv)).strip
    end
  end

  def decrypted_cipher_key
    decoded_cipher_key = Base64.decode64(self.cipher_key)
    PRIVATE_KEY.private_decrypt(decoded_cipher_key)
  end

  def decrypted_cipher_iv
    decoded_cipher_iv = Base64.decode64(self.cipher_iv)
    PRIVATE_KEY.private_decrypt(decoded_cipher_iv)
  end

  def storage_path
    "storage/#{self.id}"
  end

  def self.test_cache
    @test_cache ||= {}
  end
end
