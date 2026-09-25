#!/usr/bin/env ruby
# Édite DynamicNotch.xcodeproj sans passer par Xcode.
#   ruby Tools/xcproj.rb add <Cible> <fichier.swift>...
#   ruby Tools/xcproj.rb remove <fichier.swift>...
#   ruby Tools/xcproj.rb setup-tests
#   ruby Tools/xcproj.rb set-deployment <Cible> <version>
require 'xcodeproj'

# La locale du shell (C/POSIX) force Ruby en US-ASCII, ce qui fait planter
# xcodeproj sur les noms d'auteur non-ASCII du pbxproj (ex. « 秋星桥 »).
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

REPO = File.expand_path('..', __dir__)
Dir.chdir(REPO)
PROJECT_PATH = File.join(REPO, 'DynamicNotch.xcodeproj')
SCHEME_PATH = File.join(PROJECT_PATH, 'xcshareddata/xcschemes/DynamicNotch.xcscheme')

def target_named(project, name)
  project.targets.find { |t| t.name == name } || abort("cible #{name} introuvable")
end

# Groupe correspondant au dossier du fichier, créé au besoin (un groupe par dossier).
def group_for(project, file)
  group = project.main_group
  File.dirname(file).split('/').each do |component|
    next if component == '.'
    child = group.children.find { |c| c.isa == 'PBXGroup' && (c.path == component || c.name == component) }
    group = child || group.new_group(component, component)
  end
  group
end

def add_files(project, target_name, files)
  target = target_named(project, target_name)
  files.each do |file|
    abort("#{file} n'existe pas") unless File.exist?(file)
    group = group_for(project, file)
    name = File.basename(file)
    ref = group.files.find { |r| r.path == name } || group.new_reference(name)
    next if target.source_build_phase.files_references.include?(ref)
    target.add_file_references([ref])
    puts "ajouté #{file} → #{target_name}"
  end
end

def remove_files(project, files)
  files.each do |file|
    absolute = File.expand_path(file, REPO)
    ref = project.files.find { |r| r.real_path.to_s == absolute } || abort("#{file} absent du projet")
    ref.build_files.each(&:remove_from_project)
    ref.remove_from_project
    puts "retiré #{file}"
  end
end

def setup_tests(project)
  if project.targets.any? { |t| t.name == 'DynamicNotchTests' }
    puts 'cible DynamicNotchTests déjà présente'
    return
  end
  app = target_named(project, 'DynamicNotch')
  tests = project.new_target(:unit_test_bundle, 'DynamicNotchTests', :osx, '14.0', nil, :swift)
  tests.add_dependency(app)
  tests.build_configurations.each do |config|
    s = config.build_settings
    s['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/DynamicNotch.app/Contents/MacOS/DynamicNotch'
    s['BUNDLE_LOADER'] = '$(TEST_HOST)'
    # xcodeproj 1.24 ne fournit pas de PRODUCT_NAME par défaut pour une
    # cible :unit_test_bundle (contrairement à :framework) ; sans ça le
    # module a un nom vide et la compilation échoue.
    s['PRODUCT_NAME'] = '$(TARGET_NAME)'
    s['PRODUCT_BUNDLE_IDENTIFIER'] = 'wiki.qaq.DynamicNotchTests'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['SWIFT_VERSION'] = '5.0'
    s['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  end
  add_files(project, 'DynamicNotchTests', Dir.glob('DynamicNotchTests/*.swift').sort)
  scheme = Xcodeproj::XCScheme.new(SCHEME_PATH)
  scheme.add_test_target(tests)
  scheme.save!
  puts 'cible DynamicNotchTests créée et ajoutée au schéma'
end

def set_deployment(project, target_name, version)
  target_named(project, target_name).build_configurations.each do |config|
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = version
  end
  puts "#{target_name} → macOS #{version}"
end

project = Xcodeproj::Project.open(PROJECT_PATH)
command, *args = ARGV
case command
when 'add' then add_files(project, args.shift, args)
when 'remove' then remove_files(project, args)
when 'setup-tests' then setup_tests(project)
when 'set-deployment' then set_deployment(project, args[0], args[1])
else abort('usage : add <Cible> <fichiers…> | remove <fichiers…> | setup-tests | set-deployment <Cible> <version>')
end
project.save
