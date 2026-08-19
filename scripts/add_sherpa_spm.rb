#!/usr/bin/env ruby
# Yerel sherpa-onnx SPM paketini (vendor/SherpaOnnx) + dfki TTS model klasörünü hedef target'lara ekler.
# Idempotent. Mac (Hercules) önce; iOS için: TARGETS=Hercules,HerculesMobile ruby scripts/add_sherpa_spm.rb
require 'xcodeproj'

PROJ       = File.expand_path(File.join(__dir__, '..', 'Hercules.xcodeproj'))
LOCAL_PATH = 'vendor/SherpaOnnx'
PRODUCT    = 'SherpaOnnx'
MODEL_PATH = 'Hercules/Resources/tts/vits-piper-tr_TR-dfki-medium'
TARGETS    = (ENV['TARGETS'] || 'Hercules').split(',')

project = Xcodeproj::Project.open(PROJ)

# 1) Yerel paket referansı (varsa yeniden kullan)
pkg = project.root_object.package_references.find { |r|
  r.respond_to?(:relative_path) && r.relative_path == LOCAL_PATH
}
unless pkg
  pkg = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  pkg.relative_path = LOCAL_PATH
  project.root_object.package_references << pkg
  puts "+ yerel paket referansı eklendi: #{LOCAL_PATH}"
else
  puts "= yerel paket referansı zaten var"
end

TARGETS.each do |tname|
  target = project.targets.find { |t| t.name == tname }
  raise "target bulunamadı: #{tname}" unless target

  # 2) Ürün bağımlılığı + Frameworks build phase
  dep = target.package_product_dependencies.find { |d| d.product_name == PRODUCT }
  unless dep
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.product_name = PRODUCT
    dep.package = pkg
    target.package_product_dependencies << dep
    bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    bf.product_ref = dep
    target.frameworks_build_phase.files << bf
    puts "+ #{PRODUCT} -> #{tname} (link)"
  else
    puts "= #{PRODUCT} zaten #{tname}'e bağlı"
  end

  # 3) Model klasör referansı (blue folder) -> Resources
  fname = File.basename(MODEL_PATH)
  exists = target.resources_build_phase.files.any? { |f|
    f.file_ref && f.file_ref.respond_to?(:path) && f.file_ref.path.to_s.include?(fname)
  }
  unless exists
    ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
    ref.source_tree = 'SOURCE_ROOT'
    ref.path = MODEL_PATH
    ref.name = fname
    ref.last_known_file_type = 'folder'   # blue folder reference -> espeak-ng-data yapısı korunur
    ref.include_in_index = '0'
    project.main_group << ref
    target.resources_build_phase.add_file_reference(ref)
    puts "+ model klasörü -> #{tname} (resource)"
  else
    puts "= model klasörü zaten #{tname} resources'ta"
  end
end

project.save
puts "kaydedildi: #{PROJ}"
