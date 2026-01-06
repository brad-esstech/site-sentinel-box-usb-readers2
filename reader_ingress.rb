#!/usr/bin/env ruby

require_relative 'config2.rb' # site config
require_relative 'common2.rb' # common functions
require_relative 'worker2.rb' # sidekiq workers

@log = Logger.new('/home/ubuntu/site-sentinel-box-usb-readers2/log/ingress2.txt', 'daily')
@log.datetime_format = "%d-%m-%Y %H:%M:%S"

@log.info "-------------------------------------------"
@log.info "Starting..."

if ANTI_PASSBACK
  @log.info "Anti-Passback is enabled for ingress."
else
  @log.info "Anti-Passback is disabled."
end

# initial load of access list
@log.info "Getting access list..."
@access_list = get_access_list
@log.info "Got access list."

# initial connection to reader
initialise_and_connect_to_ingress2_reader

@log.info "Sending two beeps to show reader is online..."
reader_online(PCProxLib, "ingress")
@log.info "Beeps sent."

time_to_quit = false

until time_to_quit == true
  # try to get ESN from the reader, to ensure it's still connected      
  esn = get_esn
  # @log.debug "ESN: #{esn.inspect}" # will fill the logs but good for debugging
  if esn == nil
    @log.info "Error connecting to reader!"
    # reconnect to reader
    initialise_and_connect_to_ingress2_reader
    sleep 0.2
  end
  card = read_card
  sleep 0.25
  if card != 0
    @log.info "Found card: #{card}..."
    unless card.to_s.empty?
      if need_access_list_update(@access_list[:modified])
        @log.debug "Access list on disk is new - refresh..."
        @access_list = get_access_list
      else
        @log.debug "Access list on disk is up to date..."
      end  
      verify_card_access(card, @access_list[:access_list], "in")
    end
  end

  trap "SIGINT" do
    PCProxLib.USBDisconnect() # disconnect all USB readers
    exit
  end
end
