#!/usr/bin/env ruby

#==============================================================================
#
# iGoat Server
#
# Authors:
#   Sean Eidemiller (sean@krvw.com)
#
# Ports:
#   8080/HTTP
#   8443/HTTPS (SSL)
#
# Endpoints:
#   POST /igoat/user
#   GET /igoat/token?username=<username>&password=<password>
#
# Examples:
#   POST http://localhost:8080/igoat/user
#     { firstName: <string>, lastName: <string>, accountNumber: <string>, ... }
#   POST https://localhost:8443/igoat/user
#     { firstName: <string>, lastName: <string>, accountNumber: <string>, ... }
#
#   GET http://localhost:8080/igoat/token?username=sean&password=igoat
#   GET https://localhost:8443/igoat/token?username=sean&password=igoat
#
#==============================================================================

require 'rubygems'
require 'sinatra/base'
require 'webrick'
require 'webrick/https'
require 'openssl'
require 'json'

$request_count = 0
$mutex = Mutex.new

class GoatServer < Sinatra::Base

  # Endpoint definitions.
  post "/igoat/user" do
    if (!request.secure?)
      log_stolen_info "The user's account information was stolen by anyone on your Wi-Fi!"
    end
    headers "X-Goat-Secure" => request.secure?.to_s
    content_type :json
    json = JSON.parse request.body.read
    json['id'] = increment_count
    JSON.pretty_generate json
  end

  get "/igoat/token" do
    if (!request.secure?)
      log_stolen_info "The user's login credentials were stolen by everyone on your Wi-Fi!"
    end
    headers "X-Goat-Secure" => request.secure?.to_s
    response.set_cookie("SessionID", "34A7EF-115C24-8F21CD-#{increment_count}")
  end

  private

  def increment_count
    $mutex.synchronize do
      return $request_count += 1
    end
  end

  def log_stolen_info(message)
    puts "\n********************************************************************************"
    puts "WARNING: #{message}"
    puts "********************************************************************************\n\n"
  end

  def log(message)
    puts "GoatServer [#{Time.new.strftime("%Y-%m-%d %H:%M:%S")}]: #{message}"
  end
end

# Server configuration.
options_hashes = [
  {
    :Port => 8443,
    :Logger => WEBrick::Log::new($stderr, WEBrick::Log::WARN),
    :DocumentRoot => "/",
    :SSLEnable => true,
    :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
    :SSLCertificate => OpenSSL::X509::Certificate.new(File.open("server.crt").read),
    :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.open("server.key").read),
    :SSLCertName => [[ "CN", WEBrick::Utils::getservername ]]
  },
  {
    :Port => 8080,
    :Logger => WEBrick::Log::new($stderr, WEBrick::Log::WARN),
    :DocumentRoot => "/",
    :SSLEnable => false
  }
]

# Start each server in a separate thread.
server_threads = []

options_hashes.each do |options_hash|
  server_threads << Thread.new(options_hash) { |options|
    Rack::Handler::WEBrick.run(GoatServer, options)
  }
end

puts "OWASP iGoat server initialized; accepting connections..."

server_threads.each { |server_thread| server_thread.join }
