require 'yaml'
require 'optparse'

class Yob::Configuration
  Error = Class.new(StandardError)

  def initialize(argv = [])
    command_line_options = {}
    configuration_path = ["/etc/yob.yml", File.dirname(__FILE__) << "/yob.yml"].detect {|file| File.exists?(file)}

    OptionParser.new(argv) do |opts|
      opts.banner = "Usage: yob [options] full|partial"

      opts.on("--debug", "Print debug output") do
        command_line_options["debug"] = true
      end

      opts.on("-c", "--config CONFIG_FILE", String, "Specify a path to the configuration file") do |file|
        configuration_path = file
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end.parse!

    raise Error, "could not locate a yob.yml file in any of the normal locations" unless configuration_path

    configuration = YAML.load(IO.read(configuration_path))["configuration"]
    @hash = configuration.merge(command_line_options)
  end

  def [](key)
    @hash[key.to_s]
  end

  def fetch(key, default)
    @hash[key.to_s] || default
  end

  def method_missing(key, *args)
    key = key.to_s
    raise Error, "Required configuration parameter '#{key}' not specified in configuration file" unless @hash.member?(key)
    @hash[key]
  end

  def database_handler_class
    case database_handler.downcase
    when "postgresql" then Yob::Database::Postgresql
    when "mysql"      then Yob::Database::Mysql
    else                   raise "Unrecognised database_handler"
    end
  end

  def store_handler_class
    case storage_handler.downcase
    when "aws"  then Yob::Store::AWS
    else             raise "Unrecognised storage_handler"
    end
  end

  def encryption_handler_class
    Yob::Encrypt::GnuPG
  end
end
