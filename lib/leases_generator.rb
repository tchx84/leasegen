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

  LEASES_DIR = "/usr/share/puppetcontent/leases"
  LAST_RUN_FILE = APP_ROOT.join("var", "last_run")
  SECS_IN_WEEK = (3600*24*7)
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
    @leases_dir = @config_params.get_value("leases_dir") || LEASES_DIR
    @last_run_file = @config_params.get_value("last_run_file") || LAST_RUN_FILE
  end

  def generate(hostnames = [])
    begin 
      schools_info = Place.getSchoolsInfo(hostnames)
      raise "no school info received " if schools_info.length ==  0

      schools_info.each { |s|
        input_sn_uuids_fp = genInputFile(s["serials_uuids"])
        input_sn_uuids_file = input_sn_uuids_fp.path
        md5_tmpfile = calcMD5SUM(input_sn_uuids_file)
        prev_checksum_file = getCheckSumPath(s["school_name"])
        md5_previous = getMD5SUMFromFile(prev_checksum_file)

        if md5_tmpfile != md5_previous || olderThan?(prev_checksum_file)
          doGenerateLeases(s, input_sn_uuids_file, md5_tmpfile)
        end
      }
    rescue
      $LOG.error($!.to_s)
    end
  end

  # Sort the lines to assure you get the same MD5
  def calcMD5SUM(file_path, sort_lines = true)
    md5sum_str = ""
    lines = File.open(file_path, "r").readlines
    lines.sort! if sort_lines
    Digest::MD5.hexdigest(lines.join(""))
  end

  def run_cmd(cmd, debug = false)
    system(cmd) 
  end

  private 
  def doGenerateLeases(s, input_sn_uuids_file, new_md5sum)
    begin 
      expiry_date = s["expiry_date"]
      output_leases_file = s["school_name"]

      # generate leases for this school
      cmd = "/home/oats/leasegen/makeleases #{expiry_date} #{input_sn_uuids_file} #{@leases_dir}/#{output_leases_file}"
      
      if run_cmd(cmd)
        saveMD5SUM(new_md5sum, s["school_name"])
      end

    rescue 
      $LOG.error($!.to_s)
    end
  end

  ###
  # genInputFile: generates file with SNs and UUIDs from which leases are generated
  # @serials_uuids : [ { :serial_number, :uuid } , ... ]
  #
  # returns: path to generated file with serials and uuids:
  # SN UUID
  # SN UUID
  # ....
  #
  def genInputFile(serials_uuids)
    fp = Tempfile.new("serials_uuids")
    serials_uuids.each { |line|
      fp.puts "#{line["serial_number"]} #{line["uuid"]}"
    }

    fp.close()
    fp
  end

  def olderThan?(file2check, num_of_seconds = SECS_IN_WEEK)
    ret = true

    if File.exists?(file2check) 
      ret = false if (Time.now - File.mtime(file2check)) < num_of_seconds
    end
    
    ret
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

end

