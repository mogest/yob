spec = Gem::Specification.new do |s|
  s.name = 'yob'
  s.version = '1.0.0'
  s.summary = "YouDo Online Backup"
  s.description = "YouDo Online Backup"
  s.files = %w(README.rdoc lib/yob.rb bin/yob) + Dir['lib/**/*.rb']
  s.executables << "yob"
  s.has_rdoc = false
  s.author = "Roger Nesbitt"
  s.email = "roger@youdo.co.nz"

  s.add_runtime_dependency "sqlite3"
  s.add_runtime_dependency "minitar"
  s.add_runtime_dependency "aws-sdk"
  s.add_runtime_dependency "gpgme"
end
