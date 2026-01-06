require 'rubygems'
require 'daemons'

working_directory  = File.dirname(File.expand_path(__FILE__))
script = working_directory + '/reader_ingress.rb'
pid_folder = File.join(working_directory, 'pids') # directory where pid file will be stored

Daemons.run_proc(
  'reader_ingress', # name of daemon
  :dir_mode => :normal,
  :dir => pid_folder,
#  :backtrace => true,
#  :monitor => true,
  :log_output => true
) do
  exec "cd #{working_directory} && bundle exec ruby #{script}"
end
