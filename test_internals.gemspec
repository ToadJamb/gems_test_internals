Gem::Specification.new do |s|
  s.name    = 'test_internals'
  s.version = '2.0.2'

  s.summary     = 'Allows tests to check the stack trace, ' +
    'parameters, private methods, and class variables.'

  s.description = %Q{
TestInternals patches Test::Unit::TestCase to allow
testing of private methods, as well as variables. The stack trace
is also available, including the ability to check that specific
parameters were sent to a method. This results in cotton candy goodness for all.
}.strip

  s.author   = 'Travis Herrick'
  s.email    = 'tthetoad@gmail.com'
  s.homepage = 'http://www.bitbucket.org/ToadJamb/gems_test_internals'

  s.license = 'LGPLv3'

  s.extra_rdoc_files << 'README'

  s.require_paths = ['lib']
  s.files = Dir['lib/**/*.rb', 'license/**/*', '*'] - Dir['Gemfile.lock']
  s.test_files = Dir['test/**/*.rb']

  s.add_dependency 'app_mode', '~> 1.0.3'

  s.add_development_dependency 'rake_tasks', '~> 2.0.4'

  s.has_rdoc = true
end
