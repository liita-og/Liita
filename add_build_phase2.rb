require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.find_subpath(File.join('Runner'), true)

files = [
  'ios/Runner/MeshManager.swift',
  'ios/Runner/MeshPlugin.swift'
]

files.each do |file|
  basename = File.basename(file)
  file_ref = group.files.find { |f| f.path == basename }
  
  if file_ref
    unless target.source_build_phase.files.map(&:file_ref).include?(file_ref)
      target.source_build_phase.add_file_reference(file_ref)
      puts "Added #{basename} to compile sources."
    end
  else
    puts "File reference for #{basename} not found!"
    # Add it to group and compile sources
    file_ref = group.new_reference(basename)
    target.add_file_references([file_ref])
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{basename} completely."
  end
end

project.save
