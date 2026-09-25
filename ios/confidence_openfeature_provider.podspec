Pod::Spec.new do |s|
  s.name = 'confidence_openfeature_provider'
  s.version = '0.0.1'
  s.summary = 'Legacy Confidence calendar conversion for the Dart provider.'
  s.homepage = 'https://github.com/spotify/confidence-sdk-flutter'
  s.license = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author = 'Spotify AB'
  s.source = { :git => 'https://github.com/spotify/confidence-sdk-flutter.git' }
  s.source_files = 'confidence_openfeature_provider/Sources/confidence_openfeature_provider/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
