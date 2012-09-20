#!/usr/bin/ruby

require "rubygems"
require "logger"
require "pathname"

APP_ROOT = Pathname(__FILE__).realpath.dirname.realpath
$:.unshift APP_ROOT.join("lib")

require "leases_generator"

LOG_PATH = APP_ROOT.join("var", "leasegen.log")

def usage()
  puts <<EOF

   USAGE:
    #Generate files for all the servers
    ruby run.rb 
    or
    #Generate files only for a few servers
    ruby run.rb "hostname1,hostname2,hostnameN" 

EOF

end

hostnames = []

begin 
  if ARGV.length > 0
    hostnames = ARGV[0].split(',').map { |hostname| hostname.strip }
  end
rescue
  usage()
  exit(-1)
end


$LOG = Logger.new(LOG_PATH, "monthly")
$LOG.info("Starting")

begin
  lg = LeasesGenerator.new
  lg.fetch_stolen_list
  lg.generate(hostnames)
rescue LeasesGeneratorError => e
  puts "ERROR: #{e.message}"
  $LOG.fatal(e.message)
  exit(-1)
rescue Exception => e
  puts "Unhandled exception: #{e.message}"
  puts e.backtrace.inspect
  $LOG.fatal(e.message)
  $LOG.fatal(e.backtrace.inspect)
  exit(-1)
end

exit(0)
