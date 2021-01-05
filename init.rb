ROOT_DIR = File.expand_path(File.dirname(__FILE__)) unless defined? ROOT_DIR

require "rubygems"

begin
  require File.expand_path("vendor/dependencies/lib/dependencies", File.dirname(__FILE__))
rescue LoadError
  require "dependencies"
end

require "monk/glue"
require "yaml"
require "json"
require "haml"
require "scrivener"
require "ohm"
#require "sass"

require File.expand_path("vendor/aasm-5.1.1/lib/aasm", File.dirname(__FILE__))

class Main < Monk::Glue
  set :app_file, __FILE__
  cookie_settings = {        
    :path         => "/",
    :expire_after => 120, 
    :secret       => monk_settings(:sitekey),
    :httponly     => true
  }
  use Rack::Session::Cookie, cookie_settings  
end

class Api < Monk::Glue
  set :app_file, __FILE__
end

# Model definitions - defined here so that associations work.
class Client < Ohm::Model
end

class Profile < Ohm::Model
end

class Doc < Ohm::Model
  include AASM
  #require 'rvideo'
end

class DocEncoding < Ohm::Model
  include AASM
  #require 'streamio-ffmpeg'
end

class Notification < Ohm::Model
  include AASM
  require 'rest_client'
end

# Connect to redis database.
#Ohm.connect(monk_settings(:redis))
#Ohm.redis = Redic.new(monk_settings(:resque_redis))
Ohm.redis = Redic.new("redis://127.0.0.1:6379")

require 'resque'
#require 'fileutils'
# Setup Resque to connect to redis
Resque.redis = monk_settings(:resque_redis)
#Resque.redis = Monk::Glue::settings(:resque_redis)
#config = YAML.load_file(File.join(ROOT_DIR, 'config/settings.yml'))
#Resque.redis = config[:redis]
Resque.logger = ::Logger.new(root_path("log", "#{RACK_ENV}_resque.log"))
#Resque.logger = ::Logger.new(File.join(ROOT_DIR, "log/#{RACK_ENV}_resque.log"))
#Resque.logger = ::Logger.new(Monk::Glue::root_path("log", "#{RACK_ENV}_resque.log"))

# Load all application files.
Dir[root_path("app/**/*.rb")].each do |file|
  require file
end

# Load all extensions
Dir[root_path("lib/extensions/*.rb")].each do |file|
  require file
end

Main.run! if Main.run?