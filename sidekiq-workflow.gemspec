Gem::Specification.new do |spec|
  spec.name        = 'sidekiq-workflow'
  spec.version     = '0.0.0'
  spec.summary     = 'Parallel workflow engine based on Sidekiq & Redis'
  spec.description = 'Parallel workflow engine based on Sidekiq & Redis'
  spec.authors     = ['aeris']
  spec.email       = ['aeris@cozycloud.cc']
  spec.files       = %w(README.md LICENSE) + Dir.glob('lib/**/*', base: __dir__)
  spec.executables = Dir.glob('bin/**/*', base: File.join(__dir__, spec.bindir))
  spec.test_files  = Dir.glob('spec/**/*', base: __dir__)
  spec.homepage    = 'https://rubygems.org/gems/sidekiq-workflow'
  spec.license     = 'AGPL-3.0+'

  spec.add_dependency 'sidekiq', '~> 6.2', '>= 6.2.1'
  spec.add_dependency 'redis', '~> 4.3', '>= 4.3.1'
  spec.add_dependency 'redlock', '~> 1.2', '>= 1.2.1'

  spec.add_development_dependency 'rspec', '~> 3.10', '>= 3.10.0'
end
