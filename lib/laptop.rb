# ActiveResource frontend to Place model

require "active_resource"
require "digest/sha1"

class Laptop < ActiveResource::Base
  
  def self.set_params(site, user, password)
    self.site = site
    self.user = user
    self.password = Digest::SHA1.hexdigest(password)
    true
  end

  def self.stolen_list(hostnames = [])
    begin
      self.get(:requestBlackList)
    rescue
      $LOG.error("error : #{$!}.\n #{$!.backtrace.join("\n")}")
      nil
    end
  end

end

