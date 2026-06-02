require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# The files
files = [
  'ios/Runner/MeshPacket.swift',
  'ios/Runner/Utils.swift',
  'ios/Runner/BlePeerRegistry.swift',
  'ios/Runner/DeduplicationCache.swift',
  'ios/Runner/RelayController.swift'
]

group = project.main_group.find_subpath(File.join('Runner'), true)

files.each do |file|
  basename = File.basename(file)
  file_ref = group.files.find { |f| f.path == basename }
  
  if file_ref
    # Check if it's already in the source build phase
    unless target.source_build_phase.files.map(&:file_ref).include?(file_ref)
      target.source_build_phase.add_file_reference(file_ref)
      puts "Added #{basename} to compile sources."
    end
  end
end

project.save
