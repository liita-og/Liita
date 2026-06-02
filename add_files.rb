require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.find_subpath(File.join('Runner'), true)

# The new files
files = [
  'ios/Runner/MeshPacket.swift',
  'ios/Runner/Utils.swift',
  'ios/Runner/BlePeerRegistry.swift',
  'ios/Runner/DeduplicationCache.swift',
  'ios/Runner/RelayController.swift'
]

files.each do |file|
  # Skip if already in project
  next if group.files.map(&:path).include?(File.basename(file))
  
  file_ref = group.new_reference(File.basename(file))
  target.add_file_references([file_ref])
end

project.save
