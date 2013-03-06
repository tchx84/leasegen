# Gets the list of schools with it's SNs (and UUIDs) and generates the leases
#
# author: Raul Gutierrez S. (rgs@paraguayeduca.org)

require 'digest/md5'
require 'fileutils'
require 'tempfile'
require 'parseconfig'
require 'school_info'
require 'laptop'

class LeasesGeneratorError < StandardError
end

class LeasesGenerator

  MD5SUMS_DIR = APP_ROOT.join("var")

  def initialize
    config_file = APP_ROOT.join("etc", "leasegen.conf")
    begin
      @config_params = ParseConfig.new(config_file)
    rescue Exception => e
      msg = "Could not read config file #{config_file}: #{e.message}"
      raise LeasesGeneratorError, msg
    end

    # config ActiveResource params
    SchoolInfo.set_params(@config_params["site"], @config_params["user"], @config_params["pass"])
    Laptop.set_params(@config_params["site"], @config_params["user"], @config_params["pass"])

    # set other params
    @leases_dir = @config_params["leases_dir"] || "/var/lib/xo-activations"
    @last_run_file = @config_params["last_run_file"] || APP_ROOT.join("var", "last_run")
    @stale_lease_threshold = @config_params["stale_lease_threshold"] || 604800
    @bios_crypto_path = @config_params["bios_crypto_path"]
    @signing_key_path = @config_params["signing_key_path"]

    FileUtils.mkpath(File.join(@leases_dir, "by-school"))
    FileUtils.mkpath(File.join(@leases_dir, "by-laptop"))
  end

  def fetch_stolen_list()
    $LOG.info("Querying for stolen laptops")
    stolen_list = Laptop.stolen_list
    return if stolen_list.nil?

    csv_fd = Tempfile.new("stolen_csv", "/var/tmp")
    list_fd = Tempfile.new("stolen_list", "/var/tmp")
    stolen_list.each { |laptop|
      uuid = laptop["uuid"]
      serial_number = laptop["serial_number"]
      csv_fd.write(laptop["serial_number"] + "," + uuid + "\n")
      list_fd.write(laptop["serial_number"] + "\n")
    }

    csv_fd.close
    list_fd.close
    File.chmod(0644, csv_fd.path)
    File.chmod(0644, list_fd.path)

    outfile = File.join(@leases_dir, "stolen.csv")
    File.rename(csv_fd.path, outfile)

    outfile = File.join(@leases_dir, "stolen.list")
    File.rename(list_fd.path, outfile)
    $LOG.info("Wrote stolen laptop lists")
  end

  def get_all_hostnames
    $LOG.info("Querying for school hostnames")
    hostnames = SchoolInfo.list
    if hostnames.nil?
      $LOG.error("Could not list school hostnames.")
    else
      $LOG.info("Received #{hostnames.length} school hostnames.")
    end
    hostnames
  end

  def generate(hostnames = nil)
    Dir.chdir(@bios_crypto_path + "/build")

    hostnames = get_all_hostnames if hostnames.nil?
    return if hostnames.nil?

    hostnames.each { |hostname|
      $LOG.info("Querying school #{hostname}")
      info = SchoolInfo.lease_info(hostname)

      if info.nil?
        $LOG.error("Could not retrieve school info, skipping.")
        next
      end

      $LOG.info("Processing #{info["serials_uuids"].length} laptops for #{hostname}")
      md5_serials = calcMD5SUM(info["serials_uuids"])
      prev_checksum_file = getCheckSumPath(hostname)
      md5_previous = getMD5SUMFromFile(prev_checksum_file)

      if haveLeases?(hostname) && md5_serials == md5_previous && !leasesStale?(prev_checksum_file)
        $LOG.info("School is already up-to-date.")
        next
      end

      ret = generateLeases(hostname, info["serials_uuids"], info["expiry_date"])
      if !ret
        $LOG.error("Lease generation failure, skipping.")
        next
      end

      $LOG.info("Leases generated/refreshed.")
      saveMD5SUM(md5_serials, hostname)
    }
    $LOG.info("Complete")
  end

  private

  def calcMD5SUM(laptops)
    # Calculate a unique checksum of a serial/UUID hash
    lines = []
    laptops.each { |laptop|
      lines.push(laptop["serial_number"] + " " + laptop["uuid"])
    }

    Digest::MD5.hexdigest(lines.sort.join("\n"))
  end

  def generateLease(serial, uuid, expiry)
    cmd = "./make-lease.sh --signingkey \"#{@signing_key_path}\" \"#{serial}\" \"#{uuid}\" \"#{expiry}\""
    lease = nil
    IO.popen(cmd) { |proc|
      lease = proc.read
    }
    if $? == 0
      return lease
    else
      $LOG.error("make-lease failed with code #{$?}")
      return nil
    end
  end

  def generateLeases(school_name, laptops, expiry_date)
    $LOG.info("Generating leases with expiry #{expiry_date}")
    jsonfd = Tempfile.new(school_name, "/var/tmp")
    jsonfd.write("[1,{")

    # produce Canonical JSON output, which must be sorted by serial number
    laptops = laptops.sort_by { |laptop| laptop["serial_number"] }

    first = true
    laptops.each { |laptop|
      serial = laptop["serial_number"]
      lease = generateLease(serial, laptop["uuid"], expiry_date)
      if lease.nil?
        jsonfd.close
        jsonfd.unlink
        return false
      end

      fd = Tempfile.new(serial, "/var/tmp")
      fd.write(lease)
      fd.close
      output_path = getLaptopLeasePath(serial)
      File.rename(fd.path, output_path)
      File.chmod(0644, output_path)

      if !first
        jsonfd.write(",")
      else
        first = false
      end
      jsonfd.write("\"#{serial}\":\"#{lease}\"")
    }

    jsonfd.write("}]")
    jsonfd.close
    output_path = getSchoolLeasePath(school_name)
    File.rename(jsonfd.path, output_path)
    File.chmod(0644, output_path)
    return true
  end

  def leasesStale?(file2check)
    ret = true

    if File.exists?(file2check) 
      ret = false if (Time.now - File.mtime(file2check)) < @stale_lease_threshold
    end
    
    ret
  end

  def haveLeases?(school_name)
    return File.exists?(getSchoolLeasePath(school_name))
  end
  
  def saveMD5SUM(md5sum_str, school_name)
    output_file = getCheckSumPath(school_name)
    File.open(output_file, "w") do |fp|
      fp.puts md5sum_str.to_s
    end
    true
  end

  def getMD5SUMFromFile(file_path)
    md5sum_str = ""
    
    if File.exists?(file_path)
      File.open(file_path, "r") do |fp|
        md5sum_str = fp.gets.chomp
      end
    end

    md5sum_str
  end

  def getCheckSumPath(school_name)
    File.join(MD5SUMS_DIR, school_name + ".checksum")
  end

  def getSchoolLeasePath(school_name)
    File.join(@leases_dir, "by-school", school_name)
  end

  def getLaptopLeasePath(serial)
    dir = File.join(@leases_dir, "by-laptop", serial[-2,2])
    FileUtils.mkpath(dir)
    File.join(dir, serial)
  end

end

