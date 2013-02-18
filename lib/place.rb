# ActiveResource frontend to Place model

require "active_resource"
require "digest/sha1"

class Place < ActiveResource::Base
  
  def self.set_params(site, user, password)
    self.format = :xml
    self.site = site
    self.user = user
    self.password = Digest::SHA1.hexdigest(password)
    true
  end

  def self.getSchoolsInfo(hostnames = [])
    schools_info = Array.new
    begin
      schools_info = self.get(:schools_leases, :hostnames => hostnames)
    rescue
      $LOG.error("error : #{$!}.\n #{$!.backtrace.join("\n")}")
    end
    schools_info
  end

end

