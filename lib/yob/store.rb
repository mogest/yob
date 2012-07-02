module Yob::Store
  class AWS
    BLOCK_SIZE = 1048576

    attr_reader :pid

    def initialize(configuration)
      require 'aws-sdk'

      @configuration = configuration

      ::AWS.config(:access_key_id     => configuration.aws_access_key_id,
                   :secret_access_key => configuration.aws_secret_access_key)
    end

    def storage_input_pipe(filename)
      rd, wr = IO.pipe
      @pid = fork do
        $0 = "yob: AWS S3 storage"
        wr.close
        #IO.select([rd]) # wait until there's some input before starting up the storage to prevent timeouts
        store(filename, rd)
        rd.close
      end
      rd.close
      wr
    end

    def store(filename, file_handle)
      puts "Store::AWS: uploading #{filename}"
      object = s3_bucket.objects["#{@configuration["aws_filename_prefix"]}#{filename}"]

      exception = nil
      object.multipart_upload do |upload|
        begin
          print "Store::AWS: multipart upload started\n" if @configuration["debug"]
          bytes = 0
          while data = file_handle.read(BLOCK_SIZE)
            break if data.length == 0
            bytes += data.length
            upload.add_part(data)
            print "Store::AWS: #{bytes} bytes sent\n" if @configuration["debug"]
          end
        rescue Exception => e
          # This is awful.  #multipart_upload rescues and throws away exceptions.
          # We have to store it so we know that it ever happened.
          exception = e
          raise
        end
      end

      raise exception if exception

      if grant_to = @configuration["aws_grant_access_to"]
        puts "Store::AWS: granting access to #{filename}"
        object.acl = access_control_list(grant_to)
      end

      puts "Store::AWS: uploaded"
    end

    protected
    def s3_bucket
      ::AWS::S3.new.buckets[@configuration.aws_bucket]
    end

    def access_control_list(email)
      acl = ::AWS::S3::AccessControlList.new
      acl.grant(:full_control).to(:amazon_customer_email => email)
      acl
    end
  end
end
