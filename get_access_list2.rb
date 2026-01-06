#!/usr/bin/env ruby

require_relative 'config2.rb' # load site config
require 'httparty'

#api_url = "https://staging.sitesentinel.com/api/gates/access_tokens"
api_url = "https://www.sitesentinel.com.au/api/gates/access_tokens"

response = HTTParty.get(api_url, {
  headers: {"Authorization" => "Token #{GATE_ID}" }
})

if response.code == 200
  File.write("/home/ubuntu/site-sentinel-box-usb-readers2/access_list2.txt", response.body)
else
  puts "ERROR!"
end
