# Gets the list of schools with it's SNs (and UUIDs) and generates the leases
#
# author: Raul Gutierrez S. (rgs@paraguayeduca.org)

require 'digest/md5'
require 'fileutils'
require 'tempfile'
require 'parseconfig'
require 'place'

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
    Place.set_params(@config_params.get_value("site"), @config_params.get_value("user"), @config_params.get_value("pass"))

    # set other params
    @leases_dir = @config_params.get_value("leases_dir") || "/var/lib/xo-activations"
    @last_run_file = @config_params.get_value("last_run_file") || APP_ROOT.join("var", "last_run")
    @stale_lease_threshold = @config_params.get_value("stale_lease_threshold") || 604800
    @bios_crypto_path = @config_params.get_value("bios_crypto_path")
    @signing_key_path = @config_params.get_value("signing_key_path")

    FileUtils.mkpath(File.join(@leases_dir, "by-school"))
    FileUtils.mkpath(File.join(@leases_dir, "by-laptop"))
  end

  def generate(hostnames = [])
    Dir.chdir(@bios_crypto_path + "/build") do
      $LOG.info("Querying for school info")
      schools_info = Place.getSchoolsInfo(hostnames)
      $LOG.info("Received data for #{schools_info.length} schools")

      schools_info.each { |s|
        $LOG.info("Processing #{s["serials_uuids"].length} laptops for #{s["school_name"]}")
        md5_serials = calcMD5SUM(s["serials_uuids"])
        prev_checksum_file = getCheckSumPath(s["school_name"])
        md5_previous = getMD5SUMFromFile(prev_checksum_file)

        if md5_serials != md5_previous || leasesStale?(prev_checksum_file) || !haveLeases?(s["school_name"])
          ret = generateLeases(s["school_name"], s["serials_uuids"], s["expiry_date"])
          if ret
            saveMD5SUM(md5_serials, s["school_name"])
          else
            $LOG.error("Lease generation failure, aborting")
          end
        else
          $LOG.info("School is already up-to-date.")
        end
      }
      $LOG.info("Complete")
    end
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
    jsonfd = Tempfile.new(school_name)
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

      fd = Tempfile.new(serial)
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

