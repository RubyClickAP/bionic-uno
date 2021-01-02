require "./init"
require 'resque/server'

Main.set :run, false
#Main.set :environment, :production

#run Main
run Rack::URLMap.new(
  "/" => Main,
  "/api" => Api,
  "/queue" => Resque::Server.new
)
