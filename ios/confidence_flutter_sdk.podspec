#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint confidence_flutter_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'confidence_flutter_sdk'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for the Confidence SDK.'
  s.description      = 'Flutter plugin for the Confidence SDK.'
  s.homepage         = 'https://confidence.spotify.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Confidence' => 'confidence@spotify.com' }
  s.source           = { :path => '.' }
  s.source_files = 'confidence_flutter_sdk/Sources/confidence_flutter_sdk/**/*.swift', 'Classes/Confidence/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
