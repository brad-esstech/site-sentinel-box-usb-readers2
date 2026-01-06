require 'logger'
require 'bcrypt'
require 'json'
require 'httparty'
require 'bugsnag'
require 'evdev'
require 'ffi'

# Bugsnag config
# Bugsnag.configure do |config|
#   config.api_key = BUGSNAG_API_KEY
# end

at_exit do
  if $!
    Bugsnag.notify($!)
  end
end
# end Bugsnag config

# We need to talk to the reader
module PCProxLib
  extend FFI::Library
  ffi_lib File.expand_path('lib/32/libhidapi-hidraw.so')
  ffi_lib File.expand_path('lib/32/libpcProxAPI.so')
  attach_function :usbConnect, [], :short
  attach_function :USBDisconnect, [], :short
  attach_function :BeepNow, [:int, :bool], :bool
  attach_function :SetDevTypeSrch, [:short], :short
  attach_function :GetDevCnt, [], :short
  attach_function :SetActDev, [:short], :short
  attach_function :getPartNumberString, [], :string
  attach_function :getESN, [], :string
  attach_function :GetQueuedID, [:short, :short], :short
  attach_function :GetQueuedID_index, [:short], :long
end

# Only scan USB devices, not serial
def set_device_type_to_usb
  rc = PCProxLib.SetDevTypeSrch(0) # 0 = USB only
  if rc == 1
    return true
  else
      return false
  end
end

def set_active_device(device)
  # returns true if able to set active device, otherwise false
  rc = PCProxLib.SetActDev(device)
  if rc == 1
    return true
  else
    return false
  end
end

def usb_connect
  # opens connection to all rfideas readers/devices
  # returns true in case success, false otherwise
  rc = PCProxLib.usbConnect()
  if rc == 1
    return true
  else
    return false
  end
end

def get_devices_count
  # returns the total number of connected rfideas readers.
  number_of_devices = PCProxLib.GetDevCnt()
  return number_of_devices
end

def get_esn
  # returns a string that will contains the ESN from the reader
  esn = PCProxLib.getESN()
  return esn
end

def get_part_number
  # returns the part number of active device
  # pcproxlib.getPartNumberString.restype = ctypes.POINTER(ctypes.c_char)
  part_number = PCProxLib.getPartNumberString()
  # if partNb_p == None:
  #     return None;
  # else:
  #  return ctypes.string_at(partNb_p).decode('utf-8')
  return part_number
end

def find_device(esn)
  connect = usb_connect
  if connect == false
    @log.error "Error: couldn't connect to any card readers. Aborting."
    abort
  end
  number_of_devices = get_devices_count
  if number_of_devices > 0
    @log.info "Found #{number_of_devices} devices!"
    0.upto(number_of_devices-1) do |device|
      @log.info "Connecting to device #{device}..."
      set_active_device(device)
      @log.info "Part number: #{get_part_number}"
      this_esn = get_esn
      @log.info "ESN from get_esn function: #{this_esn}"
      @log.info "ESN we're looking for: #{esn}"
      esn = nil if esn == "" # edge case - JB test reader that has a blank ESN
      if this_esn == esn
        return device
      else
        @log.info "Didn't find the right device :("
        if device == number_of_devices-1
          return nil
        end
      end
      @log.info "-----------------------------------------------"
    end
  else
    @log.info "Didn't find any devices! :("
    return nil
  end
end

def initialise_and_connect_to_ingress2_reader

  usb_only = set_device_type_to_usb
  if usb_only == false
    @log.error "Could not set PCProxLib device types to USB only!"
    abort
  end
  
  @log.info "Connecting to reader via SDK..."
  
  @log.info "Searching for reader with ESN of #{INGRESS2_CARD_READER_ESN}..."
  ingress_reader_id = find_device(INGRESS2_CARD_READER_ESN)
  
  if ingress_reader_id == nil
    @log.error "Couldn't find reader with ESN of #{INGRESS2_CARD_READER_ESN}!"
    abort
  end
  
  @log.info "Reader ##{ingress_reader_id} has an ESN of #{INGRESS2_CARD_READER_ESN}!"
  
  set_active_device(ingress2_reader_id)
  @log.info "Connected to reader."
end

def read_card

  card_number = ""

  # Check if GetQueuedID is available for this reader
  get_queued_id_available = PCProxLib.GetQueuedID(1, 0)

  if get_queued_id_available == false
    abort("GetQueuedID is not available.")
  end

  # index 32 returns the number of bits read
  bits_read = PCProxLib.GetQueuedID_index(32)

  # @log.debug "Bits read: #{bits_read}"

  # calculate bytes to read
  bytes_to_read = (bits_read + 7) / 8

  # read a minimum of at least 8 bytes
  bytes_to_read = 8 if bytes_to_read < 8

  bytes_to_read.times do |i|

    # get the card number chunk from index i
    tmp = PCProxLib.GetQueuedID_index(i)

    # convert the card number chunk to hex
    tmp = tmp.to_s(16)

    # pad the hex value with leading zeros, if needed
    tmp = tmp.rjust(2, '0')

    # add the hex value to the beginning of the card number string
    card_number = tmp + card_number
  end

  if bits_read == 32
    # regular swipe card, need to do some magic to get the actual number
    card_number_as_int = Integer("0x#{card_number}")
    return card_number_as_int
  elsif bits_read >= 40
    # mobile app scan via BLE
    # no magic needed, just strip off any leading zeros
    card_number_as_int = card_number.sub(/^0*/, '')
    @log.debug card_number_as_int
    return card_number_as_int
  else
    return 0
  end
