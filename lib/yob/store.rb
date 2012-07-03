module Yob::Store
  class AWS
    BLOCK_SIZE = 1048576 * 5 # must be at least 5 MB

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
        store(filename, rd)
        rd.close
      end
      rd.close
      wr
    end

    def store(filename, file_handle)
      puts "[Store::AWS] uploading #{filename}"
      object = s3_bucket.objects["#{@configuration["aws_filename_prefix"]}#{filename}"]

      data = file_handle.read(BLOCK_SIZE)
      if data.nil? || data.length == 0
        puts "[Store::AWS] no file data received, upload aborted"
        return
      end

      # If the entire file is less than BLOCK_SIZE, send it in one hit.
      # Otherwise use AWS's multipart upload feature.  Note that each part must be at least 5MB.
      if data.length < BLOCK_SIZE
        object.write(data)
      else
        upload = object.multipart_uploads.create
        begin
          puts "[Store::AWS] multipart upload started" if @configuration["debug"]
          bytes = 0
          while data && data.length > 0
            upload.add_part(data)
            bytes += data.length
            puts "[Store::AWS] #{bytes} bytes sent" if @configuration["debug"]
            data = file_handle.read(BLOCK_SIZE)
          end
          upload.close
        rescue
          upload.abort
          raise
        end
      end

      if grant_to = @configuration["aws_grant_access_to"]
        puts "[Store::AWS] granting access to #{filename}"
        object.acl = access_control_list(grant_to)
      end

      puts "[Store::AWS] uploaded"
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
