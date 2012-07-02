module Yob::Encrypt
  class GnuPG
    attr_reader :pid

    def initialize(configuration)
      require 'gpgme'
      @keys = configuration.encryption_key_names
    end

    def encryption_input_pipe(output_pipe)
      rd, wr = IO.pipe
      @pid = fork do
        $0 = "yob: GnuPG encryption"
        wr.close
        encrypt(rd, output_pipe)
      end
      rd.close
      wr
    end

    def encrypt(rd, wr)
      puts "Encrypt::GnuPG: encrypting input"

      plain_data = GPGME::Data.new(rd)
      cipher_data = GPGME::Data.new(wr)
      keys = GPGME::Key.find(:public, @keys)

      GPGME::Ctx.new do |ctx|
        ctx.encrypt(keys, plain_data, cipher_data, GPGME::ENCRYPT_ALWAYS_TRUST)
      end

      puts "Encrypt::GnuPG: encrypting complete"
    end
  end
end
