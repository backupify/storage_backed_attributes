source "http://rubygems.org"

gem 'activesupport'
gem 'fog'

gem 'exception_helper', :git => 'git@github.com:backupify/exception_helper.git'
gem "filter_io", :git => "git://github.com/backupify/filter_io.git"

gem 's3_helper', :git => "git@github.com:backupify/s3_helper.git"

gem "excon"

group :development do
  gem "rdoc"
  gem "bundler"
  gem "jeweler"
end

group :test do
  gem "log4r"
  gem 'ci_reporter'
  gem 'simplecov'
  gem 'simplecov-rcov'
  gem "factory_girl"
  gem "shoulda"
  gem "test-unit"
  gem "cassandra_datum", :git => 'git@github.com:backupify/cassandra_datum.git'
  gem "active_attr"
  gem "activerecord"
  gem "mocha"
end
