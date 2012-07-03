#!/usr/bin/env ruby

module Yob::Database
  class Base
    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
    end

    protected
    def random_filename_string
      (0..15).inject(".") {|s, i| s << (97 + rand(26)).chr} if configuration["randomise_filename"]
    end
  end

  class Mysql < Base
    def initialize(configuration)
      super

      unless File.directory?(configuration.mysql_log_directory)
        raise Yob::Configuration::Error, "mysql_log_directory does not exist"
      end

      unless File.exists?(configuration.mysqldump_executable)
        raise Yob::Configuration::Error, "mysqldump_executable does not exist"
      end
    end

    def full_backup
      writer = yield Time.now.strftime("%Y%m%d-%H%M%S#{random_filename_string}.sql.gpg"), nil
      begin
        puts "[Database::Mysql] dumping all databases to SQL..."
        system("#{configuration.mysqldump_executable} --all-databases --default-character-set=utf8 --skip-opt --create-options --add-drop-database --extended-insert --flush-logs --master-data --quick --single-transaction >&#{writer.fileno}")
        puts "[Database::Mysql] dump completed"
      ensure
        writer.close
      end
    end

    def partial_backup
      require 'sqlite3'

      @db = SQLite3::Database.new(configuration.fetch("file_database", "#{File.dirname(__FILE__)}/yob.db"))
      @db.execute("CREATE TABLE IF NOT EXISTS files (id INTEGER PRIMARY KEY AUTOINCREMENT, filename varchar(255) unique not null, file_size integer not null, file_time datetime not null)")

      files = Dir["#{configuration.mysql_log_directory}/mysql-bin.*"]
      files.each do |filename|
        next if filename[-5..-1] == 'index'

        stats = File.stat(filename)
        file_time = stats.mtime.strftime("%Y-%m-%d %H:%M:%S")

        row = @db.get_first_row("SELECT id, file_size, file_time FROM files WHERE filename = ?", filename)
        if row && row[1].to_i == stats.size && row[2] == file_time
          puts "[Database::Mysql] skipping #{filename}" if @configuration["debug"]
        else
          File.open(filename, "r") do |logfile|
            yield "#{File.basename(filename)}#{random_filename_string}.gpg", logfile
          end

          if row
            @db.execute("UPDATE files SET file_size = ?, file_time = ? WHERE id = ?", stats.size, file_time, row[0])
          else
            stmt = @db.prepare("INSERT INTO files (filename, file_size, file_time) VALUES (?, ?, ?)")
            stmt.execute(filename, stats.size, file_time)
          end
        end
      end
    end
  end

  class Postgresql < Base
    def initialize(configuration)
      super
      require 'archive/tar/minitar'
    end

    def full_backup
      require 'pg'

      connect_and_execute "SELECT pg_start_backup('yob')"

      begin
        writer = yield Time.now.strftime("%Y%m%d-%H%M%S#{random_filename_string}.tar.gpg"), nil
        tar = Archive::Tar::Minitar::Output.new(writer)
        begin
          Find.find(configuration.postgresql_data_directory) do |entry|
            Archive::Tar::Minitar.pack_file(entry, tar) unless entry.include?("/pg_xlog/")
          end
        ensure
          tar.close
        end
        writer.close
      ensure
        connect_and_execute "SELECT pg_stop_backup()"
      end
    end

    def partial_backup
      raise "yob partial must be called with two more arguments - the full path and the destination filename - for a postgresql partial backup" unless ARGV.length == 3
      full_path = ARGV[1]
      destination_filename = ARGV[2]

      File.open(full_path, "r") do |file|
        yield "#{destination_filename}#{random_filename_string}", file
      end
    end

    protected
    def connect_and_execute(sql)
      hostname = @configuration.fetch("postgresql_hostname", "localhost")
      port = @configuration.fetch("postgresql_port", 5432)

      connection = PGconn.connect(
        hostname, # nil if UNIX socket
        port,     # nil if UNIX socket
        '',       # options
        '',       # unused by library
        @configuration.fetch("postgresql_default_database", "postgres"),
        @configuration["postgresql_username"],
        @configuration["postgresql_password"])

      connection.exec(sql)
      connection.close
    end
  end
end
