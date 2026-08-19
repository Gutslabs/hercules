#!/usr/bin/env ruby
# add_sherpa_spm.rb'nin TAM TERSİ: yerel SherpaOnnx SPM paketini + dfki TTS model
# klasörünü + (artık gereksiz) mikrofon iznini projeden söker. Idempotent.
# Sesli koç kaldırıldığı için app'i hafifletir (79M model + 348M framework gömülmez).
require 'xcodeproj'

# Ruby 2.6 default'u US-ASCII → pbxproj'daki Türkçe metin (mikrofon izni) okunamıyor. UTF-8'e zorla.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

PROJ       = File.expand_path(File.join(__dir__, '..', 'Hercules.xcodeproj'))
LOCAL_PATH = 'vendor/SherpaOnnx'
PRODUCT    = 'SherpaOnnx'
MODEL_NAME = 'vits-piper'

project = Xcodeproj::Project.open(PROJ)
to_remove = []

project.targets.each do |target|
  sherpa_deps = target.package_product_dependencies.select { |d| d.product_name == PRODUCT }

  # Frameworks build phase: SherpaOnnx link build-file'ları (ref'lerden ÖNCE sil)
  target.frameworks_build_phase.files.each do |bf|
    to_remove << bf if bf.product_ref && sherpa_deps.include?(bf.product_ref)
  end
  # Resources build phase: TTS modeli build-file'ları
  target.resources_build_phase.files.each do |bf|
    ref = bf.file_ref
    to_remove << bf if ref && ref.respond_to?(:path) && ref.path.to_s.include?(MODEL_NAME)
  end
  # Ürün bağımlılıkları (build-file'lardan sonra)
  sherpa_deps.each { |d| to_remove << d }
end

# TTS model file reference'ı (blue folder)
project.files.each do |ref|
  to_remove << ref if ref.respond_to?(:path) && ref.path.to_s.include?(MODEL_NAME)
end
# Yerel paket referansı
project.root_object.package_references.each do |r|
  to_remove << r if r.respond_to?(:relative_path) && r.relative_path == LOCAL_PATH
end

# remove_from_project referansları da temizler (build phase/group array'lerinden düşürür);
# build-file'lar listede ref'lerden ÖNCE olduğu için dangling kalmaz.
to_remove.uniq.each(&:remove_from_project)
puts "- #{to_remove.uniq.size} obje silindi (link/resource build-file, ürün bağımlılığı, model ref, paket ref)"

# Mikrofon izni — tüm target build config'lerinden
mic = 0
project.targets.each do |t|
  t.build_configurations.each do |c|
    mic += 1 if c.build_settings.delete('INFOPLIST_KEY_NSMicrophoneUsageDescription')
  end
end
puts "- mikrofon izni #{mic} config'ten silindi"

project.save
puts "kaydedildi: #{PROJ}"
