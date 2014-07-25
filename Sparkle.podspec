Pod::Spec.new do |s|
  s.name        = "Sparkle"
  s.version     = "1.7.1"
  s.summary     = "A software update framework for OS X"
  s.description = "Sparkle is an easy-to-use software update framework for Cocoa developers."
  s.homepage    = "https://github.com/sparkle-project/Sparkle"
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

  s.platform = :osx
  s.source   = { :http => "https://github.com/sparkle-project/Sparkle/releases/download/#{s.version}/Sparkle-#{s.version}.zip" }

  s.public_header_files = 'Sparkle.framework/Headers/*.h'
  s.vendored_framework  = 'Sparkle.framework'
  s.resources           = 'Sparkle.framework'
  s.xcconfig            = { 'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/Sparkle"' }
  s.requires_arc        = false
end
