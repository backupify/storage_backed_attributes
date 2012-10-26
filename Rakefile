# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "storage_backed_attributes"
  gem.homepage = "http://github.com/backupify/storage_backed_attributes"
  gem.license = "MIT"
  gem.summary = %Q{Allows models to add attributes which have content backed by s3.  Also provides basic s3 helper}
  gem.description = %Q{Allows models to add attributes which have content backed by s3.  Also provides basic s3 helper}
  gem.email = "dave@backupify.com"
  gem.authors = ["Dave Benvenuti"]
  # dependencies defined in Gemfile
end

#Uncomment for a public gem
#Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "storage_backed_attributes #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
