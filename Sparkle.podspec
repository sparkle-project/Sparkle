Pod::Spec.new do |s|
  s.name        = "Sparkle"
  s.version     = "1.11.0"
  s.summary     = "A software update framework for OS X"
  s.description = "Sparkle is an easy-to-use software update framework for Cocoa developers."
  s.homepage    = "http://sparkle-project.org"
  s.license     = {
    :type => 'MIT',
    :file => 'LICENSE'
  }
  s.authors     = {
    'Andy Matuschak' => 'andy@andymatuschak.org',
    'Kornel Lesiński' => 'pornel@pornel.net',
    'C.W. Betts' => 'computers57@hotmail.com',
    'Jake Petroules' => 'jake.petroules@petroules.com',
  }

  s.platform = :osx, '10.7'
  s.source   = { :http => "https://github.com/sparkle-project/Sparkle/releases/download/#{s.version}/Sparkle-#{s.version}.tar.bz2" }

  s.public_header_files = 'Sparkle.framework/Versions/A/Headers/*.h'
  s.vendored_framework  = 'Sparkle.framework'
  s.resources           = 'Sparkle.framework'
  s.xcconfig            = { 'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/Sparkle"' }
  s.requires_arc        = true
end
