#!/usr/bin/ruby

require "rubygems"
require "logger"
require "pathname"

APP_ROOT = Pathname(__FILE__).realpath.dirname.realpath
$:.unshift APP_ROOT.join("lib")

require "leases_generator"

LOG_PATH = APP_ROOT.join("var", "errors.log")

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


$LOG = Logger.new(LOG_PATH)

lg = LeasesGenerator.new
lg.generate(hostnames)
