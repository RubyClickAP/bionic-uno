require "./init"
require 'resque/server'

Main.set :run, false
#Main.set :environment, :production
Main.set :environment, :development

Dir.mkdir('log') unless File.exists?('log')
#logger = Logger.new('log/unoconv.log')
#use Rack::CommonLogger, logger

#run Main
run Rack::URLMap.new(
  "/" => Main,
  "/api" => Api,
  "/queue" => Resque::Server.new
)
