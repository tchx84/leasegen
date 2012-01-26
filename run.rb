#!/usr/bin/ruby

require "rubygems"
require "logger"
require File.join(File.dirname(__FILE__), 'lib', 'leases_generator')

LOG_PATH = File.join(File.dirname(__FILE__), "var", "errors.log")

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

    hostnames.each { |hostname|
      if !hostname.match(/schoolserver\.\w+\.\w+\.paraguayeduca\.org/)
        raise "Error de sintaxis"
      end
    }

  end
rescue
  usage()
  exit(-1)
end


$LOG = Logger.new(LOG_PATH)

lg = LeasesGenerator.new
lg.generate(hostnames)
