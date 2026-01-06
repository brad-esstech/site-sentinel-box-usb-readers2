require 'sidekiq'
require 'sidekiq/api'

Sidekiq.configure_client do |config|
  config.redis = { db: 1 }
end

Sidekiq.configure_server do |config|
  config.redis = { db: 1 }
end

class AccessGrantedWorker
  include Sidekiq::Worker
  require 'httparty'

  def perform(contractor_id, card, direction, time, gate_id)
    puts "Contractor ID: #{contractor_id}"
    puts "Direction: #{direction}"
    puts "Logging granted access..."
  
    checks = 1.times.map do
      {
        contractor_id: contractor_id,
        type: direction,
        access_token: card,
        successful: true,
        executed_at: time
      }
    end
      
    payload = JSON.pretty_generate(checks: checks)
    # api_url = "https://staging.sitsentinel.com/api/gates/checks/batch"
     api_url = "https://www.sitesentinel.com.au/api/gates/checks/batch"
    
    response = HTTParty.post(api_url,
    { 
      :body => payload,
      :headers => {"Authorization" => "Token #{gate_id}", "Content-Type" => "application/json", "Accept" => "application/json"}
    })
    if response.code == 201
      puts "Logged."
    else
      puts "FAILED TO LOG SUCCESSFUL ACCESS!"
      puts "PAYLOAD:"
      puts payload
      puts "RESPONSE:"
      puts response
      raise "FAILED TO LOG SUCCESSFUL ACCESS! See log for details."
    end
  end
end

class AccessDeniedWorker
  include Sidekiq::Worker
  require 'httparty'
  
  def perform(card, direction, time, gate_id)
    puts "Card: #{card}"
    puts "Direction: #{direction}"
    puts "Logging denied access..."
  
    checks = 1.times.map do
      {
        type: direction,
        access_token: card,
        successful: false,
        executed_at: time
      }
    end

    payload = JSON.pretty_generate(checks: checks)
    # api_url = "https://staging.sitesentinel.com/api/gates/checks/batch"
     api_url = "https://www.sitesentinel.com.au/api/gates/checks/batch"
    
    response = HTTParty.post(api_url,
    { 
      :body => payload,
      :headers => {"Authorization" => "Token #{gate_id}", "Content-Type" => "application/json", "Accept" => "application/json"}
    })
    if response.code == 201
      puts "Logged."
    else
      puts "FAILED TO LOG DENIED ACCESS!"
      puts "PAYLOAD:"
      puts payload
      puts "RESPONSE:"
      puts response
      raise "FAILED TO LOG DENIED ACCESS! See log for details."      
    end
  end
end
