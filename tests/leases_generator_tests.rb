#!/usr/bin/ruby

# add lib to load path
$: << File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "leases_generator"


class LeasesGeneratorTests < Test::Unit::TestCase
  
  def test_md5sum
    lg = LeasesGenerator.new
    md5sum_lg = lg.calcMD5SUM("/etc/passwd", false)
    md5sum_system = IO.popen("md5sum /etc/passwd").readlines.join("").split(" ")[0]

    assert_equal md5sum_system, md5sum_lg
  end

  def test_run_cmd_true
    lg = LeasesGenerator.new
    assert_equal lg.run_cmd("/bin/ls > /dev/null"), true
  end

  def test_run_cmd_false
    lg = LeasesGenerator.new
    assert_equal lg.run_cmd("/bin/tincho > /dev/null 2>&1"), false
  end
  


end

