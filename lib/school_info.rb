# ActiveResource frontend to SchoolInfo model

require "active_resource"
require "digest/sha1"

class SchoolInfo < ActiveResource::Base
  def self.set_params(site, user, password)
    self.format = :xml
    self.site = site
    self.user = user
    self.password = Digest::SHA1.hexdigest(password)
  end

  def self.list(hostnames = [])
    begin
      self.get(:list)
    rescue
      $LOG.error("error : #{$!}.\n #{$!.backtrace.join("\n")}")
      nil
    end
  end

  def self.lease_info(hostname)
    begin
      self.get(:lease_info, hostname: hostname)
    rescue
      $LOG.error("error : #{$!}.\n #{$!.backtrace.join("\n")}")
      nil
    end
  end
end