end

def get_access_list
  until File.exist? ACCESS_LIST
    @log.error "Access list #{ACCESS_LIST} does not exist... waiting 3 seconds..."
   sleep(3)
  end
  raw = File.read(ACCESS_LIST) # contents of file
  modified = File.mtime(ACCESS_LIST) # modified date/time
  @log.debug "Got access list."
  parsed_data = JSON.parse(raw)
  access_list = parsed_data["data"]
  @log.debug "Parsed access list."
  {
    access_list: access_list,
    modified: modified
  }
end

def need_access_list_update(last_modified)
  until File.exist? ACCESS_LIST
    @log.error "Access list #{ACCESS_LIST} does not exist... waiting 3 seconds..."
   sleep(3)
  end
  modified = File.mtime(ACCESS_LIST) # modified date/time
  if modified > last_modified
    true
  else
    false
  end
end

def access_allowed_beeps
x = PCProxLib.BeepNow(1, true)
end

def access_denied_beeps
x = PCProxLib.BeepNow(3, false)
end

def access_granted(card, direction)
  @log.debug "Access granted: #{card}"
  puts "ACCESS GRANTED"

  # control relays for solenoid
  # calls external script so this script keeps on moving
  # external python script even, because fuck managing GPIO ports with ruby

  if direction == "in"
    @log.debug "firing ingress relay..."
    in_action = fork { exec("python3 /home/ubuntu/site-sentinel-box-usb-readers/solenoid_relay1.py") }
    Process.detach(in_action)
   end
  access_allowed_beeps
end

def access_denied(card)
  @log.warn "Access denied: #{card}"
  puts "ACCESS DENIED"
  access_denied_beeps
end

def log_access_granted(contractor_id, card, direction)
  AccessGrantedWorker.perform_async(contractor_id, card, direction, Time.now, GATE_ID)
end

def log_access_denied(card, direction)
  AccessDeniedWorker.perform_async(card, direction, Time.now, GATE_ID)
end

def is_contractor_on_site(card)
  
  on_site_report_url = "#{API_BASE}/gates/reports/on_site"

  begin
    @log.debug "Timeout: #{ANTI_PASSBACK_SERVER_QUERY_TIMEOUT} seconds"
    starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = HTTParty.post(on_site_report_url, {
      body: "access_token=#{card}",
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "charset" => "utf-8",
        "Authorization" => "Token #{GATE_ID}"
      },
      timeout: ANTI_PASSBACK_SERVER_QUERY_TIMEOUT
    })

    ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed = ending - starting
    @log.debug "TIME ELAPSED: #{elapsed} seconds"
    @log.debug "Response code: #{response.code}"
    
    if response.code == 200
      # check to see if returned JSON includes the card we're looking for, return true or false
      if response["data"][0].nil? # did we get a record back?
        return false
      else
        @log.debug "Contractor is currently listed as on site!"
        @log.debug "Last checked in - #{response["data"][0]["checked_in_at"]}"
        return true
      end

    else
      @log.debug "ERROR! Non-200 response code from server."
      @log.debug "Response code: #{response.code}"
      @log.debug "Response: #{response}"
      return nil
    end

  rescue Net::OpenTimeout, Net::ReadTimeout => error
    @log.debug "Timeout (#{ANTI_PASSBACK_SERVER_QUERY_TIMEOUT} sec) occurred attempting to verify if contractor is currently on site."
    return nil
  end
end

def verify_card_access(card, access_list, direction)
  puts "VERIFYING..."
  @log.debug "Verifying card access: #{card}"
  encrypted_card = BCrypt::Engine.hash_secret(card, SALT)
  puts "Card: #{encrypted_card}"
  @log.debug "Encrypted card: #{encrypted_card}"

  contractor = access_list.find { |h| h['token'] == encrypted_card }
  
  if not contractor.nil? # make sure they're in the access list

    if direction == "in"
      
      if ANTI_PASSBACK # set in config.rb
        
        @log.debug "Checking to see if contractor is already marked as on site..."
        # contractor has access to site;
        # check to see if they are currently on site or not
        on_site = is_contractor_on_site(card)
        
        if on_site == true
          @log.debug "Contractor is already marked as on site!"
        elsif on_site == false
          @log.debug "Contractor is not marked as on site."
        elsif on_site == nil
          @log.debug "Unable to determine if contractor is marked as on site or not."
          @log.debug "Could be a server timeout, non-200 response or other issue."
          @log.debug "Assuming contractor is NOT already on site to minimise site access issues."
          on_site = false
        end
        
      else
        on_site = false # force to 'not on site' to continue process below
      end
    
      if not on_site
        # contractor is not currently on site, or
        # we couldn't determine if they were on site or not, or
        # we're not checking ANTI_PASSBACK IN; allow them in!
        access_granted(encrypted_card, direction)
        log_access_granted(contractor["contractor_id"], card, direction)
      else
        access_denied(encrypted_card)
        log_access_denied(card, direction)
      end
    
  else # not in access list
    @log.debug "Card is not present in the access list."
    access_denied(encrypted_card)
    log_access_denied(card, direction)
  end
end

def reader_online(reader, direction)
   reader.BeepNow(2, false)
end
