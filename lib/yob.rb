require 'rubygems'

class Yob
  def initialize(configuration)
    @configuration = configuration
    @store = @configuration.store_handler_class.new(@configuration)
    @database = @configuration.database_handler_class.new(@configuration)
    @encryption = @configuration.encryption_handler_class.new(@configuration)
  end

  def backup(type)
    @database.send(type) do |filename, rd|
      storage_pipe = @store.storage_input_pipe(filename)
      if rd
        @encryption.encrypt(rd, storage_pipe)
        storage_pipe.close
        nil
      else
        @encryption.encryption_input_pipe(storage_pipe)
      end
    end
    Process.waitall
  end
end

require 'yob/configuration'
require 'yob/database'
require 'yob/encrypt'
require 'yob/store'
