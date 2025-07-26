Pod::Spec.new do |s|
  s.name        = "Sparkle"
  s.version     = "2.7.1"
  s.summary     = "A software update framework for macOS"
  s.description = "Sparkle is an easy-to-use software update framework for macOS."
  s.homepage    = "https://sparkle-project.org"
  s.documentation_url = "https://sparkle-project.org/documentation/"
  s.screenshot  = "https://sparkle-project.org/images/screenshot-noshadow@2x.png"
  s.license     = {
    :type => 'MIT',
    :file => 'LICENSE'
  }
  s.authors     = {
    'Zorg' => 'zorgiepoo@gmail.com',
    'Kornel Lesiński' => 'pornel@pornel.net',
    'Jake Petroules' => 'jake.petroules@petroules.com',
    'C.W. Betts' => 'computers57@hotmail.com',
    'Andy Matuschak' => 'andy@andymatuschak.org',
  }

  s.platform = :osx, '10.13'
  s.source   = { :http => "https://github.com/sparkle-project/Sparkle/releases/download/#{s.version}/Sparkle-#{s.version}.tar.xz" }
  s.source_files = 'Sparkle.framework/Versions/B/Headers/*.h'

  s.preserve_paths = ['bin/*', 'Symbols']
  s.public_header_files = 'Sparkle.framework/Versions/B/Headers/*.h'
  s.vendored_frameworks  = 'Sparkle.framework'
  s.xcconfig            = {
    'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/Sparkle"',
    'LD_RUNPATH_SEARCH_PATHS' => '@loader_path/../Frameworks'
  }
  s.requires_arc        = true
end
