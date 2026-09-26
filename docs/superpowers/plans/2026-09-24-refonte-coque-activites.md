# Refonte de la coque et moteur d'activités — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** rendre l'encoche de DynamicNotch nette, calée au pixel sur l'encoche physique, animée par des ressorts cohérents, et vivante grâce à un moteur d'activités (charge, batterie, Pomodoro, chrono, fichiers, AirDrop, musique).

**Architecture :** une géométrie pure (`NotchGeometry`) calcule tout au pixel près. Une forme unique animable (`NotchShellShape`) est dessinée dans une fenêtre de taille fixe. Une machine d'états (`NotchPresentation`) portée par `NotchViewModel` choisit taille et ressort. `ActivityCenter` arbitre les activités publiées par des sources système (IOKit, modèles de widgets) via `ActivityWiring`.

**Tech Stack :** Swift 5 (mode langage 5), SwiftUI + AppKit, macOS 14+, IOKit.ps, XCTest, gem Ruby `xcodeproj` 1.24 pour éditer le projet.

**Spec :** `docs/superpowers/specs/2026-09-24-refonte-coque-activites-design.md` (lire aussi la section « Amendements » en fin de fichier).

## Global Constraints

- Branche : `refonte/coque-activites`. Un commit par tâche au minimum, message en français, préfixe conventionnel (`feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`), terminé par la ligne `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Cible de déploiement : macOS 14.0 pour la cible app et la cible de tests.
- Le projet Xcode n'utilise pas de dossiers synchronisés : **tout fichier Swift créé ou supprimé doit passer par `ruby Tools/xcproj.rb`** (créé en tâche 0), sinon il n'est pas compilé.
- Tests : `Tools/test.sh [NomDeClasseDeTest]`. Build Release : `Tools/build.sh`. Ne jamais lancer `xcodebuild` sans `CODE_SIGNING_ALLOWED=NO` (pas d'équipe de signature sur cette machine).
- Code : style du dépôt (`AGENTS.md`) : 4 espaces, `guard` et retours anticipés, commentaires en français comme le code récent.
- Typographie : SF Pro standard (jamais `design: .rounded`), rien sous 11 pt dans le panneau, ailes en 13 pt semi-gras à chiffres fixes.
- Aucun `scaleEffect` sur une vue qui contient du texte ; aucune transition `.scale` sur du contenu ; pas de glow.
- Remplissage de la coque : `Color.black` opaque.
- Ressorts de la coque (exclusivement) : `expand` = `.spring(response: 0.42, dampingFraction: 0.78)`, `collapse` = `.spring(response: 0.32, dampingFraction: 0.95)`, `micro` = `.spring(response: 0.25, dampingFraction: 0.8)`.
- Durées des activités ponctuelles : charge 2,2 s ; débranchement 1,5 s ; batterie faible 3 s ; phase Pomodoro 2,5 s ; fichiers 1,2 s ; AirDrop 1,2 s ; musique 2 s. Abandon d'une ponctuelle en file depuis plus de 5 s.
- Priorités des persistantes : Pomodoro 40 > chrono 30 > musique 20 > calendrier 15 > charge 10.
- Écran de référence (tests) : frame 1512 × 982 pt, échelle 2, `safeAreaTop` 32, aux gauche largeur 663, aux droite largeur 664 → encoche x = 663, largeur 185, hauteur 32.

## Carte des fichiers

| Fichier | Rôle |
|---|---|
| `Tools/xcproj.rb` (créé) | Ajoute ou retire des fichiers des cibles, crée la cible de tests, règle la cible de déploiement |
| `Tools/test.sh`, `Tools/build.sh` (créés) | Lancer les tests, construire la Release |
| `DynamicNotch/DataMigration.swift` (créé) | Migration `~/Documents/DynamicNotch` → Application Support |
| `DynamicNotch/Geometry/NotchGeometry.swift` (créé) | `pixelAligned`, `ScreenDescriptor`, `NotchGeometry` |
| `DynamicNotch/Shell/NotchShellShape.swift` (créé) | Forme animable de la coque |
| `DynamicNotch/Shell/NotchPresentation.swift` (créé) | États, `ShellMetrics`, choix du ressort |
| `DynamicNotch/Shell/WingLayout.swift` (créé) | Largeur des ailes par activité |
| `DynamicNotch/Shell/BatteryGlyph.swift` (créé) | Glyphe batterie redimensionnable |
| `DynamicNotch/Shell/ActivityViews.swift` (créé) | Vues compactes et étendues des activités |
| `DynamicNotch/Activities/Activity.swift` (créé) | `ActivityID`, `ActivityDisplay`, durées et priorités |
| `DynamicNotch/Activities/ActivityScheduler.swift` (créé) | Minuterie injectable |
| `DynamicNotch/Activities/ActivityCenter.swift` (créé) | Arbitrage des activités |
| `DynamicNotch/Activities/PowerEvents.swift` (créé) | `PowerSnapshot`, `PowerEventDetector` |
| `DynamicNotch/Activities/ActivityWiring.swift` (créé) | Branche les sources sur `ActivityCenter` |
| `DynamicNotch/Debug/DebugTools.swift` (créé) | Simulation d'activités et rendu PNG des états (Debug) |
| `DynamicNotch/NotchView.swift`, `NotchViewModel.swift`, `NotchViewModel+Events.swift`, `NotchWindowController.swift`, `NotchViewController.swift`, `AppDelegate.swift`, `main.swift` (modifiés) | Coque et cycle de vie |
| `DynamicNotch/BatteryMonitor.swift` (réécrit) | Abonnement IOKit, événements |
| `DynamicNotch/NotchWingsView.swift`, `DynamicNotch/NotchShape.swift` (supprimés) | Remplacés par `Shell/` |

---

### Task 0 : outillage, cible de tests, macOS 14

**Files :**
- Create : `Tools/xcproj.rb`, `Tools/test.sh`, `Tools/build.sh`
- Rename : `DynamicNotch/NotchDrop.entitlements` → `DynamicNotch/DynamicNotch.entitlements` (le projet référence déjà ce nom)
- Modify : `DynamicNotch/main.swift`, `DynamicNotch/PublishedPersist.swift:26-60`, `DynamicNotchTests/PersistTests.swift`, `DynamicNotchTests/README.md`, `DynamicNotch.xcodeproj/project.pbxproj` (via le script), `DynamicNotch.xcodeproj/xcshareddata/xcschemes/DynamicNotch.xcscheme` (via le script)

**Interfaces :**
- Produces : `ruby Tools/xcproj.rb add <Cible> <fichiers…>`, `ruby Tools/xcproj.rb remove <fichiers…>`, `ruby Tools/xcproj.rb setup-tests`, `ruby Tools/xcproj.rb set-deployment <Cible> <version>` ; `Tools/test.sh [Classe]` ; `Tools/build.sh` ; global `persistWriteQueue: DispatchQueue`.

- [ ] **Step 1 : vérifier le gem**

Run : `ruby -e 'require "xcodeproj"; puts Xcodeproj::VERSION'`
Expected : `1.24.0`. Sinon : `gem install --user-install xcodeproj -v '~> 1.24.0' --no-document`.

- [ ] **Step 2 : écrire `Tools/xcproj.rb`**

```ruby
#!/usr/bin/env ruby
# Édite DynamicNotch.xcodeproj sans passer par Xcode.
#   ruby Tools/xcproj.rb add <Cible> <fichier.swift>...
#   ruby Tools/xcproj.rb remove <fichier.swift>...
#   ruby Tools/xcproj.rb setup-tests
#   ruby Tools/xcproj.rb set-deployment <Cible> <version>
require 'xcodeproj'

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
```

- [ ] **Step 3 : écrire `Tools/test.sh` et `Tools/build.sh`, les rendre exécutables**

`Tools/test.sh` :
```bash
#!/bin/bash
# Lance les tests unitaires. Argument optionnel : nom d'une classe de test.
set -o pipefail
cd "$(dirname "$0")/.."
ARGS=()
if [ -n "$1" ]; then ARGS+=("-only-testing:DynamicNotchTests/$1"); fi
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  test "${ARGS[@]}" 2>&1 | grep -E "error:|: error|failed|passed|Executed|TEST (SUCCEEDED|FAILED)|BUILD FAILED" | tail -60
```

`Tools/build.sh` :
```bash
#!/bin/bash
# Construit l'app non signée dans build/Build/Products/<Configuration>.
# Argument optionnel : Debug ou Release (défaut).
set -o pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration "$CONFIG" \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v "appintentsmetadataprocessor" | tail -60
```

Run : `chmod +x Tools/test.sh Tools/build.sh`

- [ ] **Step 4 : entitlements, cible de déploiement et cible de tests**

Run :
```bash
git mv DynamicNotch/NotchDrop.entitlements DynamicNotch/DynamicNotch.entitlements
ruby Tools/xcproj.rb set-deployment DynamicNotch 14.0
ruby Tools/xcproj.rb setup-tests
```
Expected : `DynamicNotch → macOS 14.0`, trois lignes `ajouté DynamicNotchTests/…`, `cible DynamicNotchTests créée et ajoutée au schéma`.

- [ ] **Step 5 : empêcher l'app hôte des tests de prendre le verrou d'instance unique**

Sans ça, si DynamicNotch tourne déjà, l'hôte de test appelle `exit(0)` et aucun test ne s'exécute. Dans `DynamicNotch/main.swift`, insérer juste avant `// Single-instance enforcement` :

```swift
// Hôte des tests unitaires : XCTest injecte le bundle de tests dans l'app en
// cours d'exécution. On démarre une app nue : ni verrou d'instance unique, ni
// fenêtres, ni migration de données.
if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}

```

- [ ] **Step 6 : sérialiser les écritures de `Persist` (corrige un test instable)**

Dans `DynamicNotch/PublishedPersist.swift`, après `private let valueDecoder = JSONDecoder()`, ajouter :

```swift
/// File unique et sérielle pour toutes les écritures de réglages : deux
/// changements rapprochés d'une même clé ne peuvent plus être réordonnés.
/// Les tests appellent `persistWriteQueue.sync {}` pour attendre l'écriture.
let persistWriteQueue = DispatchQueue(label: "wiki.qaq.DynamicNotch.persist")
```

Dans `Persist.init`, remplacer `.receive(on: DispatchQueue.global())` par `.receive(on: persistWriteQueue)`.

Dans `DynamicNotchTests/PersistTests.swift`, dans `test_persist_roundTrip_simpleString`, juste après `mutable.wrappedValue = "beta"`, ajouter :

```swift
        persistWriteQueue.sync {} // attend l'écriture asynchrone
```

- [ ] **Step 7 : lancer tous les tests**

Run : `Tools/test.sh`
Expected : `Executed N tests, with 0 failures` et `** TEST SUCCEEDED **`.
Si l'hôte refuse de charger le bundle (« code signature invalid »), relancer en remplaçant dans `Tools/test.sh` `CODE_SIGNING_ALLOWED=NO` par `CODE_SIGNING_ALLOWED=YES` (signature ad hoc `-`), et garder ce réglage.

- [ ] **Step 8 : mettre à jour `DynamicNotchTests/README.md`**

Remplacer la section « One-time wiring (Xcode UI, ~30 s) » (du titre jusqu'à la phrase sur la CI incluse) par :

```markdown
## Lancer les tests

    Tools/test.sh               # tous les tests
    Tools/test.sh PersistTests  # une seule classe

La cible `DynamicNotchTests` est branchée dans le projet. Pour ajouter un
fichier de test : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/MonTest.swift`.
```

- [ ] **Step 9 : build Release et commit**

Run : `Tools/build.sh` → Expected : `** BUILD SUCCEEDED **`.

```bash
git add -A Tools DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "chore: cible de tests, outillage xcodeproj, macOS 14

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1 : spike MediaRemote (jetable)

**But :** savoir si `MRMediaRemoteGetNowPlayingInfo` renvoie des données à un binaire non Apple sous macOS 26.6. Le code du spike n'est pas commité.

**Files :**
- Create (scratch, hors dépôt) : `$TMPDIR/mr-spike/mr.swift`
- Modify : ce plan, section « Résultat du spike » ci-dessous

- [ ] **Step 1 : demander à l'utilisateur de lancer une musique** (Musique, Spotify, ou une vidéo YouTube dans Safari ou Chrome) et d'attendre qu'elle joue.

- [ ] **Step 2 : écrire et lancer le spike**

```bash
mkdir -p "$TMPDIR/mr-spike" && cat > "$TMPDIR/mr-spike/mr.swift" <<'EOF'
import Foundation
let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)!
typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
let info = unsafeBitCast(dlsym(h, "MRMediaRemoteGetNowPlayingInfo")!, to: GetInfo.self)
info(.main) { d in
    print("clés :", d.keys.count, "titre :", d["kMRMediaRemoteNowPlayingInfoTitle"] ?? "nil")
    exit(0)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 2) { print("pas de réponse"); exit(0) }
dispatchMain()
EOF
swiftc -o "$TMPDIR/mr-spike/mr" "$TMPDIR/mr-spike/mr.swift" && "$TMPDIR/mr-spike/mr"
```

- [ ] **Step 3 : consigner le résultat** dans la section suivante et commiter le plan.

- Titre affiché → **accès direct OK** : exécuter la tâche 11 telle quelle.
- `clés : 0` alors que la musique joue → **accès bloqué** : ne pas exécuter la tâche 11. Signaler à l'utilisateur que l'activité musique nécessite l'adaptateur tiers mediaremote-adapter (téléchargement et intégration de code tiers : son accord est requis) et attendre sa décision.

```bash
git add docs/superpowers/plans/2026-09-24-refonte-coque-activites.md
git commit -m "docs: résultat du spike MediaRemote

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

#### Résultat du spike

_(à compléter par l'exécutant : date, lecteur utilisé, sortie brute, décision)_

---

### Task 2 : données dans Application Support, écritures atomiques

**Files :**
- Create : `DynamicNotch/DataMigration.swift`, `DynamicNotchTests/DataMigrationTests.swift`
- Modify : `DynamicNotch/main.swift`, `DynamicNotch/PublishedPersist.swift`, `DynamicNotch/SingleInstance.swift:36,52-57`, `DynamicNotch/TrayDrop.swift:106`, `DynamicNotch/TrayDrop+DropItem.swift:94`, `DynamicNotch/NotchSettingsView.swift:388`, `DynamicNotch/Widgets/NoteWidget.swift:6,13`

**Interfaces :**
- Consumes : `ruby Tools/xcproj.rb`, `Tools/test.sh`.
- Produces : globals `dataDirectory: URL` (remplace `documentsDirectory`), `legacyDataDirectory: URL` ; `enum DataMigration { static let markerName: String; static let configFiles: Set<String>; static func run(from: URL, to: URL, fileManager: FileManager = .default) }`.

- [ ] **Step 1 : écrire le test qui échoue**

`DynamicNotchTests/DataMigrationTests.swift` :
```swift
//
//  DataMigrationTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class DataMigrationTests: XCTestCase {
    private var root: URL!
    private var legacy: URL { root.appendingPathComponent("legacy") }
    private var destination: URL { root.appendingPathComponent("destination") }
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("DataMigrationTests-\(UUID().uuidString)")
        try fm.createDirectory(at: legacy.appendingPathComponent("Config"), withIntermediateDirectories: true)
        try fm.createDirectory(at: legacy.appendingPathComponent("CopiedItems/ABC"), withIntermediateDirectories: true)
        try Data("true".utf8).write(to: legacy.appendingPathComponent("Config/wingBattery"))
        try Data("0.95".utf8).write(to: legacy.appendingPathComponent("Config/notchOpacity"))
        try Data("\"x\"".utf8).write(to: legacy.appendingPathComponent("Config/prompterText"))
        try Data("note".utf8).write(to: legacy.appendingPathComponent("Config/quickNote.txt"))
        try Data("file".utf8).write(to: legacy.appendingPathComponent("CopiedItems/ABC/a.txt"))
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    func test_copiesKnownKeysOnly() {
        DataMigration.run(from: legacy, to: destination)
        let config = destination.appendingPathComponent("Config")
        XCTAssertTrue(fm.fileExists(atPath: config.appendingPathComponent("wingBattery").path))
        XCTAssertTrue(fm.fileExists(atPath: config.appendingPathComponent("quickNote.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: config.appendingPathComponent("notchOpacity").path))
        XCTAssertFalse(fm.fileExists(atPath: config.appendingPathComponent("prompterText").path))
    }

    func test_copiesTrayFiles() {
        DataMigration.run(from: legacy, to: destination)
        let file = destination.appendingPathComponent("CopiedItems/ABC/a.txt")
        XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), "file")
    }

    func test_runsOnlyOnce_andNeverOverwrites() throws {
        DataMigration.run(from: legacy, to: destination)
        let key = destination.appendingPathComponent("Config/wingBattery")
        try Data("false".utf8).write(to: key)
        DataMigration.run(from: legacy, to: destination)
        XCTAssertEqual(try String(contentsOf: key, encoding: .utf8), "false")
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent(DataMigration.markerName).path))
    }

    func test_leavesLegacyFolderInPlace() {
        DataMigration.run(from: legacy, to: destination)
        XCTAssertTrue(fm.fileExists(atPath: legacy.appendingPathComponent("Config/wingBattery").path))
    }

    func test_missingLegacyFolder_isHarmless() {
        DataMigration.run(from: root.appendingPathComponent("absent"), to: destination)
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent(DataMigration.markerName).path))
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/DataMigrationTests.swift && Tools/test.sh DataMigrationTests`
Expected : échec de compilation, `cannot find 'DataMigration' in scope`.

- [ ] **Step 2 : implémenter `DataMigration`**

`DynamicNotch/DataMigration.swift` :
```swift
//
//  DataMigration.swift
//  DynamicNotch
//
//  Migration unique des données de ~/Documents/DynamicNotch vers
//  ~/Library/Application Support/DynamicNotch (ou leur équivalent dans le
//  conteneur quand l'app est sandboxée : on passe toujours par FileManager).
//  Seules les clés encore lues par l'app sont reprises ; l'ancien dossier
//  reste en place.
//

import Foundation

enum DataMigration {
    static let markerName = ".migrated-v1"

    /// Fichiers de `Config/` encore utilisés. Les clés périmées d'anciennes
    /// versions (notchOpacity, prompterText, isProUnlocked, …) sont ignorées.
    static let configFiles: Set<String> = [
        "TrayDropItems", "alwaysVisibleWhenClosed", "customStorageTime",
        "customStorageTimeUnit", "displayPreference", "escClosesNotch",
        "forcePillMode", "hapticFeedback", "keepInterval",
        "pomodoroCyclesBeforeLongBreak", "pomodoroFocusMinutes",
        "pomodoroLongBreakMinutes", "pomodoroShortBreakMinutes",
        "popOnHoverEnabled", "quickNote.txt", "selectedFileStorageTime",
        "selectedLanguage", "showOnAllScreens", "widgetPages", "wingBattery",
        "wingCalendar", "wingPomodoro", "wingStopwatch", "wingsEnabled",
    ]

    static func run(from legacy: URL, to destination: URL, fileManager: FileManager = .default) {
        let marker = destination.appendingPathComponent(markerName)
        guard !fileManager.fileExists(atPath: marker.path) else { return }

        let legacyConfig = legacy.appendingPathComponent("Config")
        let config = destination.appendingPathComponent("Config")
        try? fileManager.createDirectory(at: config, withIntermediateDirectories: true)
        for name in configFiles {
            copyIfAbsent(legacyConfig.appendingPathComponent(name), to: config.appendingPathComponent(name), fileManager)
        }
        copyIfAbsent(
            legacy.appendingPathComponent("CopiedItems"),
            to: destination.appendingPathComponent("CopiedItems"),
            fileManager
        )
        fileManager.createFile(atPath: marker.path, contents: Data())
    }

    private static func copyIfAbsent(_ source: URL, to target: URL, _ fileManager: FileManager) {
        guard fileManager.fileExists(atPath: source.path),
              !fileManager.fileExists(atPath: target.path)
        else { return }
        try? fileManager.copyItem(at: source, to: target)
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/DataMigration.swift && Tools/test.sh DataMigrationTests`
Expected : `Executed 5 tests, with 0 failures`.

- [ ] **Step 3 : remplacer `documentsDirectory` par `dataDirectory`**

Dans `DynamicNotch/main.swift`, remplacer le bloc qui va de `private let availableDirectories` jusqu'à la création de `temporaryDirectory` incluse par :

```swift
private let fileManager = FileManager.default
/// Répertoire des données de l'app (réglages, fichiers du plateau, verrou).
let dataDirectory = fileManager
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("DynamicNotch")
/// Ancien emplacement, lu une seule fois par `DataMigration`.
let legacyDataDirectory = fileManager
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("DynamicNotch")
let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(bundleIdentifier)
try? fileManager.removeItem(at: temporaryDirectory)
try? fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
```

Toujours dans `main.swift`, juste après le `guard SingleInstance.acquire() else { exit(0) }`, ajouter :

```swift
DataMigration.run(from: legacyDataDirectory, to: dataDirectory)
```

Puis remplacer toutes les autres occurrences :

```bash
grep -rl 'documentsDirectory' DynamicNotch | xargs sed -i '' 's/documentsDirectory/dataDirectory/g'
sed -i '' 's|~/Documents/DynamicNotch/Config/quickNote.txt|<dataDirectory>/Config/quickNote.txt|' DynamicNotch/Widgets/NoteWidget.swift
grep -rn 'documentsDirectory\|Documents/DynamicNotch' DynamicNotch
```
Expected : la dernière commande n'affiche rien.

- [ ] **Step 4 : écritures atomiques**

Dans `DynamicNotch/PublishedPersist.swift`, dans `FileStorage.set`, remplacer `try? data?.write(to: pathForKey(key))` par :

```swift
        try? data?.write(to: pathForKey(key), options: .atomic)
```

- [ ] **Step 5 : tests, build, commit**

Run : `Tools/test.sh && Tools/build.sh`
Expected : `** TEST SUCCEEDED **` puis `** BUILD SUCCEEDED **`.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: données dans Application Support avec migration unique

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3 : `NotchGeometry` au pixel près

**Files :**
- Create : `DynamicNotch/Geometry/NotchGeometry.swift`, `DynamicNotchTests/NotchGeometryTests.swift`
- Modify : `DynamicNotch/Ext+NSScreen.swift` (supprimer `notchSize` et son commentaire d'en-tête), `DynamicNotch/DisplayPreference.swift:27`

**Interfaces :**
- Produces :
  - `func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat`
  - `struct ScreenDescriptor: Equatable { var displayID: UInt32; var frame: CGRect; var scale: CGFloat; var safeAreaTop: CGFloat; var auxiliaryTopLeft: CGRect?; var auxiliaryTopRight: CGRect?; var menuBarHeight: CGFloat }` + `init(_ screen: NSScreen)`
  - `struct NotchGeometry: Equatable { let screen: ScreenDescriptor; let notchRect: CGRect; let hasHardwareNotch: Bool; init(screen:forcePill:); var windowFrame: CGRect; var notchCenterXInWindow: CGFloat; static let windowSize: CGSize; static let preview: NotchGeometry }`

- [ ] **Step 1 : écrire les tests qui échouent**

`DynamicNotchTests/NotchGeometryTests.swift` :
```swift
//
//  NotchGeometryTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class NotchGeometryTests: XCTestCase {
    /// MacBook Pro 14" de référence (mesuré le 2026-09-24).
    private let reference = ScreenDescriptor(
        displayID: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        scale: 2,
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32),
        menuBarHeight: 32
    )

    func test_pixelAligned() {
        XCTAssertEqual(pixelAligned(663.3, scale: 2), 663.5)
        XCTAssertEqual(pixelAligned(663.2, scale: 2), 663.0)
        XCTAssertEqual(pixelAligned(663.5, scale: 1), 664.0)
    }

    func test_hardwareNotch_usesAuxiliaryAreas_notCentering() {
        let geometry = NotchGeometry(screen: reference)
        XCTAssertTrue(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 663, y: 950, width: 185, height: 32))
    }

    func test_hardwareNotch_onSecondaryScreenOrigin() {
        var screen = reference
        screen.frame.origin = CGPoint(x: -1512, y: 200)
        let geometry = NotchGeometry(screen: screen)
        XCTAssertEqual(geometry.notchRect, CGRect(x: -1512 + 663, y: 200 + 950, width: 185, height: 32))
    }

    func test_missingAuxiliaryAreas_fallsBackToRatio() {
        var screen = reference
        screen.auxiliaryTopLeft = nil
        screen.auxiliaryTopRight = nil
        let geometry = NotchGeometry(screen: screen)
        XCTAssertTrue(geometry.hasHardwareNotch)
        // 1512 × 0,12 = 181,44 → 181,5 ; centre 756 → x = 665,25 → 665,5
        XCTAssertEqual(geometry.notchRect, CGRect(x: 665.5, y: 950, width: 181.5, height: 32))
    }

    func test_noNotch_isMenuBarHighPill() {
        let screen = ScreenDescriptor(
            displayID: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1,
            safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil, menuBarHeight: 24
        )
        let geometry = NotchGeometry(screen: screen)
        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 865, y: 1056, width: 190, height: 24))
    }

    func test_forcePill_onNotchedScreen() {
        let geometry = NotchGeometry(screen: reference, forcePill: true)
        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 661, y: 950, width: 190, height: 32))
    }

    func test_windowFrame_isPixelAligned_andCenteredOnNotch() {
        let geometry = NotchGeometry(screen: reference)
        let frame = geometry.windowFrame
        XCTAssertEqual(frame.size, NotchGeometry.windowSize)
        XCTAssertEqual(frame.maxY, 982)
        XCTAssertEqual(frame.minX * 2, (frame.minX * 2).rounded())
        XCTAssertEqual(frame.minX + geometry.notchCenterXInWindow, geometry.notchRect.midX)
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/NotchGeometryTests.swift && Tools/test.sh NotchGeometryTests`
Expected : échec de compilation, `cannot find 'ScreenDescriptor' in scope`.

- [ ] **Step 2 : implémenter**

`DynamicNotch/Geometry/NotchGeometry.swift` :
```swift
//
//  NotchGeometry.swift
//  DynamicNotch
//
//  Géométrie de l'encoche calculée une fois, au pixel physique près. Valeur
//  pure (aucune dépendance à NSScreen hors de l'initialiseur de commodité),
//  donc testable sans écran réel.
//

import AppKit

/// Arrondit `value` au pixel physique le plus proche pour une échelle donnée.
func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
    guard scale > 0 else { return value.rounded() }
    return (value * scale).rounded() / scale
}

/// Ce que l'on retient d'un `NSScreen` pour calculer la géométrie.
struct ScreenDescriptor: Equatable {
    var displayID: UInt32
    var frame: CGRect
    var scale: CGFloat
    var safeAreaTop: CGFloat
    var auxiliaryTopLeft: CGRect?
    var auxiliaryTopRight: CGRect?
    var menuBarHeight: CGFloat
}

extension ScreenDescriptor {
    init(_ screen: NSScreen) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        self.init(
            displayID: (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0,
            frame: screen.frame,
            scale: screen.backingScaleFactor,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            // Barre masquée (plein écran) → 24 pt, pour que la signature
            // d'écran reste stable.
            menuBarHeight: max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        )
    }
}

struct NotchGeometry: Equatable {
    static let pillWidth: CGFloat = 190
    static let fallbackWidthRatio: CGFloat = 0.12
    /// Plus grand corps (réglages 880 × 560) + oreilles (2 × 10) + marge d'ombre (24).
    static let windowSize = CGSize(width: 880 + 2 * 10 + 2 * 24, height: 560 + 24)

    let screen: ScreenDescriptor
    /// Encoche (ou pilule) en coordonnées écran AppKit (origine en bas à gauche).
    let notchRect: CGRect
    let hasHardwareNotch: Bool

    init(screen: ScreenDescriptor, forcePill: Bool = false) {
        self.screen = screen
        let scale = screen.scale
        let frame = screen.frame

        if screen.safeAreaTop > 0, !forcePill {
            let height = pixelAligned(screen.safeAreaTop, scale: scale)
            hasHardwareNotch = true
            // Voie nominale : les zones visibles de part et d'autre de l'encoche.
            // On n'utilise que leurs largeurs, valables quel que soit le repère.
            if let left = screen.auxiliaryTopLeft?.width, let right = screen.auxiliaryTopRight?.width,
               left > 0, right > 0
            {
                let minX = pixelAligned(frame.minX + left, scale: scale)
                let maxX = pixelAligned(frame.maxX - right, scale: scale)
                if maxX - minX > 50, maxX - minX < frame.width / 2 {
                    notchRect = CGRect(x: minX, y: frame.maxY - height, width: maxX - minX, height: height)
                    return
                }
            }
            let width = pixelAligned(frame.width * Self.fallbackWidthRatio, scale: scale)
            notchRect = CGRect(
                x: pixelAligned(frame.midX - width / 2, scale: scale),
                y: frame.maxY - height, width: width, height: height
            )
            return
        }

        hasHardwareNotch = false
        let height = pixelAligned(screen.safeAreaTop > 0 ? screen.safeAreaTop : screen.menuBarHeight, scale: scale)
        let width = Self.pillWidth
        notchRect = CGRect(
            x: pixelAligned(frame.midX - width / 2, scale: scale),
            y: frame.maxY - height, width: width, height: height
        )
    }

    /// Fenêtre de taille fixe, collée en haut de l'écran et centrée sur l'encoche.
    var windowFrame: CGRect {
        let size = Self.windowSize
        return CGRect(
            x: pixelAligned(notchRect.midX - size.width / 2, scale: screen.scale),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Centre horizontal de l'encoche dans le repère SwiftUI de la fenêtre.
    var notchCenterXInWindow: CGFloat {
        notchRect.midX - windowFrame.minX
    }

    /// Géométrie de l'écran de référence, pour les aperçus et le rendu Debug.
    static let preview = NotchGeometry(screen: ScreenDescriptor(
        displayID: 0,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        scale: 2,
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
        auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32),
        menuBarHeight: 32
    ))
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Geometry/NotchGeometry.swift && Tools/test.sh NotchGeometryTests`
Expected : `Executed 7 tests, with 0 failures`.

- [ ] **Step 3 : retirer l'ancienne heuristique**

Dans `DynamicNotch/Ext+NSScreen.swift` : supprimer la propriété `notchSize` entière et le long commentaire d'en-tête qui la décrit (lignes « Détection robuste… » jusqu'à « …centrée. »). Garder `isBuildinDisplay` et `buildin`.

Dans `DynamicNotch/DisplayPreference.swift`, remplacer `if let screen = NSScreen.buildin, screen.notchSize != .zero { return screen }` par :

```swift
            if let screen = NSScreen.buildin, screen.safeAreaInsets.top > 0 { return screen }
```

Dans `DynamicNotch/NotchWindowController.swift`, l'ancien code lit encore `screen.notchSize`. Remplacer les lignes de `var notchSize = screen.notchSize` jusqu'à `vm.screenRect = screen.frame` incluses par :

```swift
        let geometry = NotchGeometry(screen: ScreenDescriptor(screen))
        let vm = NotchViewModel(inset: geometry.hasHardwareNotch ? -4 : 0)
        self.vm = vm
        contentViewController = NotchViewController(vm)
        vm.deviceNotchRect = geometry.notchRect
        vm.screenRect = screen.frame
```

(Transition : la tâche 9 réécrit ce contrôleur ; ici on garde juste l'app compilable avec la nouvelle géométrie.)

- [ ] **Step 4 : tests, build, commit**

Run : `Tools/test.sh && Tools/build.sh` → `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: géométrie de l'encoche calée au pixel sur les zones système

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4 : forme animable `NotchShellShape`

**Files :**
- Create : `DynamicNotch/Shell/NotchShellShape.swift`, `DynamicNotchTests/NotchShellShapeTests.swift`

**Interfaces :**
- Produces : `struct NotchShellShape: Shape { var centerX: CGFloat; var bodyWidth: CGFloat; var bodyHeight: CGFloat; var topRadius: CGFloat; var bottomRadius: CGFloat }` avec `animatableData` sur les quatre dernières valeurs.

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/NotchShellShapeTests.swift` :
```swift
//
//  NotchShellShapeTests.swift
//  DynamicNotchTests
//

import SwiftUI
import XCTest
@testable import DynamicNotch

final class NotchShellShapeTests: XCTestCase {
    private let canvas = CGRect(x: 0, y: 0, width: 948, height: 584)

    func test_bounds_includeEars() {
        let shape = NotchShellShape(centerX: 474, bodyWidth: 185, bodyHeight: 32, topRadius: 6, bottomRadius: 10)
        let bounds = shape.path(in: canvas).boundingRect
        XCTAssertEqual(bounds.minX, 474 - 92.5 - 6, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 474 + 92.5 + 6, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 32, accuracy: 0.001)
    }

    func test_pill_hasNoEars() {
        let shape = NotchShellShape(centerX: 474, bodyWidth: 190, bodyHeight: 24, topRadius: 0, bottomRadius: 12)
        let bounds = shape.path(in: canvas).boundingRect
        XCTAssertEqual(bounds.width, 190, accuracy: 0.001)
    }

    func test_radiiAreClamped() {
        let shape = NotchShellShape(centerX: 474, bodyWidth: 20, bodyHeight: 10, topRadius: 50, bottomRadius: 50)
        let path = shape.path(in: canvas)
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingRect.maxY, 10, accuracy: 0.001)
    }

    func test_animatableData_roundTrip() {
        var shape = NotchShellShape(centerX: 474, bodyWidth: 185, bodyHeight: 32, topRadius: 6, bottomRadius: 10)
        var data = shape.animatableData
        data.first.first = 340
        data.second.second = 24
        shape.animatableData = data
        XCTAssertEqual(shape.bodyWidth, 340)
        XCTAssertEqual(shape.bottomRadius, 24)
        XCTAssertEqual(shape.bodyHeight, 32)
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/NotchShellShapeTests.swift && Tools/test.sh NotchShellShapeTests`
Expected : échec de compilation, `cannot find 'NotchShellShape' in scope`.

- [ ] **Step 2 : implémenter**

`DynamicNotch/Shell/NotchShellShape.swift` :
```swift
//
//  NotchShellShape.swift
//  DynamicNotch
//
//  Silhouette unique de la coque, dessinée dans un canevas de taille fixe (la
//  fenêtre). Seule la géométrie du tracé est animée : aucune animation de
//  frame ni de mise à l'échelle, donc des bords nets à chaque image.
//
//      (left − tr, 0) ────────────────────────── (right + tr, 0)   ← bord de l'écran
//             ╲ oreille concave        oreille ╱
//          (left, tr)                    (right, tr)
//              │                             │
//          (left, h − br)              (right, h − br)
//              ╰── coin bas ────── coin bas ──╯
//

import SwiftUI

struct NotchShellShape: Shape {
    /// Centre horizontal de l'encoche dans le canevas (non animé).
    var centerX: CGFloat
    /// Largeur du corps, oreilles exclues.
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat
    /// Rayon des oreilles concaves du haut ; 0 pour une pilule.
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// Coefficient de Bézier d'un quart de cercle (1 − 0,552).
    private static let k: CGFloat = 0.448

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(bodyWidth, bodyHeight), .init(topRadius, bottomRadius)) }
        set {
            bodyWidth = newValue.first.first
            bodyHeight = newValue.first.second
            topRadius = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in _: CGRect) -> Path {
        let width = max(0, bodyWidth)
        let height = max(0, bodyHeight)
        let tr = max(0, min(topRadius, height / 2))
        let br = max(0, min(bottomRadius, height - tr, width / 2))
        let left = centerX - width / 2
        let right = centerX + width / 2
        let k = Self.k

        var p = Path()
        p.move(to: CGPoint(x: left - tr, y: 0))
        p.addCurve(
            to: CGPoint(x: left, y: tr),
            control1: CGPoint(x: left - tr * k, y: 0),
            control2: CGPoint(x: left, y: tr * k)
        )
        p.addLine(to: CGPoint(x: left, y: height - br))
        p.addCurve(
            to: CGPoint(x: left + br, y: height),
            control1: CGPoint(x: left, y: height - br * k),
            control2: CGPoint(x: left + br * k, y: height)
        )
        p.addLine(to: CGPoint(x: right - br, y: height))
        p.addCurve(
            to: CGPoint(x: right, y: height - br),
            control1: CGPoint(x: right - br * k, y: height),
            control2: CGPoint(x: right, y: height - br * k)
        )
        p.addLine(to: CGPoint(x: right, y: tr))
        p.addCurve(
            to: CGPoint(x: right + tr, y: 0),
            control1: CGPoint(x: right, y: tr * k),
            control2: CGPoint(x: right + tr * k, y: 0)
        )
        p.closeSubpath()
        return p
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Shell/NotchShellShape.swift && Tools/test.sh NotchShellShapeTests`
Expected : `Executed 4 tests, with 0 failures`.

- [ ] **Step 3 : commit**

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: forme de coque unique et animable

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5 : design system natif (typo SF Pro, ressorts, fin des glows et des zooms)

**Files :**
- Modify : `DynamicNotch/DesignSystem/DSTokens.swift`, `DynamicNotch/DesignSystem/DSComponents.swift`, `DynamicNotch/DesignSystem/DSGallery.swift`, `DynamicNotch/Share+View.swift`, `DynamicNotch/TrayDrop+DropItemView.swift`, `DynamicNotch/TrayDrop+View.swift`, `DynamicNotch/NotchContentView.swift`, `DynamicNotch/NotchSettingsView.swift`, `DynamicNotch/Widgets/*.swift`

**Interfaces :**
- Produces : `DS.Typography.wing`, `.activityTitle`, `.activitySubtitle`, `.activityValue` ; `DS.Motion.expand`, `.collapse`, `.micro`, `enum DS.Motion.Kind { case expand, collapse, micro }`, `static func DS.Motion.animation(_ kind: Kind) -> Animation` ; `DS.Color.hairline`. Supprime : `DS.Effect.glowBrand/glowDestructive/glowWarning`, `DS.Motion.expressive/crossfade`, `View.dsRimLight`.

Cette tâche est visuelle : pas de test unitaire, le build et la recherche des motifs interdits servent de garde-fous.

- [ ] **Step 1 : typographie**

Dans `DSTokens.swift`, remplacer tout le contenu de `enum Typography { … }` par :

```swift
    enum Typography {
        // SF Pro standard, comme les HUD et la barre de menus du système.
        // Rien sous 11 pt : en dessous, le texte bave sur fond noir.
        public static let displayLarge  = Font.system(size: 28, weight: .bold)
        public static let displayMedium = Font.system(size: 22, weight: .bold)
        public static let title         = Font.system(size: 17, weight: .semibold)
        public static let headline      = Font.system(size: 15, weight: .semibold)
        public static let body          = Font.system(size: 13, weight: .regular)
        public static let bodyEmphasis  = Font.system(size: 13, weight: .semibold)
        public static let caption       = Font.system(size: 11, weight: .medium)
        public static let captionSmall  = Font.system(size: 11, weight: .regular)
        public static let mono          = Font.system(size: 11, weight: .medium, design: .monospaced)

        // ─── Coque et activités ───────────────────────────────────────────
        /// Ailes de l'encoche : même corps que la barre de menus.
        public static let wing             = Font.system(size: 13, weight: .semibold).monospacedDigit()
        public static let activityTitle    = Font.system(size: 15, weight: .semibold)
        public static let activitySubtitle = Font.system(size: 12, weight: .regular)
        public static let activityValue    = Font.system(size: 26, weight: .semibold).monospacedDigit()
    }
```

- [ ] **Step 2 : ressorts**

Dans `DSTokens.swift`, remplacer tout le contenu de `enum Motion { … }` par :

```swift
    enum Motion {
        /// Micro-retour (survol, pression) des composants.
        public static let fast = Animation.spring(response: 0.18, dampingFraction: 0.85)
        /// Transitions d'état des composants.
        public static let base = Animation.spring(response: 0.32, dampingFraction: 0.78)

        // ─── Coque : seuls ressorts autorisés ─────────────────────────────
        /// Ouverture, expansion : léger rebond.
        public static let expand = Animation.spring(response: 0.42, dampingFraction: 0.78)
        /// Fermeture, repli : pas de rebond (Apple ne rebondit pas en rentrant).
        public static let collapse = Animation.spring(response: 0.32, dampingFraction: 0.95)
        /// Aperçu au survol.
        public static let micro = Animation.spring(response: 0.25, dampingFraction: 0.8)

        public enum Kind: Equatable { case expand, collapse, micro }

        public static func animation(_ kind: Kind) -> Animation {
            switch kind {
            case .expand: expand
            case .collapse: collapse
            case .micro: micro
            }
        }
    }
```

- [ ] **Step 3 : couleurs, effets, modificateurs**

Dans `DSTokens.swift` :
- dans `enum Color`, après `borderFocus`, ajouter :
  ```swift
          /// Trait fin unique des cartes (0,5 pt).
          public static let hairline = SwiftUI.Color.white.opacity(0.10)
  ```
- dans `enum Effect`, supprimer les trois lignes `glowBrand`, `glowDestructive`, `glowWarning` et le commentaire `// Glows …` au-dessus ;
- dans `dsCard`, remplacer `.strokeBorder(DS.Color.borderSubtle, lineWidth: 1)` par `.strokeBorder(DS.Color.hairline, lineWidth: 0.5)` ;
- supprimer entièrement la fonction `dsRimLight(radius:)` et son commentaire.

- [ ] **Step 4 : composants sans zoom ni glow**

Dans `DSComponents.swift` :
- `DSButton.body` : supprimer la ligne `.dsShadow(shadow)` ; remplacer `.scaleEffect(isPressed ? 0.97 : (isHovering ? 1.02 : 1.0))` par :
  ```swift
              .brightness(isHovering ? 0.08 : 0)
              .opacity(isPressed ? 0.75 : 1)
  ```
- supprimer la propriété `private var shadow: DS.Effect.Shadow { … }` de `DSButton` ;
- `DSIconTile.body` : supprimer `.dsShadow(isHovering ? glow : DS.Effect.shadowSm)` ; remplacer `.scaleEffect(isPressed ? 0.96 : (isHovering ? 1.03 : 1.0))` par `.opacity(isPressed ? 0.75 : 1)` ;
- supprimer la propriété `private var glow: DS.Effect.Shadow { … }` de `DSIconTile` ;
- `DSCard.body` : supprimer `.dsRimLight(radius: radius)` ;
- dans la zone de dépôt (vers la ligne 410), supprimer `.dsShadow(isTargeted ? DS.Effect.glowBrand : DS.Effect.shadowSm)`.

Dans `Share+View.swift` : supprimer `.dsShadow(targeting ? DS.Effect.glowBrand : DS.Effect.shadowSm)` et `.scaleEffect(hover && !targeting ? 1.02 : 1)`, puis dans `background` remplacer le `.fill(…)` par :

```swift
            .fill(targeting ? DS.Color.brand.opacity(0.18) : (hover ? DS.Color.surfaceRaisedStrong : DS.Color.surfaceRaised))
```

Dans `TrayDrop+DropItemView.swift`, remplacer `.scaleEffect(hover ? 1.05 : 1.0)` par :

```swift
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(hover ? DS.Color.surfaceRaisedStrong : Color.clear)
        )
```

et remplacer l'insertion `.opacity.combined(with: .scale)` de sa transition par `.opacity`.

- [ ] **Step 5 : motifs interdits dans le reste de l'app**

```bash
cd DynamicNotch
grep -rl 'dsRimLight' . | xargs sed -i '' '/\.dsRimLight(/d'
sed -i '' -E 's/\.font\(\.system\(size: (9|10), weight: \.semibold\)\)/.font(.system(size: 11, weight: .semibold))/' \
  NotchSettingsView.swift TrayDrop+View.swift Widgets/*.swift DesignSystem/DSComponents.swift
sed -i '' 's/, design: \.rounded//' TrayDrop+DropItemView.swift Widgets/*.swift
sed -i '' 's/\.transition(\.scale(scale: 0\.85)\.combined(with: \.opacity))/.transition(.opacity)/' NotchContentView.swift NotchSettingsView.swift
sed -i '' 's/insertion: \.opacity\.combined(with: \.scale(scale: 0\.95)),/insertion: .opacity,/' NotchContentView.swift
cd ..
grep -rn 'dsRimLight\|glowBrand\|glowWarning\|glowDestructive\|design: \.rounded\|size: 9,\|size: 10,\|\.scale(scale' DynamicNotch --include='*.swift' | grep -v 'NotchWingsView.swift'
```
Expected : la dernière commande n'affiche rien (`NotchWingsView.swift` disparaît en tâche 9). S'il reste une ligne, la corriger à la main selon la même règle.

`DSGallery.swift` affiche les échelles : remplacer le libellé `"captionSmall — 10"` par `"captionSmall — 11"`.

- [ ] **Step 6 : build, tests, commit**

Run : `Tools/build.sh && Tools/test.sh` → `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

```bash
git add -A DynamicNotch
git commit -m "refactor: design system SF Pro, ressorts de coque, fin des glows et des zooms

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 6 : moteur d'activités (`ActivityCenter`)

**Files :**
- Create : `DynamicNotch/Activities/Activity.swift`, `DynamicNotch/Activities/ActivityScheduler.swift`, `DynamicNotch/Activities/ActivityCenter.swift`, `DynamicNotchTests/ActivityCenterTests.swift`

**Interfaces :**
- Produces :
  - `enum ActivityID: Hashable { case charging, unplugged, lowBattery(percent: Int), pomodoroPhase, stopwatch, filesAdded(count: Int), airDropSent, nowPlaying, calendarSoon }`, avec `var transientDuration: TimeInterval`, `var persistentPriority: Int`, `static let samples: [ActivityID]`, `var debugName: String`
  - `struct ActivityDisplay: Equatable { enum Mode { case compact, expanded }; let id: ActivityID; let mode: Mode }`
  - `@MainActor protocol ActivityScheduler: AnyObject { var now: Date { get }; func schedule(after: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork }`, `@MainActor final class ScheduledWork { func cancel() }`, `@MainActor final class MainQueueScheduler: ActivityScheduler`
  - `@MainActor final class ActivityCenter { static let shared; static let staleAfter: TimeInterval = 5; init(scheduler:); private(set) var current: ActivityDisplay?; var isSuspended: Bool; func post(_ id: ActivityID); func setPersistent(_ id: ActivityID, active: Bool); func beginSuspension(); func endSuspension(); @discardableResult func observe(_ handler: @escaping (ActivityDisplay?) -> Void) -> ActivityObservation }`
  - `@MainActor final class ActivityObservation { func cancel() }`

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/ActivityCenterTests.swift` :
```swift
//
//  ActivityCenterTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

/// Minuterie manuelle : `advance(by:)` exécute de façon synchrone les travaux échus.
@MainActor
final class ManualScheduler: ActivityScheduler {
    private final class Job {
        let fireAt: Date
        let action: @MainActor () -> Void
        var cancelled = false
        init(fireAt: Date, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.action = action
        }
    }

    private(set) var now = Date(timeIntervalSince1970: 1_000)
    private var jobs: [Job] = []

    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        let job = Job(fireAt: now.addingTimeInterval(seconds), action: action)
        jobs.append(job)
        return ScheduledWork { job.cancelled = true }
    }

    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = jobs.filter({ !$0.cancelled && $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            now = next.fireAt
            next.cancelled = true
            next.action()
        }
        now = target
    }
}

@MainActor
final class ActivityCenterTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var center: ActivityCenter!

    override func setUp() async throws {
        scheduler = ManualScheduler()
        center = ActivityCenter(scheduler: scheduler)
    }

    func test_transient_expandsThenClears() {
        center.post(.charging)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .expanded))
        scheduler.advance(by: 2.1)
        XCTAssertNotNil(center.current)
        scheduler.advance(by: 0.2)
        XCTAssertNil(center.current)
    }

    func test_transient_collapsesToPersistent() {
        center.setPersistent(.charging, active: true)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .compact))
        center.post(.charging)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .expanded))
        scheduler.advance(by: 2.2)
        XCTAssertEqual(center.current, ActivityDisplay(id: .charging, mode: .compact))
    }

    func test_persistentPriorities() {
        center.setPersistent(.charging, active: true)
        center.setPersistent(.stopwatch, active: true)
        XCTAssertEqual(center.current?.id, .stopwatch)
        center.setPersistent(.pomodoroPhase, active: true)
        XCTAssertEqual(center.current?.id, .pomodoroPhase)
        center.setPersistent(.pomodoroPhase, active: false)
        XCTAssertEqual(center.current?.id, .stopwatch)
    }

    func test_transientsAreQueued_inArrivalOrder() {
        center.post(.filesAdded(count: 2))
        center.post(.airDropSent)
        XCTAssertEqual(center.current?.id, .filesAdded(count: 2))
        scheduler.advance(by: 1.2)
        XCTAssertEqual(center.current?.id, .airDropSent)
        scheduler.advance(by: 1.2)
        XCTAssertNil(center.current)
    }

    func test_staleQueuedTransient_isDropped() {
        center.post(.lowBattery(percent: 10)) // 3 s
        center.post(.charging)                // attend 3 s, dure 2,2 s
        center.post(.unplugged)               // attend 5,2 s → abandonné
        scheduler.advance(by: 3)
        XCTAssertEqual(center.current?.id, .charging)
        scheduler.advance(by: 2.2)
        XCTAssertNil(center.current)
    }

    func test_sameTransient_extendsInsteadOfQueuing() {
        center.post(.charging)
        scheduler.advance(by: 2)
        center.post(.charging)
        scheduler.advance(by: 1)
        XCTAssertEqual(center.current?.id, .charging)
        scheduler.advance(by: 1.3)
        XCTAssertNil(center.current)
    }

    func test_suspension_dropsTransients_butKeepsPersistent() {
        center.setPersistent(.stopwatch, active: true)
        center.post(.charging)
        center.beginSuspension()
        XCTAssertEqual(center.current, ActivityDisplay(id: .stopwatch, mode: .compact))
        center.post(.airDropSent)
        XCTAssertEqual(center.current?.mode, .compact)
        center.endSuspension()
        XCTAssertFalse(center.isSuspended)
        scheduler.advance(by: 5)
        XCTAssertEqual(center.current, ActivityDisplay(id: .stopwatch, mode: .compact))
    }

    func test_observers_notifiedOncePerChange() {
        var received: [ActivityDisplay?] = []
        let observation = center.observe { received.append($0) }
        center.setPersistent(.charging, active: true)
        center.setPersistent(.charging, active: true)
        center.post(.charging)
        scheduler.advance(by: 2.2)
        XCTAssertEqual(received, [
            ActivityDisplay(id: .charging, mode: .compact),
            ActivityDisplay(id: .charging, mode: .expanded),
            ActivityDisplay(id: .charging, mode: .compact),
        ])
        observation.cancel()
        center.setPersistent(.charging, active: false)
        XCTAssertEqual(received.count, 3)
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/ActivityCenterTests.swift && Tools/test.sh ActivityCenterTests`
Expected : échec de compilation, `cannot find type 'ActivityScheduler' in scope`.

- [ ] **Step 2 : types d'activité**

`DynamicNotch/Activities/Activity.swift` :
```swift
//
//  Activity.swift
//  DynamicNotch
//
//  Catalogue des activités affichables par l'encoche. Une même valeur sert en
//  mode ponctuel (état étendu) et persistant (ailes compactes) : c'est ce qui
//  permet l'animation continue de l'un à l'autre.
//

import Foundation

enum ActivityID: Hashable {
    case charging
    case unplugged
    case lowBattery(percent: Int)
    case pomodoroPhase
    case stopwatch
    case filesAdded(count: Int)
    case airDropSent
    case nowPlaying
    case calendarSoon

    /// Durée d'affichage en mode étendu quand l'activité est ponctuelle.
    var transientDuration: TimeInterval {
        switch self {
        case .charging: 2.2
        case .unplugged: 1.5
        case .lowBattery: 3
        case .pomodoroPhase: 2.5
        case .filesAdded, .airDropSent: 1.2
        case .nowPlaying: 2
        case .stopwatch, .calendarSoon: 2
        }
    }

    /// Priorité en mode persistant : la plus haute occupe les ailes.
    var persistentPriority: Int {
        switch self {
        case .pomodoroPhase: 40
        case .stopwatch: 30
        case .nowPlaying: 20
        case .calendarSoon: 15
        case .charging: 10
        case .unplugged, .lowBattery, .filesAdded, .airDropSent: 0
        }
    }

    /// Une valeur de chaque cas, pour la simulation et le rendu Debug.
    static let samples: [ActivityID] = [
        .charging, .unplugged, .lowBattery(percent: 10), .pomodoroPhase, .stopwatch,
        .filesAdded(count: 3), .airDropSent, .nowPlaying, .calendarSoon,
    ]

    /// Nom court (« charging », « lowBattery », …) pour la ligne de commande et les fichiers.
    var debugName: String {
        String(describing: self).components(separatedBy: "(").first ?? "activity"
    }
}

/// Ce que l'encoche doit afficher à un instant donné.
struct ActivityDisplay: Equatable {
    enum Mode: Equatable { case compact, expanded }
    let id: ActivityID
    let mode: Mode
}
```

- [ ] **Step 3 : minuterie injectable**

`DynamicNotch/Activities/ActivityScheduler.swift` :
```swift
//
//  ActivityScheduler.swift
//  DynamicNotch
//
//  Minuterie injectable d'ActivityCenter. En production, la file principale ;
//  en test, une minuterie manuelle qui avance le temps de façon synchrone.
//

import Foundation

@MainActor
protocol ActivityScheduler: AnyObject {
    var now: Date { get }
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork
}

/// Travail planifié, annulable une seule fois.
@MainActor
final class ScheduledWork {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

@MainActor
final class MainQueueScheduler: ActivityScheduler {
    var now: Date { Date() }

    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledWork {
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return ScheduledWork { item.cancel() }
    }
}
```

- [ ] **Step 4 : `ActivityCenter`**

`DynamicNotch/Activities/ActivityCenter.swift` :
```swift
//
//  ActivityCenter.swift
//  DynamicNotch
//
//  Arbitre unique des activités, partagé par tous les écrans.
//   - Une ponctuelle en cours → mode étendu pendant sa durée.
//   - Sinon la persistante de plus haute priorité → mode compact.
//   - Ponctuelles suivantes : en file, dans l'ordre d'arrivée ; abandonnées
//     après `staleAfter` secondes d'attente ; la même que celle en cours la
//     prolonge.
//   - Suspendu (panneau ouvert par l'utilisateur) : les ponctuelles sont
//     ignorées, les persistantes continuent d'être suivies.
//

import Foundation

@MainActor
final class ActivityCenter {
    static let shared = ActivityCenter(scheduler: MainQueueScheduler())
    static let staleAfter: TimeInterval = 5

    private struct Pending {
        let id: ActivityID
        let postedAt: Date
    }

    private(set) var current: ActivityDisplay?

    private let scheduler: ActivityScheduler
    private var transient: Pending?
    private var queue: [Pending] = []
    private var persistent: Set<ActivityID> = []
    private var endWork: ScheduledWork?
    private var suspensionCount = 0
    private var observers: [UUID: (ActivityDisplay?) -> Void] = [:]

    init(scheduler: ActivityScheduler) {
        self.scheduler = scheduler
    }

    var isSuspended: Bool { suspensionCount > 0 }

    func post(_ id: ActivityID) {
        guard !isSuspended else { return }
        let pending = Pending(id: id, postedAt: scheduler.now)
        if transient == nil || transient?.id == id {
            start(pending)
        } else {
            queue.removeAll { $0.id == id }
            queue.append(pending)
        }
    }

    func setPersistent(_ id: ActivityID, active: Bool) {
        let changed = active ? persistent.insert(id).inserted : persistent.remove(id) != nil
        if changed { recompute() }
    }

    func beginSuspension() {
        suspensionCount += 1
        endWork?.cancel()
        endWork = nil
        transient = nil
        queue.removeAll()
        recompute()
    }

    func endSuspension() {
        suspensionCount = max(0, suspensionCount - 1)
        recompute()
    }

    @discardableResult
    func observe(_ handler: @escaping (ActivityDisplay?) -> Void) -> ActivityObservation {
        let key = UUID()
        observers[key] = handler
        return ActivityObservation { [weak self] in
            self?.observers[key] = nil
        }
    }

    // MARK: interne

    private func start(_ pending: Pending) {
        endWork?.cancel()
        transient = pending
        endWork = scheduler.schedule(after: pending.id.transientDuration) { [weak self] in
            self?.finishTransient()
        }
        recompute()
    }

    private func finishTransient() {
        endWork = nil
        transient = nil
        let now = scheduler.now
        queue.removeAll { now.timeIntervalSince($0.postedAt) > Self.staleAfter }
        if queue.isEmpty {
            recompute()
        } else {
            start(queue.removeFirst())
        }
    }

    private func recompute() {
        let next: ActivityDisplay?
        if let transient {
            next = ActivityDisplay(id: transient.id, mode: .expanded)
        } else if let top = persistent.max(by: { $0.persistentPriority < $1.persistentPriority }) {
            next = ActivityDisplay(id: top, mode: .compact)
        } else {
            next = nil
        }
        guard next != current else { return }
        current = next
        for handler in observers.values {
            handler(next)
        }
    }
}

/// Jeton d'abonnement à `ActivityCenter`. `cancel()` désabonne.
@MainActor
final class ActivityObservation {
    private var onCancel: (() -> Void)?

    init(_ onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }
}
```

Run :
```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Activities/Activity.swift DynamicNotch/Activities/ActivityScheduler.swift DynamicNotch/Activities/ActivityCenter.swift
Tools/test.sh ActivityCenterTests
```
Expected : `Executed 8 tests, with 0 failures`.

- [ ] **Step 5 : commit**

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: moteur d'activités avec file, priorités et suspension

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7 : événements d'alimentation instantanés

**Files :**
- Create : `DynamicNotch/Activities/PowerEvents.swift`, `DynamicNotchTests/PowerEventsTests.swift`
- Rewrite : `DynamicNotch/BatteryMonitor.swift`

**Interfaces :**
- Produces :
  - `struct PowerSnapshot: Equatable { var hasBattery: Bool; var level: Double; var isPluggedIn: Bool; var isCharging: Bool; var minutesToFull: Int?; static func parse(_ descriptions: [[String: Any]]) -> PowerSnapshot; var percent: Int }`
  - `enum PowerEvent: Equatable { case pluggedIn, unplugged, lowBattery(percent: Int) }`
  - `struct PowerEventDetector { static let thresholds: [Int]; mutating func process(_ snapshot: PowerSnapshot) -> [PowerEvent] }`
  - `BatteryMonitor` (`ObservableObject`, `@MainActor`, singleton) : `@Published private(set) var snapshot: PowerSnapshot`, `var onChange: ((PowerSnapshot, [PowerEvent]) -> Void)?`, propriétés conservées : `level`, `isCharging`, `isPluggedIn`, `hasBattery`, `percentText`, `indicativeTint` ; nouvelles : `percent: Int`, `timeToFullText: String?`.

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/PowerEventsTests.swift` :
```swift
//
//  PowerEventsTests.swift
//  DynamicNotchTests
//

import IOKit.ps
import XCTest
@testable import DynamicNotch

final class PowerEventsTests: XCTestCase {
    private func battery(_ capacity: Int, ac: Bool, charging: Bool = false, timeToFull: Int = -1) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: capacity,
            kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: ac ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: charging,
            kIOPSTimeToFullChargeKey: timeToFull,
        ]
    }

    private func snapshot(_ percent: Int, ac: Bool) -> PowerSnapshot {
        PowerSnapshot(hasBattery: true, level: Double(percent) / 100, isPluggedIn: ac, isCharging: ac, minutesToFull: nil)
    }

    // MARK: parse

    func test_parse_internalBattery() {
        let s = PowerSnapshot.parse([battery(82, ac: true, charging: true, timeToFull: 70)])
        XCTAssertEqual(s, PowerSnapshot(hasBattery: true, level: 0.82, isPluggedIn: true, isCharging: true, minutesToFull: 70))
        XCTAssertEqual(s.percent, 82)
    }

    func test_parse_unknownTimeToFull_isNil() {
        XCTAssertNil(PowerSnapshot.parse([battery(50, ac: true, timeToFull: -1)]).minutesToFull)
    }

    func test_parse_noBattery() {
        let s = PowerSnapshot.parse([[kIOPSTypeKey: "UPS"]])
        XCTAssertFalse(s.hasBattery)
        XCTAssertTrue(s.isPluggedIn)
    }

    // MARK: detector

    func test_firstSnapshot_emitsNothing() {
        var detector = PowerEventDetector()
        XCTAssertEqual(detector.process(snapshot(15, ac: false)), [])
    }

    func test_plugAndUnplugEdges() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(60, ac: false))
        XCTAssertEqual(detector.process(snapshot(60, ac: true)), [.pluggedIn])
        XCTAssertEqual(detector.process(snapshot(61, ac: true)), [])
        XCTAssertEqual(detector.process(snapshot(61, ac: false)), [.unplugged])
    }

    func test_lowBattery_firesOncePerThreshold() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(21, ac: false))
        XCTAssertEqual(detector.process(snapshot(20, ac: false)), [.lowBattery(percent: 20)])
        XCTAssertEqual(detector.process(snapshot(19, ac: false)), [])
        XCTAssertEqual(detector.process(snapshot(10, ac: false)), [.lowBattery(percent: 10)])
        XCTAssertEqual(detector.process(snapshot(9, ac: false)), [])
    }

    func test_launchBelowThreshold_doesNotWarnUntilNextThreshold() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(15, ac: false))
        XCTAssertEqual(detector.process(snapshot(14, ac: false)), [])
        XCTAssertEqual(detector.process(snapshot(10, ac: false)), [.lowBattery(percent: 10)])
    }

    func test_unplugBelowThreshold_onlyEmitsUnplugged() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(15, ac: true))
        XCTAssertEqual(detector.process(snapshot(15, ac: false)), [.unplugged])
        XCTAssertEqual(detector.process(snapshot(10, ac: false)), [.lowBattery(percent: 10)])
    }

    func test_crossingTwoThresholdsAtOnce_emitsOnce() {
        var detector = PowerEventDetector()
        _ = detector.process(snapshot(21, ac: false))
        XCTAssertEqual(detector.process(snapshot(9, ac: false)), [.lowBattery(percent: 9)])
        XCTAssertEqual(detector.process(snapshot(8, ac: false)), [])
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/PowerEventsTests.swift && Tools/test.sh PowerEventsTests`
Expected : échec de compilation, `cannot find 'PowerSnapshot' in scope`.

- [ ] **Step 2 : implémenter**

`DynamicNotch/Activities/PowerEvents.swift` :
```swift
//
//  PowerEvents.swift
//  DynamicNotch
//
//  Lecture pure de l'état d'alimentation (dictionnaires IOKit) et détection
//  des événements : branchement, débranchement, franchissement des seuils de
//  batterie faible. Aucune dépendance système : testable avec des données factices.
//

import Foundation
import IOKit.ps

struct PowerSnapshot: Equatable {
    var hasBattery: Bool
    /// 0…1
    var level: Double
    var isPluggedIn: Bool
    var isCharging: Bool
    /// `nil` quand macOS ne sait pas encore estimer.
    var minutesToFull: Int?

    var percent: Int { Int((level * 100).rounded()) }

    /// Parse les descriptions renvoyées par `IOPSGetPowerSourceDescription`.
    static func parse(_ descriptions: [[String: Any]]) -> PowerSnapshot {
        guard let battery = descriptions.first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }) else {
            // Mac de bureau : toujours sur secteur, pas de batterie.
            return PowerSnapshot(hasBattery: false, level: 1, isPluggedIn: true, isCharging: false, minutesToFull: nil)
        }
        var level = 1.0
        if let capacity = battery[kIOPSCurrentCapacityKey] as? Int,
           let maximum = battery[kIOPSMaxCapacityKey] as? Int, maximum > 0
        {
            level = min(1, Double(capacity) / Double(maximum))
        }
        let timeToFull = battery[kIOPSTimeToFullChargeKey] as? Int ?? -1
        return PowerSnapshot(
            hasBattery: true,
            level: level,
            isPluggedIn: (battery[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
            isCharging: battery[kIOPSIsChargingKey] as? Bool ?? false,
            minutesToFull: timeToFull > 0 ? timeToFull : nil
        )
    }
}

enum PowerEvent: Equatable {
    case pluggedIn
    case unplugged
    case lowBattery(percent: Int)
}

struct PowerEventDetector {
    static let thresholds = [20, 10]

    private var previous: PowerSnapshot?
    private var firedThresholds: Set<Int> = []

    mutating func process(_ snapshot: PowerSnapshot) -> [PowerEvent] {
        defer { previous = snapshot }
        guard snapshot.hasBattery else { return [] }
        let percent = snapshot.percent

        guard let previous else {
            // Au lancement : les seuils déjà franchis ne déclenchent rien.
            firedThresholds = Set(Self.thresholds.filter { percent <= $0 })
            return []
        }

        var events: [PowerEvent] = []
        if !previous.isPluggedIn, snapshot.isPluggedIn {
            events.append(.pluggedIn)
        }
        if previous.isPluggedIn, !snapshot.isPluggedIn {
            events.append(.unplugged)
            // On n'alerte que sur un franchissement pendant la décharge.
            firedThresholds = Set(Self.thresholds.filter { percent <= $0 })
            return events
        }
        if !snapshot.isPluggedIn {
            let crossed = Self.thresholds.filter { percent <= $0 && !firedThresholds.contains($0) }
            if !crossed.isEmpty {
                firedThresholds.formUnion(crossed)
                events.append(.lowBattery(percent: percent))
            }
        }
        return events
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Activities/PowerEvents.swift && Tools/test.sh PowerEventsTests`
Expected : `Executed 8 tests, with 0 failures`.

- [ ] **Step 3 : réécrire `BatteryMonitor` sur l'abonnement IOKit**

Remplacer tout `DynamicNotch/BatteryMonitor.swift` par :
```swift
//
//  BatteryMonitor.swift
//  DynamicNotch
//
//  État de la batterie, mis à jour instantanément par l'abonnement système
//  IOPSNotificationCreateRunLoopSource (plus de minuterie de 10 s).
//  `onChange` reçoit le nouvel état et les événements détectés.
//

import Combine
import IOKit.ps
import SwiftUI

@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var snapshot = PowerSnapshot(
        hasBattery: false, level: 1, isPluggedIn: true, isCharging: false, minutesToFull: nil
    )
    var onChange: ((PowerSnapshot, [PowerEvent]) -> Void)?

    private var detector = PowerEventDetector()
    private var runLoopSource: CFRunLoopSource?

    private init() {
        refresh()
        // Singleton jamais libéré : un pointeur non retenu suffit.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    // MARK: accès simplifiés

    var level: Double { snapshot.level }
    var isCharging: Bool { snapshot.isCharging }
    var isPluggedIn: Bool { snapshot.isPluggedIn }
    var hasBattery: Bool { snapshot.hasBattery }
    var percent: Int { snapshot.percent }

    /// « 87 % », avec l'espace insécable de la typographie française.
    var percentText: String { "\(percent) %" }

    /// Vert au-dessus de 50 %, jaune au-dessus de 20 %, rouge en dessous.
    var indicativeTint: Color {
        if level > 0.5 { return DS.Color.success }
        if level > 0.2 { return DS.Color.warning }
        return DS.Color.destructive
    }

    /// « Pleine dans 1 h 10 », « Pleine dans 25 min », ou `nil` si inconnu.
    var timeToFullText: String? {
        guard let minutes = snapshot.minutesToFull else { return nil }
        if minutes < 60 { return "Pleine dans \(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "Pleine dans \(minutes / 60) h" : "Pleine dans \(minutes / 60) h \(String(format: "%02d", rest))"
    }

    func refresh() {
        let next = Self.readSnapshot()
        let events = detector.process(next)
        snapshot = next
        onChange?(next, events)
    }

    private static func readSnapshot() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return PowerSnapshot.parse([]) }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerSnapshot.parse(descriptions)
    }
}
```

- [ ] **Step 4 : build, tests, vérification manuelle, commit**

Run : `Tools/build.sh && Tools/test.sh` → `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.
(`NotchWingsView.swift` compile encore : il n'utilise que `level`, `indicativeTint`, `isCharging`, `percentText`, `hasBattery`, `isPluggedIn`, tous conservés.)

Vérification manuelle : `pkill -x DynamicNotch; open build/Build/Products/Release/DynamicNotch.app`, débrancher puis rebrancher le chargeur. L'aile batterie actuelle doit apparaître en moins d'une seconde (avant : jusqu'à 10 s).

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: batterie suivie par abonnement IOKit, détection des événements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8 : états de la coque, métriques et ailes

**Files :**
- Create : `DynamicNotch/Shell/NotchPresentation.swift`, `DynamicNotch/Shell/WingLayout.swift`, `DynamicNotchTests/NotchPresentationTests.swift`

**Interfaces :**
- Consumes : `ActivityID` (tâche 6), `pixelAligned` (tâche 3), `DS.Motion.Kind` (tâche 5), `NotchViewModel.ContentType` (existant : `normal = 0, menu = 1, settings = 2`).
- Produces :
  - `enum NotchPresentation: Equatable { case closed, peek, compact(ActivityID), expanded(ActivityID), opened(NotchViewModel.ContentType); var isOpened: Bool; func metrics(notch: CGSize, hasHardwareNotch: Bool, scale: CGFloat) -> ShellMetrics; static func motion(from: NotchPresentation, to: NotchPresentation) -> DS.Motion.Kind }`
  - `struct ShellMetrics: Equatable { var bodyWidth, bodyHeight, topRadius, bottomRadius: CGFloat; var hasShadow: Bool }`
  - `extension NotchViewModel.ContentType { var panelSize: CGSize }`
  - `enum WingLayout { static let padding: CGFloat; static func wingWidth(for: ActivityID) -> CGFloat; static func wingsWidth(for: ActivityID, scale: CGFloat) -> CGFloat }`

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/NotchPresentationTests.swift` :
```swift
//
//  NotchPresentationTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class NotchPresentationTests: XCTestCase {
    private let notch = CGSize(width: 185, height: 32)

    private func metrics(_ p: NotchPresentation, hardware: Bool = true) -> ShellMetrics {
        p.metrics(notch: hardware ? notch : CGSize(width: 190, height: 24), hasHardwareNotch: hardware, scale: 2)
    }

    func test_closed_matchesHardwareNotch() {
        XCTAssertEqual(metrics(.closed), ShellMetrics(bodyWidth: 185, bodyHeight: 32, topRadius: 6, bottomRadius: 10, hasShadow: false))
    }

    func test_peek_isSlightlyLarger() {
        XCTAssertEqual(metrics(.peek), ShellMetrics(bodyWidth: 197, bodyHeight: 36, topRadius: 6, bottomRadius: 12, hasShadow: false))
    }

    func test_compact_addsTwoEqualWings() {
        let m = metrics(.compact(.charging))
        XCTAssertEqual(m.bodyWidth, 185 + WingLayout.wingsWidth(for: .charging, scale: 2))
        XCTAssertEqual(m.bodyHeight, 32)
        XCTAssertFalse(m.hasShadow)
    }

    func test_expanded_and_opened() {
        XCTAssertEqual(metrics(.expanded(.charging)), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 10, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.normal)), ShellMetrics(bodyWidth: 600, bodyHeight: 180, topRadius: 10, bottomRadius: 28, hasShadow: true))
        XCTAssertEqual(metrics(.opened(.settings)).bodyWidth, 880)
    }

    func test_pill_hasNoEars_andRoundEnds() {
        XCTAssertEqual(metrics(.closed, hardware: false), ShellMetrics(bodyWidth: 190, bodyHeight: 24, topRadius: 0, bottomRadius: 12, hasShadow: false))
    }

    func test_motion() {
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .peek), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .peek, to: .closed), .micro)
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .opened(.normal)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.normal), to: .closed), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .compact(.charging), to: .expanded(.charging)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .expanded(.charging), to: .compact(.charging)), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.normal), to: .opened(.settings)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .opened(.settings), to: .opened(.normal)), .collapse)
    }

    func test_wingWidth_fitsWidestValue_andIsPixelAligned() {
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .stopwatch), 36)
        let text = WingLayout.textWidth("100 %")
        XCTAssertGreaterThanOrEqual(WingLayout.wingWidth(for: .charging), text + 2 * WingLayout.padding)
        let total = WingLayout.wingsWidth(for: .charging, scale: 2)
        XCTAssertEqual(total * 2, (total * 2).rounded())
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/NotchPresentationTests.swift && Tools/test.sh NotchPresentationTests`
Expected : échec de compilation, `cannot find type 'NotchPresentation' in scope`.

- [ ] **Step 2 : `WingLayout`**

`DynamicNotch/Shell/WingLayout.swift` :
```swift
//
//  WingLayout.swift
//  DynamicNotch
//
//  Largeur des ailes compactes. On mesure la valeur la plus large possible de
//  chaque activité (« 100 % », « 00:00 », …) avec la police des ailes : la
//  coque ne « respire » pas quand les chiffres changent, et le calcul est
//  déterministe (pas de boucle de layout).
//

import AppKit

enum WingLayout {
    /// Marge entre le bord extérieur de l'aile et son contenu.
    static let padding: CGFloat = 12
    static let iconWidth: CGFloat = 24
    static let minimumWing: CGFloat = 36
    /// Même police que `DS.Typography.wing`.
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    /// Valeur la plus large affichée dans l'aile droite, `nil` pour un graphisme.
    static func template(for id: ActivityID) -> String? {
        switch id {
        case .charging, .unplugged, .lowBattery: "100 %"
        case .stopwatch, .pomodoroPhase: "00:00"
        case .calendarSoon: "60 min"
        case .nowPlaying, .filesAdded, .airDropSent: nil
        }
    }

    static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Largeur d'UNE aile. Les deux ailes sont égales pour que la coque reste
    /// centrée sur l'encoche physique.
    static func wingWidth(for id: ActivityID) -> CGFloat {
        let leading = iconWidth + padding
        let trailing = template(for: id).map { textWidth($0) + 2 * padding } ?? leading
        return max(minimumWing, leading, trailing)
    }

    /// Largeur ajoutée à l'encoche par les deux ailes, alignée au pixel.
    static func wingsWidth(for id: ActivityID, scale: CGFloat) -> CGFloat {
        pixelAligned(2 * wingWidth(for: id), scale: scale)
    }
}
```

- [ ] **Step 3 : `NotchPresentation`**

`DynamicNotch/Shell/NotchPresentation.swift` :
```swift
//
//  NotchPresentation.swift
//  DynamicNotch
//
//  Machine d'états de la coque : l'encoche est toujours dans exactement un de
//  ces états. Chaque état donne une géométrie (`ShellMetrics`) ; chaque
//  transition donne un ressort (`DS.Motion.Kind`).
//

import CoreGraphics

enum NotchPresentation: Equatable {
    case closed
    case peek
    case compact(ActivityID)
    case expanded(ActivityID)
    case opened(NotchViewModel.ContentType)

    var isOpened: Bool {
        if case .opened = self { return true }
        return false
    }

    func metrics(notch: CGSize, hasHardwareNotch: Bool, scale: CGFloat) -> ShellMetrics {
        let ear: CGFloat = hasHardwareNotch ? 6 : 0
        let largeEar: CGFloat = hasHardwareNotch ? 10 : 0
        switch self {
        case .closed:
            return ShellMetrics(
                bodyWidth: notch.width, bodyHeight: notch.height, topRadius: ear,
                bottomRadius: hasHardwareNotch ? 10 : notch.height / 2, hasShadow: false
            )
        case .peek:
            let height = notch.height + 4
            return ShellMetrics(
                bodyWidth: notch.width + 12, bodyHeight: height, topRadius: ear,
                bottomRadius: hasHardwareNotch ? 12 : height / 2, hasShadow: false
            )
        case let .compact(id):
            return ShellMetrics(
                bodyWidth: notch.width + WingLayout.wingsWidth(for: id, scale: scale),
                bodyHeight: notch.height, topRadius: ear,
                bottomRadius: hasHardwareNotch ? 12 : notch.height / 2, hasShadow: false
            )
        case .expanded:
            return ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: largeEar, bottomRadius: 24, hasShadow: true)
        case let .opened(content):
            let size = content.panelSize
            return ShellMetrics(bodyWidth: size.width, bodyHeight: size.height, topRadius: largeEar, bottomRadius: 28, hasShadow: true)
        }
    }

    /// Plus l'état est « grand », plus la valeur est élevée.
    private var magnitude: Int {
        switch self {
        case .closed: 0
        case .peek: 10
        case .compact: 20
        case .expanded: 30
        case let .opened(content): 40 + content.rawValue
        }
    }

    /// Ressort d'une transition : grandir rebondit, rétrécir non.
    static func motion(from: NotchPresentation, to: NotchPresentation) -> DS.Motion.Kind {
        if (from == .closed && to == .peek) || (from == .peek && to == .closed) { return .micro }
        return to.magnitude >= from.magnitude ? .expand : .collapse
    }
}

struct ShellMetrics: Equatable {
    var bodyWidth: CGFloat
    var bodyHeight: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var hasShadow: Bool
}

extension NotchViewModel.ContentType {
    /// Taille du panneau ouvert selon le contenu.
    var panelSize: CGSize {
        switch self {
        case .normal: CGSize(width: 600, height: 180)
        case .menu: CGSize(width: 600, height: 200)
        case .settings: CGSize(width: 880, height: 560)
        }
    }
}
```

Run :
```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Shell/WingLayout.swift DynamicNotch/Shell/NotchPresentation.swift
Tools/test.sh NotchPresentationTests
```
Expected : `Executed 7 tests, with 0 failures`.

- [ ] **Step 4 : commit**

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: états de la coque, métriques et largeur des ailes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 9 : sources d'événements (chrono, Pomodoro, plateau, AirDrop)

**Files :**
- Modify : `DynamicNotch/Widgets/StopwatchWidget.swift` (modèle + vue), `DynamicNotch/Widgets/PomodoroWidget.swift` (modèle), `DynamicNotch/TrayDrop.swift:60-81`, `DynamicNotch/Share.swift`
- Create : `DynamicNotchTests/StopwatchModelTests.swift`, `DynamicNotchTests/PomodoroModelTests.swift`

**Interfaces :**
- Produces :
  - `StopwatchModel` : `init()` interne ; `@Published private(set) var running: Bool`, `accumulated: TimeInterval`, `startedAt: Date?` ; `func elapsed(at: Date = Date()) -> TimeInterval` ; `var elapsed: TimeInterval` ; `var hasTime: Bool` ; `func formatted(at: Date = Date()) -> String` ; `static func minutesSeconds(_: TimeInterval) -> String` ; `func toggle(at: Date = Date())` ; `func reset()`
  - `PomodoroModel` : `init()` interne ; `var onPhaseChange: ((_ phase: Phase, _ naturalEnd: Bool) -> Void)?` ; `Phase.activityTitle: String`
  - `TrayDrop.onItemsAdded: ((Int) -> Void)?` (appelé sur la file principale)
  - `Share.onAirDropSent: (() -> Void)?` (appelé sur la file principale)

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/StopwatchModelTests.swift` :
```swift
//
//  StopwatchModelTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class StopwatchModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    func test_elapsed_accumulatesAcrossPauses() {
        let model = StopwatchModel()
        model.toggle(at: t0)
        XCTAssertTrue(model.running)
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(5)), 5, accuracy: 0.001)
        model.toggle(at: t0.addingTimeInterval(5))
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(100)), 5, accuracy: 0.001)
        model.toggle(at: t0.addingTimeInterval(100))
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(102)), 7, accuracy: 0.001)
    }

    func test_reset() {
        let model = StopwatchModel()
        model.toggle(at: t0)
        model.reset()
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.hasTime)
        XCTAssertEqual(model.elapsed(at: t0.addingTimeInterval(10)), 0)
    }

    func test_formats() {
        XCTAssertEqual(StopwatchModel.minutesSeconds(65.9), "01:05")
        XCTAssertEqual(StopwatchModel.minutesSeconds(0), "00:00")
        let model = StopwatchModel()
        model.toggle(at: t0)
        XCTAssertEqual(model.formatted(at: t0.addingTimeInterval(61.25)), "01:01.25")
    }
}
```

`DynamicNotchTests/PomodoroModelTests.swift` :
```swift
//
//  PomodoroModelTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class PomodoroModelTests: XCTestCase {
    func test_skip_reportsPhaseChange_notNaturalEnd() {
        let model = PomodoroModel()
        var events: [(PomodoroModel.Phase, Bool)] = []
        model.onPhaseChange = { events.append(($0, $1)) }

        model.performPrimary()
        XCTAssertEqual(model.phase, .work)
        XCTAssertTrue(events.isEmpty, "démarrer n'est pas une fin de phase")

        model.skip()
        XCTAssertNotEqual(model.phase, .work)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.0, model.phase)
        XCTAssertEqual(events.first?.1, false)
        model.reset()
    }

    func test_activityTitles() {
        XCTAssertEqual(PomodoroModel.Phase.work.activityTitle, "Au travail")
        XCTAssertEqual(PomodoroModel.Phase.shortBreak.activityTitle, "Pause")
        XCTAssertEqual(PomodoroModel.Phase.longBreak.activityTitle, "Pause longue")
    }
}
```

Run :
```bash
ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/StopwatchModelTests.swift DynamicNotchTests/PomodoroModelTests.swift
Tools/test.sh StopwatchModelTests
```
Expected : échec de compilation (`'StopwatchModel' initializer is inaccessible due to 'private' protection level`, puis `toggle(at:)` inconnu).

- [ ] **Step 2 : chrono calculé à partir de dates**

Dans `DynamicNotch/Widgets/StopwatchWidget.swift`, remplacer toute la classe `StopwatchModel` par :

```swift
@MainActor
final class StopwatchModel: ObservableObject {
    static let shared = StopwatchModel()

    // Plus de minuterie : le temps écoulé est calculé à la demande à partir
    // de dates. Les vues qui l'affichent se rafraîchissent via TimelineView,
    // et seulement tant qu'elles sont à l'écran.
    @Published private(set) var running = false
    @Published private(set) var accumulated: TimeInterval = 0
    @Published private(set) var startedAt: Date?

    init() {}

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    var elapsed: TimeInterval { elapsed() }

    /// Vrai dès qu'il y a quelque chose à afficher (en cours ou en pause).
    var hasTime: Bool { running || accumulated > 0 }

    /// mm:ss.cc, pour le widget.
    func formatted(at date: Date = Date()) -> String {
        let total = max(0, elapsed(at: date))
        let cs = Int((total - floor(total)) * 100)
        return String(format: "%02d:%02d.%02d", Int(total) / 60, Int(total) % 60, cs)
    }

    /// mm:ss, pour l'aile.
    static func minutesSeconds(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func toggle(at date: Date = Date()) {
        if let startedAt {
            accumulated += max(0, date.timeIntervalSince(startedAt))
            self.startedAt = nil
            running = false
        } else {
            startedAt = date
            running = true
        }
    }

    func reset() {
        running = false
        startedAt = nil
        accumulated = 0
    }
}
```

Dans `StopwatchWidgetView.body`, remplacer le `Text(model.formatted)` et ses quatre modificateurs par :

```swift
            TimelineView(.periodic(from: .now, by: model.running ? 1.0 / 30 : 3600)) { context in
                Text(model.formatted(at: context.date))
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
```

et remplacer les deux occurrences de `model.elapsed == 0 && !model.running` par `!model.hasTime`.

Run : `Tools/test.sh StopwatchModelTests` → `Executed 3 tests, with 0 failures`.

- [ ] **Step 3 : Pomodoro publie ses fins de phase**

Dans `DynamicNotch/Widgets/PomodoroWidget.swift` :

1. Dans `enum Phase`, après `var tint: Color { … }`, ajouter :
```swift

        /// Titre de l'activité affichée à l'entrée dans la phase.
        var activityTitle: String {
            switch self {
            case .idle:       "Prêt"
            case .work:       "Au travail"
            case .shortBreak: "Pause"
            case .longBreak:  "Pause longue"
            }
        }
```
2. Remplacer `private init() {}` par :
```swift
    /// Appelé à chaque changement de phase ; `naturalEnd` vaut `false` quand
    /// l'utilisateur a passé la phase.
    var onPhaseChange: ((_ phase: Phase, _ naturalEnd: Bool) -> Void)?

    init() {}
```
3. Remplacer `func skip() { advancePhase() }` (corps compris) par :
```swift
    func skip() {
        advancePhase(naturalEnd: false)
    }
```
4. Dans `tick()`, remplacer `advancePhase()` par `advancePhase(naturalEnd: true)`.
5. Remplacer toute la fonction `advancePhase()` par :
```swift
    private func advancePhase(naturalEnd: Bool) {
        timer?.invalidate()
        timer = nil
        isRunning = false
        switch phase {
        case .work:
            sessionsCompleted += 1
            // max(1, …) : un réglage à 0 faisait planter le modulo.
            let next: Phase = (sessionsCompleted % max(1, cyclesBeforeLongBreak) == 0) ? .longBreak : .shortBreak
            transition(to: next)
        case .shortBreak, .longBreak:
            transition(to: .work)
        case .idle:
            return
        }
        onPhaseChange?(phase, naturalEnd)
    }
```

Run : `Tools/test.sh PomodoroModelTests` → `Executed 2 tests, with 0 failures`.

- [ ] **Step 4 : le plateau signale les fichiers ajoutés**

Dans `DynamicNotch/TrayDrop.swift`, après `@Published var isLoading: Int = 0`, ajouter :
```swift

    /// Appelé sur la file principale après un dépôt réussi, avec le nombre de fichiers.
    var onItemsAdded: ((Int) -> Void)?
```
Dans `load(_:)`, remplacer :
```swift
            DispatchQueue.main.async {
                items.forEach { self.items.updateOrInsert($0, at: 0) }
                self.isLoading -= 1
            }
```
par :
```swift
            DispatchQueue.main.async {
                items.forEach { self.items.updateOrInsert($0, at: 0) }
                self.isLoading -= 1
                self.onItemsAdded?(items.count)
            }
```

- [ ] **Step 5 : AirDrop confirme l'envoi**

Aujourd'hui l'objet `Share` n'est retenu par personne pendant l'envoi : son délégué (référence faible) n'est jamais appelé. Dans `DynamicNotch/Share.swift` :

1. Après `let serviceName: NSSharingService.Name?`, ajouter :
```swift

    /// Partages en cours, retenus jusqu'au retour du délégué.
    private static var inFlight: Set<Share> = []
    /// Appelé sur la file principale quand un envoi AirDrop a réussi.
    static var onAirDropSent: (() -> Void)?
```
2. Remplacer `func begin() { … }` par :
```swift
    func begin() {
        Share.inFlight.insert(self)
        do {
            try sendEx(files)
        } catch {
            Share.inFlight.remove(self)
            NSAlert.popError(error)
        }
    }

    func sharingService(_: NSSharingService, didShareItems _: [Any]) {
        if serviceName == .sendViaAirDrop { Share.onAirDropSent?() }
        Share.inFlight.remove(self)
    }

    func sharingService(_: NSSharingService, didFailToShareItems _: [Any], error _: Error) {
        Share.inFlight.remove(self)
    }
```
3. Dans la branche `else` de `sendEx` (sélecteur de partage), ajouter `Share.inFlight.remove(self)` en première ligne : ce chemin n'a pas de délégué.

- [ ] **Step 6 : tests, build, commit**

Run : `Tools/test.sh && Tools/build.sh` → `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: chrono sans minuterie, événements Pomodoro, plateau et AirDrop

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10 : réécriture de la coque

La tâche centrale : la fenêtre, le modèle, les événements et la vue passent sur `NotchGeometry` + `NotchPresentation` + `NotchShellShape`. Les ailes lisent `ActivityCenter` (qui n'est alimenté qu'à la tâche 11 : ici on vérifie fermé, aperçu, ouvert).

**Files :**
- Create : `DynamicNotch/Shell/BatteryGlyph.swift`, `DynamicNotch/Shell/ActivityViews.swift`
- Rewrite : `DynamicNotch/NotchView.swift`, `DynamicNotch/NotchViewModel+Events.swift`, `DynamicNotch/NotchWindowController.swift`
- Modify : `DynamicNotch/NotchViewModel.swift`, `DynamicNotch/NotchViewController.swift`, `DynamicNotch/AppDelegate.swift`, `DynamicNotch/AppSettings.swift:37-42`, `DynamicNotch/NotchSettingsView.swift`
- Delete : `DynamicNotch/NotchWingsView.swift`, `DynamicNotch/NotchShape.swift`

**Interfaces :**
- Consumes : `NotchGeometry` (3), `NotchShellShape` (4), `DS.Motion`/`DS.Typography` (5), `ActivityCenter`/`ActivityID`/`ActivityObservation` (6), `BatteryMonitor` (7), `NotchPresentation`/`ShellMetrics`/`WingLayout`/`ContentType.panelSize` (8), `StopwatchModel.elapsed(at:)`/`minutesSeconds`, `PomodoroModel.Phase.activityTitle` (9).
- Produces : `NotchViewModel` (`@MainActor`) : `init(geometry: NotchGeometry = .preview, activities: ActivityCenter = .shared)`, `presentation`, `geometry`, `metrics`, `deviceNotchRect`, `screenRect`, `hasHardwareNotch`, `inset`, `notchOpenedSize`, `notchOpenedRect`, `currentShellRect`, `contentType` (get/set), `restingPresentation`, `transition(to:)`, `notchOpen(_:)`, `notchClose()`, `notchPop()`, `showSettings()`, `activityDidChange()`, `handleMouseDown(at:)`, `handleMouseMove(to:)`, `destroy()`, `setPresentationForRendering(_:)` (Debug) ; `NotchWindowController(screen:geometry:openAfterCreate:)` ; `CompactActivityView`, `ExpandedActivityView`, `BatteryGlyph`, `AudioBars`.

Règle de compilation pour toute la tâche : si le compilateur signale un appel isolé au `MainActor` depuis une closure `DispatchQueue.main.async`/`asyncAfter`, entourer l'appel de `MainActor.assumeIsolated { … }`.

- [ ] **Step 1 : retirer les fichiers remplacés et le réglage d'opacité**

```bash
ruby Tools/xcproj.rb remove DynamicNotch/NotchWingsView.swift DynamicNotch/NotchShape.swift
git rm -q DynamicNotch/NotchWingsView.swift DynamicNotch/NotchShape.swift
grep -n "appearanceSection\|notchOpacity" DynamicNotch/NotchSettingsView.swift DynamicNotch/AppSettings.swift
```
Puis :
- `AppSettings.swift` : supprimer la propriété `notchOpacity` et son commentaire, ainsi que le `// MARK: appearance` devenu vide ;
- `NotchSettingsView.swift` : supprimer la ligne qui appelle `appearanceSection`, la propriété `appearanceSection` entière (du `// MARK: appearance` à son accolade fermante) et la ligne `settings.notchOpacity = 1.0` de `confirmAndReset()`.

Vérifier : `grep -rn "notchOpacity\|appearanceSection" DynamicNotch` → aucune sortie.

- [ ] **Step 2 : `BatteryGlyph`**

`DynamicNotch/Shell/BatteryGlyph.swift` :
```swift
//
//  BatteryGlyph.swift
//  DynamicNotch
//
//  Glyphe batterie dessiné, redimensionnable (22 pt dans l'aile, 44 pt dans
//  l'état étendu). Hauteur arrondie au point, trait de 1 ou 2 pt : net à
//  toutes les tailles.
//

import SwiftUI

struct BatteryGlyph: View {
    let level: Double
    let tint: Color
    let isCharging: Bool
    var width: CGFloat = 22

    var body: some View {
        let height = (width / 2).rounded()
        let stroke: CGFloat = width >= 40 ? 2 : 1
        let inset = stroke + 1
        let corner = height * 0.3
        HStack(spacing: max(1, (width * 0.05).rounded())) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: stroke)
                RoundedRectangle(cornerRadius: max(1, corner - inset), style: .continuous)
                    .fill(tint)
                    .frame(width: max(0, (width - 2 * inset) * min(1, max(0, level))))
                    .padding(inset)
            }
            .frame(width: width, height: height)
            .overlay {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.8, weight: .bold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.7), radius: 0.5)
                }
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .frame(width: max(1.5, (width * 0.07).rounded()), height: (height * 0.4).rounded())
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 3 : vues d'activité**

`DynamicNotch/Shell/ActivityViews.swift` :
```swift
//
//  ActivityViews.swift
//  DynamicNotch
//
//  Contenu des ailes (compact) et de l'état étendu, par activité. Chaque vue
//  n'observe que SON modèle : un chrono qui tourne ne fait plus recalculer
//  toute l'encoche.
//

import EventKit
import SwiftUI

enum ActivityPlace {
    case compactLeading
    case compactTrailing
    case expanded
}

/// Ailes compactes, de part et d'autre de l'encoche physique.
struct CompactActivityView: View {
    let id: ActivityID
    let notchWidth: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        let wing = WingLayout.wingWidth(for: id)
        HStack(spacing: 0) {
            ActivitySlot(id: id, place: .compactLeading, namespace: namespace)
                .frame(width: wing - WingLayout.padding, alignment: .leading)
                .padding(.leading, WingLayout.padding)
            Spacer(minLength: notchWidth)
            ActivitySlot(id: id, place: .compactTrailing, namespace: namespace)
                .frame(width: wing - WingLayout.padding, alignment: .trailing)
                .padding(.trailing, WingLayout.padding)
        }
        .font(DS.Typography.wing)
        .foregroundStyle(DS.Color.textPrimary)
    }
}

/// État étendu : une ligne sous l'encoche (icône, titre, valeur).
struct ExpandedActivityView: View {
    let id: ActivityID
    let notchHeight: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: notchHeight)
            ActivitySlot(id: id, place: .expanded, namespace: namespace)
                .frame(height: 36)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .foregroundStyle(DS.Color.textPrimary)
    }
}

/// Barres audio animées tant que la lecture est en cours.
struct AudioBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0 ..< 4, id: \.self) { index in
                    Capsule()
                        .fill(DS.Color.textPrimary)
                        .frame(
                            width: 2.5,
                            height: isPlaying ? 4 + 8 * abs(sin(t * (5 + Double(index)) + Double(index) * 1.3)) : 3
                        )
                }
            }
            .frame(width: 18, height: 14)
        }
    }
}

// MARK: - Aiguillage

private struct ActivitySlot: View {
    let id: ActivityID
    let place: ActivityPlace
    let namespace: Namespace.ID

    var body: some View {
        switch id {
        case .charging, .unplugged, .lowBattery:
            BatteryActivity(id: id, place: place, namespace: namespace)
        case .pomodoroPhase:
            PomodoroActivity(place: place, namespace: namespace)
        case .stopwatch:
            StopwatchActivity(place: place)
        case .nowPlaying:
            NowPlayingActivity(place: place, namespace: namespace)
        case .calendarSoon:
            CalendarActivity(place: place)
        case let .filesAdded(count):
            ConfirmationActivity(
                place: place, systemImage: "checkmark.circle.fill", tint: DS.Color.success,
                title: count > 1 ? "\(count) fichiers ajoutés" : "1 fichier ajouté"
            )
        case .airDropSent:
            ConfirmationActivity(
                place: place, systemImage: "checkmark.circle.fill", tint: DS.Color.info,
                title: "Envoyé via AirDrop"
            )
        }
    }
}

/// Ligne standard de l'état étendu.
private struct ActivityRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DS.Typography.activityTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typography.activitySubtitle)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
    }
}

// MARK: - Batterie

private struct BatteryActivity: View {
    let id: ActivityID
    let place: ActivityPlace
    let namespace: Namespace.ID
    @ObservedObject private var battery = BatteryMonitor.shared

    private var isLow: Bool {
        if case .lowBattery = id { return true }
        return false
    }

    private var tint: Color {
        if isLow { return DS.Color.destructive }
        return battery.isPluggedIn ? DS.Color.success : battery.indicativeTint
    }

    private var valueColor: Color {
        if isLow { return DS.Color.destructive }
        return battery.isPluggedIn ? DS.Color.success : DS.Color.textPrimary
    }

    private var title: String {
        switch id {
        case .charging: "En charge"
        case .unplugged: "Sur batterie"
        default: "Batterie faible"
        }
    }

    var body: some View {
        switch place {
        case .compactLeading:
            glyph(width: 22)
        case .compactTrailing:
            percent.foregroundStyle(valueColor)
        case .expanded:
            ActivityRow(title: title, subtitle: id == .charging ? battery.timeToFullText : nil) {
                glyph(width: 44)
            } trailing: {
                percent
                    .font(DS.Typography.activityValue)
                    .foregroundStyle(valueColor)
            }
        }
    }

    private func glyph(width: CGFloat) -> some View {
        BatteryGlyph(level: battery.level, tint: tint, isCharging: battery.isCharging, width: width)
            .matchedGeometryEffect(id: "battery", in: namespace)
    }

    private var percent: some View {
        Text("\(battery.percent) %")
            .contentTransition(.numericText(value: Double(battery.percent)))
    }
}

// MARK: - Pomodoro

private struct PomodoroActivity: View {
    let place: ActivityPlace
    let namespace: Namespace.ID
    @ObservedObject private var model = PomodoroModel.shared

    var body: some View {
        switch place {
        case .compactLeading:
            dot(size: 8)
        case .compactTrailing:
            remaining
        case .expanded:
            ActivityRow(title: model.phase.activityTitle, subtitle: "\(Int(model.phaseTotal / 60)) min") {
                dot(size: 14)
            } trailing: {
                remaining.font(DS.Typography.activityValue)
            }
        }
    }

    private func dot(size: CGFloat) -> some View {
        Circle()
            .fill(model.phase.tint)
            .frame(width: size, height: size)
            .matchedGeometryEffect(id: "pomodoro", in: namespace)
    }

    private var remaining: some View {
        Text(model.formatted).contentTransition(.numericText(countsDown: true))
    }
}

// MARK: - Chrono

private struct StopwatchActivity: View {
    let place: ActivityPlace
    @ObservedObject private var model = StopwatchModel.shared

    var body: some View {
        switch place {
        case .compactLeading:
            Image(systemName: "stopwatch")
        case .compactTrailing:
            time
        case .expanded:
            ActivityRow(title: "Chrono") {
                Image(systemName: "stopwatch").font(.system(size: 20, weight: .semibold))
            } trailing: {
                time.font(DS.Typography.activityValue)
            }
        }
    }

    private var time: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(StopwatchModel.minutesSeconds(model.elapsed(at: context.date)))
        }
    }
}

// MARK: - Musique

private struct NowPlayingActivity: View {
    let place: ActivityPlace
    let namespace: Namespace.ID
    @ObservedObject private var player = NowPlayingManager.shared

    var body: some View {
        switch place {
        case .compactLeading:
            artwork(size: 20)
        case .compactTrailing:
            AudioBars(isPlaying: player.isPlaying)
        case .expanded:
            ActivityRow(
                title: player.title.isEmpty ? "Lecture en cours" : player.title,
                subtitle: player.artist.isEmpty ? nil : player.artist
            ) {
                artwork(size: 36)
            } trailing: {
                AudioBars(isPlaying: player.isPlaying)
            }
        }
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let image = player.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    DS.Color.surfaceRaisedStrong
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .matchedGeometryEffect(id: "artwork", in: namespace)
    }
}

// MARK: - Calendrier

private struct CalendarActivity: View {
    let place: ActivityPlace
    @ObservedObject private var store = CalendarStore.shared

    var body: some View {
        switch place {
        case .compactLeading:
            Image(systemName: "calendar")
        case .compactTrailing:
            countdown
        case .expanded:
            ActivityRow(title: store.nextEvent?.title ?? "Événement", subtitle: "Bientôt") {
                Image(systemName: "calendar").font(.system(size: 20, weight: .semibold))
            } trailing: {
                countdown.font(DS.Typography.activityValue)
            }
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minutes = store.nextEvent.map { max(0, Int(ceil($0.startDate.timeIntervalSince(context.date) / 60))) } ?? 0
            Text("\(minutes) min")
        }
    }
}

// MARK: - Confirmations (fichiers, AirDrop)

private struct ConfirmationActivity: View {
    let place: ActivityPlace
    let systemImage: String
    let tint: Color
    let title: String

    var body: some View {
        switch place {
        case .compactLeading:
            Image(systemName: systemImage).foregroundStyle(tint)
        case .compactTrailing:
            EmptyView()
        case .expanded:
            ActivityRow(title: title) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
            } trailing: {
                EmptyView()
            }
        }
    }
}
```

- [ ] **Step 4 : `NotchViewModel` sur la machine d'états**

Dans `DynamicNotch/NotchViewModel.swift` :

(a) Remplacer le début de la classe, de `class NotchViewModel: NSObject, ObservableObject {` jusqu'à la fin de `let animation: Animation = .interactiveSpring( … )` inclus, par :

```swift
@MainActor
final class NotchViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []
    /// Abonnement à `ActivityCenter`, posé par `setupCancellables()`.
    var activityObservation: ActivityObservation?
    let activities: ActivityCenter
    private var isSuspendingActivities = false

    init(geometry: NotchGeometry = .preview, activities: ActivityCenter = .shared) {
        self.geometry = geometry
        self.activities = activities
        super.init()
        setupCancellables()
    }

    /// Ressort des animations internes aux widgets.
    let animation: Animation = DS.Motion.expand
```

(b) Remplacer le bloc qui va de `    /// Logical size of the opened panel` jusqu'à `    @Published var notchVisible: Bool = true` inclus par :

```swift
    let dropDetectorRange: CGFloat = 32

    enum OpenReason: String, Codable, Hashable, Equatable {
        case click
        case drag
        case boot
        case unknown
    }

    enum ContentType: Int, Codable, Hashable, Equatable {
        case normal
        case menu
        case settings
    }

    @Published private(set) var presentation: NotchPresentation = .closed
    @Published var geometry: NotchGeometry
    @Published var openReason: OpenReason = .unknown
    @Published var spacing: CGFloat = 16
    @Published var optionKeyPressed: Bool = false

    // MARK: géométrie (coordonnées écran AppKit)

    var deviceNotchRect: CGRect { geometry.notchRect }
    var screenRect: CGRect { geometry.screen.frame }
    var hasHardwareNotch: Bool { geometry.hasHardwareNotch }
    /// Marge de survol et de clic : élargie de 4 pt autour d'une vraie encoche.
    var inset: CGFloat { hasHardwareNotch ? -4 : 0 }

    var metrics: ShellMetrics {
        presentation.metrics(notch: deviceNotchRect.size, hasHardwareNotch: hasHardwareNotch, scale: geometry.screen.scale)
    }

    var notchOpenedSize: CGSize { contentType.panelSize }

    var notchOpenedRect: CGRect {
        let size = notchOpenedSize
        return CGRect(x: deviceNotchRect.midX - size.width / 2, y: screenRect.maxY - size.height, width: size.width, height: size.height)
    }

    /// Rectangle de la coque dans son état courant.
    var currentShellRect: CGRect {
        let m = metrics
        return CGRect(x: deviceNotchRect.midX - m.bodyWidth / 2, y: screenRect.maxY - m.bodyHeight, width: m.bodyWidth, height: m.bodyHeight)
    }
```

(c) Remplacer tout ce qui suit `let hapticSender = PassthroughSubject<Void, Never>()` (de `func notchOpen` jusqu'à l'accolade fermante de la classe incluse) par :

```swift

    // MARK: états

    /// Contenu du panneau ouvert. L'écrire hors de l'état ouvert est sans effet.
    var contentType: ContentType {
        get {
            if case let .opened(content) = presentation { return content }
            return .normal
        }
        set {
            guard presentation.isOpened else { return }
            transition(to: .opened(newValue))
        }
    }

    /// État de repos : l'activité en cours, sinon l'encoche nue.
    var restingPresentation: NotchPresentation {
        guard let display = activities.current else { return .closed }
        return display.mode == .expanded ? .expanded(display.id) : .compact(display.id)
    }

    /// Seul point d'entrée des changements d'état : choisit le ressort.
    func transition(to next: NotchPresentation) {
        guard next != presentation else { return }
        let kind = NotchPresentation.motion(from: presentation, to: next)
        withAnimation(DS.Motion.animation(kind)) {
            presentation = next
        }
    }

    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        if !isSuspendingActivities {
            isSuspendingActivities = true
            activities.beginSuspension()
        }
        transition(to: .opened(.normal))
        // Ne voler le focus que sur un clic explicite (pas pendant un
        // glisser-déposer depuis une autre app, ni au lancement).
        if reason == .click {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func notchClose() {
        openReason = .unknown
        if isSuspendingActivities {
            isSuspendingActivities = false
            activities.endSuspension()
        }
        transition(to: restingPresentation)
    }

    func notchPop() {
        guard presentation == .closed else { return }
        transition(to: .peek)
    }

    func showSettings() {
        transition(to: .opened(.settings))
    }

    /// Appelé par `ActivityCenter` : le panneau ouvert et l'aperçu ne sont pas interrompus.
    func activityDidChange() {
        guard !presentation.isOpened, presentation != .peek else { return }
        transition(to: restingPresentation)
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        activityObservation?.cancel()
        activityObservation = nil
        if isSuspendingActivities {
            isSuspendingActivities = false
            activities.endSuspension()
        }
    }

    #if DEBUG
        /// Rendu PNG des états (DebugTools) : pose un état sans animation.
        func setPresentationForRendering(_ state: NotchPresentation) {
            presentation = state
        }
    #endif
}
```

- [ ] **Step 5 : événements**

Remplacer tout `DynamicNotch/NotchViewModel+Events.swift` par :

```swift
//
//  NotchViewModel+Events.swift
//  DynamicNotch
//

import Cocoa
import Combine
import Foundation
import SwiftUI

extension NotchViewModel {
    func setupCancellables() {
        let events = EventMonitors.shared

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMouseDown(at: NSEvent.mouseLocation) }
            .store(in: &cancellables)

        events.optionKeyPress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pressed in self?.optionKeyPressed = pressed }
            .store(in: &cancellables)

        // Le système émet mouseMoved à la fréquence d'affichage : 60 Hz suffisent
        // pour détecter l'entrée et la sortie de l'encoche.
        events.mouseLocation
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.handleMouseMove(to: NSEvent.mouseLocation) }
            .store(in: &cancellables)

        $presentation
            .filter { $0 == .peek }
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard NSEvent.pressedMouseButtons == 0 else { return }
                self?.hapticSender.send()
            }
            .store(in: &cancellables)

        hapticSender
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] _ in
                guard self?.hapticFeedback ?? false else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            .store(in: &cancellables)

        $selectedLanguage
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                self?.notchClose()
                output.apply()
            }
            .store(in: &cancellables)

        // Échap ferme le panneau (désactivable dans les réglages).
        events.escapePressed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, presentation.isOpened, AppSettings.shared.escClosesNotch else { return }
                notchClose()
            }
            .store(in: &cancellables)

        activityObservation = activities.observe { [weak self] _ in
            self?.activityDidChange()
        }
    }

    func handleMouseDown(at point: NSPoint) {
        if presentation.isOpened {
            // Clic hors du panneau, ou sur l'encoche elle-même → fermer.
            if !notchOpenedRect.contains(point) || deviceNotchRect.insetBy(dx: inset, dy: inset).contains(point) {
                notchClose()
            }
        } else if currentShellRect.insetBy(dx: inset, dy: inset).contains(point) {
            notchOpen(.click)
        }
    }

    func handleMouseMove(to point: NSPoint) {
        guard AppSettings.shared.popOnHoverEnabled else { return }
        let inside = deviceNotchRect.insetBy(dx: inset, dy: inset).contains(point)
        if presentation == .closed, inside { notchPop() }
        if presentation == .peek, !inside { notchClose() }
    }
}
```

- [ ] **Step 6 : `NotchView`**

Remplacer tout `DynamicNotch/NotchView.swift` par :

```swift
//
//  NotchView.swift
//  DynamicNotch
//
//  Racine SwiftUI d'une fenêtre d'encoche. La coque est UNE forme animée
//  (`NotchShellShape`) dessinée dans le canevas fixe de la fenêtre ; le
//  contenu (ailes, activité étendue, panneau) est masqué par cette même
//  forme, donc il ne déborde jamais pendant les animations.
//

import SwiftUI

struct NotchView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject private var tray = TrayDrop.shared
    @Namespace private var activityNamespace
    @State private var dropTargeting = false

    /// Le contenu arrive après la coque et part avant elle.
    private static let contentTransition: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .offset(y: -6)).animation(DS.Motion.expand.delay(0.08)),
        removal: .opacity.animation(.easeOut(duration: 0.12))
    )

    private var centerX: CGFloat { vm.geometry.notchCenterXInWindow }

    private func shape(_ m: ShellMetrics) -> NotchShellShape {
        NotchShellShape(
            centerX: centerX, bodyWidth: m.bodyWidth, bodyHeight: m.bodyHeight,
            topRadius: m.topRadius, bottomRadius: m.bottomRadius
        )
    }

    var body: some View {
        let metrics = vm.metrics
        ZStack(alignment: .topLeading) {
            dragDetector(metrics)
            shape(metrics)
                .fill(Color.black)
                .shadow(color: .black.opacity(metrics.hasShadow ? 0.35 : 0), radius: 10, y: 4)
            content
                .frame(width: metrics.bodyWidth, height: metrics.bodyHeight, alignment: .top)
                .position(x: centerX, y: metrics.bodyHeight / 2)
                .mask(shape(metrics))
            closedBadge
        }
        .frame(
            width: NotchGeometry.windowSize.width,
            height: NotchGeometry.windowSize.height,
            alignment: .topLeading
        )
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.presentation {
        case .closed, .peek:
            Color.clear
        case let .compact(id):
            CompactActivityView(id: id, notchWidth: vm.deviceNotchRect.width, namespace: activityNamespace)
                .frame(height: vm.deviceNotchRect.height)
                .id(id)
                .transition(Self.contentTransition)
        case let .expanded(id):
            ExpandedActivityView(id: id, notchHeight: vm.deviceNotchRect.height, namespace: activityNamespace)
                .id(id)
                .transition(Self.contentTransition)
        case .opened:
            openedPanel
                .transition(Self.contentTransition)
        }
    }

    private var openedPanel: some View {
        VStack(spacing: vm.spacing) {
            NotchHeaderView(vm: vm)
            NotchContentView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Le header reste collé en haut quel que soit le contenu de la page.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(vm.spacing)
    }

    /// Pastille du nombre de fichiers en attente, à droite de l'encoche fermée.
    @ViewBuilder
    private var closedBadge: some View {
        if vm.presentation == .closed, !tray.items.isEmpty {
            DSBadge(count: tray.items.count, tone: .brand)
                .accessibilityLabel(Text("\(tray.items.count) fichier(s) en attente"))
                .position(x: centerX + vm.deviceNotchRect.width / 2 + 18, y: vm.deviceNotchRect.height / 2)
                .transition(.opacity)
        }
    }

    /// Zone de dépôt autour de la coque. L'alpha non nul est nécessaire au
    /// hit-test SwiftUI ; `.position` vient en dernier pour que seule cette
    /// zone (et non toute la fenêtre) reçoive les dépôts.
    private func dragDetector(_ metrics: ShellMetrics) -> some View {
        let width = metrics.bodyWidth + vm.dropDetectorRange
        let height = metrics.bodyHeight + vm.dropDetectorRange
        return Color.black.opacity(0.001)
            .frame(width: width, height: height)
            .accessibilityLabel(Text("DynamicNotch. Glissez des fichiers ou cliquez pour ouvrir le panneau."))
            .accessibilityAddTraits(.isButton)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) { _, targeted in
                if targeted, !vm.presentation.isOpened {
                    vm.notchOpen(.drag)
                    vm.hapticSender.send()
                } else if !targeted,
                          !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(NSEvent.mouseLocation)
                {
                    vm.notchClose()
                }
            }
            .position(x: centerX, y: height / 2)
    }
}
```

- [ ] **Step 7 : fenêtre et contrôleurs**

Remplacer tout `DynamicNotch/NotchWindowController.swift` par :

```swift
//
//  NotchWindowController.swift
//  DynamicNotch
//
//  Une fenêtre par écran, de taille fixe (NotchGeometry.windowSize), collée
//  en haut de l'écran et centrée sur l'encoche au pixel près. Transparente :
//  les clics hors de la coque traversent vers les fenêtres du dessous.
//

import Cocoa

class NotchWindowController: NSWindowController {
    var vm: NotchViewModel?
    weak var screen: NSScreen?

    init(screen: NSScreen, geometry: NotchGeometry, openAfterCreate: Bool) {
        self.screen = screen
        let window = NotchWindow(
            contentRect: geometry.windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init(window: window)

        let vm = NotchViewModel(geometry: geometry)
        self.vm = vm
        contentViewController = NotchViewController(vm)
        // Cadre en coordonnées globales, déjà aligné au pixel.
        window.setFrame(geometry.windowFrame, display: true)
        window.makeKeyAndOrderFront(nil)

        guard openAfterCreate else { return }
        Task { @MainActor [weak vm] in
            vm?.notchOpen(.boot)
            // Argument Debug pour les captures : `--initial-view settings|menu|normal`.
            if let index = CommandLine.arguments.firstIndex(of: "--initial-view"),
               index + 1 < CommandLine.arguments.count
            {
                switch CommandLine.arguments[index + 1] {
                case "settings": vm?.contentType = .settings
                case "menu": vm?.contentType = .menu
                default: break
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    func destroy() {
        vm?.destroy()
        vm = nil
        window?.close()
        contentViewController = nil
        window = nil
    }
}
```

Dans `DynamicNotch/NotchViewController.swift`, remplacer `super.init(rootView: .init(vm: vm))` par :

```swift
        super.init(rootView: .init(vm: vm))
        // La fenêtre a une taille fixe : SwiftUI ne doit pas la redimensionner.
        sizingOptions = []
```

- [ ] **Step 8 : `AppDelegate` ne reconstruit que si l'écran a changé**

Dans `DynamicNotch/AppDelegate.swift` :

1. Après `private var settingsObservers: Set<AnyCancellable> = []`, ajouter :
```swift
    /// Configuration d'écrans des fenêtres actuelles : on ne reconstruit que si elle change.
    private var lastLayout: WindowLayout?

    private struct WindowLayout: Equatable {
        let screens: [ScreenDescriptor]
        let forcePill: Bool
    }
```
2. Dans `applicationDidFinishLaunching`, remplacer `selector: #selector(rebuildApplicationWindows),` par `selector: #selector(screenParametersChanged),`.
3. Remplacer le bloc `Publishers.CombineLatest( … ).store(in: &settingsObservers)` par :
```swift
        Publishers.CombineLatest3(
            AppSettings.shared.$displayPreference.removeDuplicates(),
            AppSettings.shared.$showOnAllScreens.removeDuplicates(),
            AppSettings.shared.$forcePillMode.removeDuplicates()
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            Log.app.info("display setting changed, rebuilding windows")
            self?.rebuildApplicationWindows(force: true)
        }
        .store(in: &settingsObservers)
```
4. Remplacer l'appel final `rebuildApplicationWindows()` de `applicationDidFinishLaunching` par `rebuildApplicationWindows(force: true)`.
5. Remplacer toute la fonction `@objc func rebuildApplicationWindows() { … }` par :
```swift
    @objc func screenParametersChanged() {
        rebuildApplicationWindows(force: false)
    }

    /// Reconstruit les fenêtres si la configuration d'écrans a changé (ou si `force`).
    /// `didChangeScreenParametersNotification` arrive souvent sans changement réel :
    /// reconstruire à chaque fois provoquait un flash et perdait l'état.
    func rebuildApplicationWindows(force: Bool) {
        let screens: [NSScreen]
        if AppSettings.shared.showOnAllScreens {
            screens = NSScreen.screens
        } else if let one = findScreenFitsOurNeeds() {
            screens = [one]
        } else {
            screens = []
        }
        let forcePill = AppSettings.shared.forcePillMode
        let layout = WindowLayout(screens: screens.map { ScreenDescriptor($0) }, forcePill: forcePill)
        guard force || layout != lastLayout else { return }
        lastLayout = layout
        defer { isFirstOpen = false }

        windowControllers.forEach { $0.destroy() }
        windowControllers.removeAll()

        let shouldOpen = isFirstOpen && !isLaunchedAtLogin
        for (index, screen) in screens.enumerated() {
            // Ouverture au lancement sur le premier écran seulement.
            let geometry = NotchGeometry(screen: ScreenDescriptor(screen), forcePill: forcePill)
            windowControllers.append(NotchWindowController(
                screen: screen,
                geometry: geometry,
                openAfterCreate: shouldOpen && index == 0
            ))
        }
        Log.app.info("rebuilt \(self.windowControllers.count) notch window(s)")
    }
```
6. Supprimer le doublon `import Combine` en fin de fichier.

- [ ] **Step 9 : build, tests, vérification manuelle, commit**

```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Shell/BatteryGlyph.swift DynamicNotch/Shell/ActivityViews.swift
Tools/build.sh && Tools/test.sh
```
Expected : `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`. Corriger toute erreur de compilation en restant dans les interfaces ci-dessus (voir la règle `MainActor.assumeIsolated`).

Vérification manuelle (Release) : `pkill -x DynamicNotch; open build/Build/Products/Release/DynamicNotch.app`, puis contrôler :
1. Fermée : la coque se confond avec l'encoche physique, sans liseré ni décalage.
2. Survol : l'encoche gonfle légèrement (ressort `micro`), avec un retour haptique.
3. Clic : le panneau s'ouvre en rebondissant légèrement, le contenu arrive après la coque.
4. Clic à l'extérieur : fermeture sans rebond.
5. Menu puis Réglages : le panneau s'agrandit avec le même ressort, le texte reste net pendant l'animation.
6. Glisser un fichier sur l'encoche : le panneau s'ouvre, le dépôt dans « Fichiers » fonctionne.

```bash
git add -A DynamicNotch DynamicNotch.xcodeproj
git commit -m "feat: coque réécrite sur la géométrie, la machine d'états et la forme unique

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11 : câblage des activités

**Files :**
- Create : `DynamicNotch/Activities/ActivityWiring.swift`, `DynamicNotchTests/ActivityWiringTests.swift`
- Modify : `DynamicNotch/AppDelegate.swift` (ligne `_ = BatteryMonitor.shared`)

**Interfaces :**
- Consumes : `ActivityCenter` (6), `BatteryMonitor.onChange`/`PowerEvent` (7), `PomodoroModel.onPhaseChange`, `StopwatchModel.hasTime`, `TrayDrop.onItemsAdded`, `Share.onAirDropSent` (9), `AppSettings` (`wingsEnabled`, `wingBattery`, `wingStopwatch`, `wingPomodoro`, `wingCalendar`).
- Produces : `@MainActor final class ActivityWiring { static let shared; init(center:); func install(); func reevaluate(); struct Inputs; static func activePersistent(_ inputs: Inputs) -> Set<ActivityID>; static let persistentIDs: [ActivityID]; static func activity(for: PowerEvent) -> ActivityID }`

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/ActivityWiringTests.swift` :
```swift
//
//  ActivityWiringTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class ActivityWiringTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func inputs(
        wings: Bool = true,
        plugged: Bool = false,
        hasBattery: Bool = true,
        stopwatch: Bool = false,
        pomodoro: Bool = false,
        music: Bool = false,
        eventIn minutes: Double? = nil
    ) -> ActivityWiring.Inputs {
        ActivityWiring.Inputs(
            wingsEnabled: wings, wingBattery: true, wingStopwatch: true, wingPomodoro: true, wingCalendar: true,
            battery: PowerSnapshot(hasBattery: hasBattery, level: 0.5, isPluggedIn: plugged, isCharging: plugged, minutesToFull: nil),
            stopwatchHasTime: stopwatch, pomodoroActive: pomodoro, musicPlaying: music,
            nextEventStart: minutes.map { now.addingTimeInterval($0 * 60) }, now: now
        )
    }

    func test_nothingActive() {
        XCTAssertEqual(ActivityWiring.activePersistent(inputs()), [])
    }

    func test_charging_onlyWithBattery() {
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(plugged: true)), [.charging])
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(plugged: true, hasBattery: false)), [])
    }

    func test_wingsDisabled_disablesEverything() {
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(wings: false, plugged: true, stopwatch: true, music: true)), [])
    }

    func test_timersAndMusic() {
        XCTAssertEqual(
            ActivityWiring.activePersistent(inputs(stopwatch: true, pomodoro: true, music: true)),
            [.stopwatch, .pomodoroPhase, .nowPlaying]
        )
    }

    func test_calendar_withinTheHourOnly() {
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(eventIn: 30)), [.calendarSoon])
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(eventIn: 90)), [])
        XCTAssertEqual(ActivityWiring.activePersistent(inputs(eventIn: -5)), [])
    }

    func test_powerEventMapping() {
        XCTAssertEqual(ActivityWiring.activity(for: .pluggedIn), .charging)
        XCTAssertEqual(ActivityWiring.activity(for: .unplugged), .unplugged)
        XCTAssertEqual(ActivityWiring.activity(for: .lowBattery(percent: 10)), .lowBattery(percent: 10))
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/ActivityWiringTests.swift && Tools/test.sh ActivityWiringTests`
Expected : échec de compilation, `cannot find 'ActivityWiring' in scope`.

- [ ] **Step 2 : implémenter**

`DynamicNotch/Activities/ActivityWiring.swift` :
```swift
//
//  ActivityWiring.swift
//  DynamicNotch
//
//  Branche les sources (batterie, Pomodoro, chrono, plateau, AirDrop,
//  calendrier) sur ActivityCenter. Les événements ponctuels sont postés tels
//  quels ; l'état persistant est recalculé à chaque changement d'une source
//  ou d'un réglage, et toutes les 30 s (décompte du calendrier).
//

import AppKit
import Combine

@MainActor
final class ActivityWiring {
    static let shared = ActivityWiring()

    /// Tout ce dont dépend l'état persistant, à un instant donné.
    struct Inputs {
        var wingsEnabled: Bool
        var wingBattery: Bool
        var wingStopwatch: Bool
        var wingPomodoro: Bool
        var wingCalendar: Bool
        var battery: PowerSnapshot
        var stopwatchHasTime: Bool
        var pomodoroActive: Bool
        var musicPlaying: Bool
        var nextEventStart: Date?
        var now: Date
    }

    static let persistentIDs: [ActivityID] = [.charging, .stopwatch, .pomodoroPhase, .nowPlaying, .calendarSoon]

    static func activePersistent(_ inputs: Inputs) -> Set<ActivityID> {
        guard inputs.wingsEnabled else { return [] }
        var active: Set<ActivityID> = []
        if inputs.wingBattery, inputs.battery.hasBattery, inputs.battery.isPluggedIn { active.insert(.charging) }
        if inputs.wingStopwatch, inputs.stopwatchHasTime { active.insert(.stopwatch) }
        if inputs.wingPomodoro, inputs.pomodoroActive { active.insert(.pomodoroPhase) }
        if inputs.musicPlaying { active.insert(.nowPlaying) }
        if inputs.wingCalendar, let start = inputs.nextEventStart {
            let delay = start.timeIntervalSince(inputs.now)
            if delay > 0, delay < 60 * 60 { active.insert(.calendarSoon) }
        }
        return active
    }

    static func activity(for event: PowerEvent) -> ActivityID {
        switch event {
        case .pluggedIn: .charging
        case .unplugged: .unplugged
        case let .lowBattery(percent): .lowBattery(percent: percent)
        }
    }

    private let center: ActivityCenter
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    init(center: ActivityCenter = .shared) {
        self.center = center
    }

    func install() {
        BatteryMonitor.shared.onChange = { [weak self] _, events in
            guard let self else { return }
            for event in events {
                center.post(Self.activity(for: event))
            }
            reevaluate()
        }
        PomodoroModel.shared.onPhaseChange = { [weak self] _, naturalEnd in
            if naturalEnd { NSSound(named: "Glass")?.play() }
            self?.center.post(.pomodoroPhase)
        }
        TrayDrop.shared.onItemsAdded = { [weak self] count in
            MainActor.assumeIsolated { self?.center.post(.filesAdded(count: count)) }
        }
        Share.onAirDropSent = { [weak self] in
            MainActor.assumeIsolated { self?.center.post(.airDropSent) }
        }

        let settings = AppSettings.shared
        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$wingsEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingBattery.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingStopwatch.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingPomodoro.map { _ in () }.eraseToAnyPublisher(),
            settings.$wingCalendar.map { _ in () }.eraseToAnyPublisher(),
            PomodoroModel.shared.$phase.map { _ in () }.eraseToAnyPublisher(),
            StopwatchModel.shared.$running.map { _ in () }.eraseToAnyPublisher(),
            StopwatchModel.shared.$accumulated.map { _ in () }.eraseToAnyPublisher(),
            NowPlayingManager.shared.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            CalendarStore.shared.$nextEvent.map { _ in () }.eraseToAnyPublisher(),
        ]
        // receive(on:) : @Published émet avant l'écriture, on relit après.
        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reevaluate() }
            .store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluate() }
        }
        reevaluate()
    }

    func reevaluate() {
        let settings = AppSettings.shared
        let inputs = Inputs(
            wingsEnabled: settings.wingsEnabled,
            wingBattery: settings.wingBattery,
            wingStopwatch: settings.wingStopwatch,
            wingPomodoro: settings.wingPomodoro,
            wingCalendar: settings.wingCalendar,
            battery: BatteryMonitor.shared.snapshot,
            stopwatchHasTime: StopwatchModel.shared.hasTime,
            pomodoroActive: PomodoroModel.shared.phase != .idle,
            musicPlaying: NowPlayingManager.shared.isPlaying,
            nextEventStart: CalendarStore.shared.nextEvent?.startDate,
            now: Date()
        )
        let active = Self.activePersistent(inputs)
        for id in Self.persistentIDs {
            center.setPersistent(id, active: active.contains(id))
        }
    }
}
```

Dans `DynamicNotch/AppDelegate.swift`, remplacer les deux lignes :
```swift
        // Singletons des managers utilisés par les wings.
        _ = BatteryMonitor.shared
```
par :
```swift
        // Sources d'activités (batterie, Pomodoro, chrono, plateau, AirDrop…).
        ActivityWiring.shared.install()
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Activities/ActivityWiring.swift && Tools/test.sh ActivityWiringTests`
Expected : `Executed 6 tests, with 0 failures`.

- [ ] **Step 3 : build, tests, vérification manuelle, commit**

Run : `Tools/build.sh && Tools/test.sh` → `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

Vérification manuelle (Release relancée) :
1. Brancher le chargeur : la carte « En charge » descend (≈ 2,2 s), puis se replie en ailes ⚡ + %.
2. Débrancher : « Sur batterie · NN % » (≈ 1,5 s), puis encoche nue.
3. Lancer le chrono depuis le panneau, fermer : ailes mm:ss qui avancent chaque seconde.
4. Déposer deux fichiers dans « Fichiers » : ✓ « 2 fichiers ajoutés ».

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: câblage des activités (charge, batterie, Pomodoro, chrono, fichiers, AirDrop)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12 : musique en cours (seulement si le spike de la tâche 1 est positif)

Si la tâche 1 a conclu « accès bloqué », **ne pas exécuter cette tâche** : le signaler et attendre la décision de l'utilisateur.

**Files :**
- Modify : `DynamicNotch/Widgets/NowPlayingWidget.swift` (struct `MR`, classe `NowPlayingManager`), `DynamicNotch/Activities/ActivityWiring.swift` (`install()`)
- Create : `DynamicNotchTests/NowPlayingTrackTrackerTests.swift`

**Interfaces :**
- Produces : `struct NowPlayingTrackTracker { mutating func update(title: String) -> Bool }` ; `NowPlayingManager.onTrackChange: (() -> Void)?` ; `startObserving()` idempotent, basé sur les notifications MediaRemote (plus de polling de 3 s).

- [ ] **Step 1 : test qui échoue**

`DynamicNotchTests/NowPlayingTrackTrackerTests.swift` :
```swift
//
//  NowPlayingTrackTrackerTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

final class NowPlayingTrackTrackerTests: XCTestCase {
    func test_firstTitle_isBaseline_notAChange() {
        var tracker = NowPlayingTrackTracker()
        XCTAssertFalse(tracker.update(title: "A"))
    }

    func test_changes_areReportedOnce() {
        var tracker = NowPlayingTrackTracker()
        _ = tracker.update(title: "A")
        XCTAssertFalse(tracker.update(title: "A"))
        XCTAssertTrue(tracker.update(title: "B"))
        XCTAssertFalse(tracker.update(title: "B"))
    }

    func test_emptyTitle_isIgnored() {
        var tracker = NowPlayingTrackTracker()
        _ = tracker.update(title: "A")
        XCTAssertFalse(tracker.update(title: ""))
        XCTAssertFalse(tracker.update(title: "A"))
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/NowPlayingTrackTrackerTests.swift && Tools/test.sh NowPlayingTrackTrackerTests`
Expected : échec de compilation, `cannot find 'NowPlayingTrackTracker' in scope`.

- [ ] **Step 2 : implémenter**

Dans `DynamicNotch/Widgets/NowPlayingWidget.swift` :

1. Dans `private struct MR`, ajouter le type et le champ :
```swift
    typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    let register: RegisterFn?
```
puis dans `static let shared`, résoudre `MRMediaRemoteRegisterForNowPlayingNotifications` :
```swift
        let registerSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
        let register = registerSym.map { unsafeBitCast($0, to: RegisterFn.self) }
```
et passer `register: register` aux deux `.init(…)` (`register: nil` dans la branche d'échec du `dlopen`).

2. Avant `// MARK: - Manager`, ajouter :
```swift
/// Détecte un changement de morceau. Le premier titre vu sert de référence.
struct NowPlayingTrackTracker {
    private var lastTitle: String?

    mutating func update(title: String) -> Bool {
        guard !title.isEmpty else { return false }
        defer { lastTitle = title }
        guard let lastTitle else { return false }
        return lastTitle != title
    }
}
```

3. Dans `NowPlayingManager`, remplacer `private var pollTimer: Timer?` ainsi que `startObserving()`, `stopObserving()` et `refresh()` par :
```swift
    /// Appelé quand le titre change (hors premier titre vu).
    var onTrackChange: (() -> Void)?

    private var observing = false
    private var tracker = NowPlayingTrackTracker()

    /// Abonnement aux notifications MediaRemote. Idempotent : appelé au
    /// lancement par ActivityWiring et à l'apparition du widget.
    func startObserving() {
        guard !observing else { return }
        observing = true
        MR.shared.register?(DispatchQueue.main)
        for name in [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        ] {
            NotificationCenter.default.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    /// Conservé pour les appels existants : l'observation reste active pour les activités.
    func stopObserving() {}

    func refresh() {
        guard let getInfo = MR.shared.getNowPlayingInfo else { return }
        getInfo(.main) { [weak self] info in
            Task { @MainActor in
                guard let self else { return }
                self.title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                self.artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                self.artwork = (info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).flatMap { NSImage(data: $0) }
                self.isPlaying = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0) > 0
                if self.tracker.update(title: self.title) { self.onTrackChange?() }
            }
        }
    }
```

4. Dans `ActivityWiring.install()`, juste avant `let settings = AppSettings.shared`, ajouter :
```swift
        NowPlayingManager.shared.onTrackChange = { [weak self] in
            guard NowPlayingManager.shared.isPlaying else { return }
            self?.center.post(.nowPlaying)
        }
        NowPlayingManager.shared.startObserving()
```

Run : `Tools/test.sh NowPlayingTrackTrackerTests` → `Executed 3 tests, with 0 failures`.

- [ ] **Step 3 : build, tests, vérification manuelle, commit**

Run : `Tools/build.sh && Tools/test.sh` → `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

Vérification manuelle : lancer une musique → ailes pochette + barres ; passer au morceau suivant → carte titre et artiste (≈ 2 s) puis retour aux ailes.

```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: activité musique par notifications MediaRemote

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13 : outils Debug (simulation et rendu des états)

**Files :**
- Create : `DynamicNotch/Debug/DebugTools.swift`
- Modify : `DynamicNotch/main.swift`, `DynamicNotch/AppDelegate.swift`, `DynamicNotch/NotchMenuView.swift`

**Interfaces :**
- Consumes : `ActivityID.samples`/`debugName` (6), `NotchViewModel.setPresentationForRendering` (10), `NotchGeometry`/`ScreenDescriptor` (3).
- Produces (Debug uniquement) : `enum ActivitySimulator { static func run(_ name: String, center: ActivityCenter = .shared); static func handleLaunchArguments() }`, `enum StateRenderer { static func renderAll(to: URL) }`, `struct DebugActivityTile: View`. Arguments : `--simulate <debugName>`, `--render-states <dossier>`.

- [ ] **Step 1 : écrire les outils**

`DynamicNotch/Debug/DebugTools.swift` :
```swift
//
//  DebugTools.swift
//  DynamicNotch
//
//  Outils de développement, absents des builds Release :
//   - `--simulate <activité>` : déclenche une activité 1 s après le lancement ;
//   - `--render-states <dossier>` : rend chaque état de la coque en PNG
//     (ImageRenderer) puis quitte, sans autorisation d'enregistrement d'écran ;
//   - une tuile « Simuler » dans le menu de l'encoche.
//

#if DEBUG
    import AppKit
    import SwiftUI

    @MainActor
    enum ActivitySimulator {
        static func run(_ name: String, center: ActivityCenter = .shared) {
            switch name {
            case "charging":
                center.setPersistent(.charging, active: true)
                center.post(.charging)
            case "unplugged":
                center.post(.unplugged)
            case "lowBattery":
                center.post(.lowBattery(percent: 10))
            case "pomodoroPhase":
                let model = PomodoroModel.shared
                if model.phase == .idle { model.performPrimary() }
                model.skip()
            case "stopwatch":
                if !StopwatchModel.shared.running { StopwatchModel.shared.toggle() }
            case "filesAdded":
                center.post(.filesAdded(count: 3))
            case "airDropSent":
                center.post(.airDropSent)
            case "nowPlaying":
                center.setPersistent(.nowPlaying, active: true)
                center.post(.nowPlaying)
            case "calendarSoon":
                center.setPersistent(.calendarSoon, active: true)
            default:
                Log.app.error("activité simulée inconnue : \(name, privacy: .public)")
            }
        }

        static func handleLaunchArguments() {
            guard let index = CommandLine.arguments.firstIndex(of: "--simulate"),
                  index + 1 < CommandLine.arguments.count
            else { return }
            let name = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { run(name) }
            }
        }
    }

    @MainActor
    enum StateRenderer {
        static func renderAll(to directory: URL) {
            let geometry = NSScreen.main.map { NotchGeometry(screen: ScreenDescriptor($0)) } ?? .preview
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var states: [(String, NotchPresentation)] = [
                ("closed", .closed), ("peek", .peek), ("opened", .opened(.normal)),
            ]
            for id in ActivityID.samples {
                states.append(("compact-\(id.debugName)", .compact(id)))
                states.append(("expanded-\(id.debugName)", .expanded(id)))
            }

            for (name, state) in states {
                let vm = NotchViewModel(geometry: geometry)
                vm.setPresentationForRendering(state)
                // Haut de fenêtre seulement, sauf pour le panneau ouvert.
                let height: CGFloat = state.isOpened ? NotchGeometry.windowSize.height : 120
                let view = NotchView(vm: vm)
                    .frame(width: NotchGeometry.windowSize.width, height: height, alignment: .top)
                    .clipped()
                    .background(Color(white: 0.82))
                let renderer = ImageRenderer(content: view)
                renderer.scale = geometry.screen.scale
                if let image = renderer.cgImage,
                   let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                {
                    try? png.write(to: directory.appendingPathComponent("\(name).png"))
                }
                vm.destroy()
            }
            print("rendu : \(states.count) états dans \(directory.path)")
        }
    }

    struct DebugActivityTile: View {
        let onPick: (String) -> Void

        var body: some View {
            Menu {
                ForEach(ActivityID.samples.map(\.debugName), id: \.self) { name in
                    Button(name) { onPick(name) }
                }
            } label: {
                Label("Simuler", systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
#endif
```

- [ ] **Step 2 : brancher**

`DynamicNotch/main.swift`, juste après le bloc de l'hôte de tests (tâche 0), ajouter :
```swift
#if DEBUG
    // Rendu des états en PNG, sans fenêtre ni verrou d'instance unique.
    if let index = CommandLine.arguments.firstIndex(of: "--render-states"),
       index + 1 < CommandLine.arguments.count
    {
        _ = NSApplication.shared
        MainActor.assumeIsolated {
            StateRenderer.renderAll(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        exit(0)
    }
#endif

```

`DynamicNotch/AppDelegate.swift`, à la fin de `applicationDidFinishLaunching`, après `rebuildApplicationWindows(force: true)` :
```swift
        #if DEBUG
            ActivitySimulator.handleLaunchArguments()
        #endif
```

`DynamicNotch/NotchMenuView.swift`, dans le `HStack` de `body`, après `quitTile` :
```swift
            #if DEBUG
                DebugActivityTile { name in
                    vm.notchClose()
                    // Laisser le panneau se fermer : ouvert, il suspend les activités.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        MainActor.assumeIsolated { ActivitySimulator.run(name) }
                    }
                }
            #endif
```

- [ ] **Step 3 : rendre les états et les regarder**

```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/Debug/DebugTools.swift
Tools/build.sh Debug
OUT="$TMPDIR/notch-states" && rm -rf "$OUT"
build/Build/Products/Debug/DynamicNotch.app/Contents/MacOS/DynamicNotch --render-states "$OUT"
ls "$OUT"
```
Expected : `rendu : 21 états dans …` et 21 fichiers PNG. Ouvrir chaque PNG (outil Read) et vérifier :
- `closed.png` : forme noire nette, oreilles concaves, coins bas arrondis, aucun contenu ;
- `compact-*.png` : ailes symétriques, texte en 13 pt net et centré verticalement, rien sous l'encoche ;
- `expanded-*.png` : ligne icône, titre, valeur sous l'encoche, rien de tronqué ;
- `opened.png` : header et tuiles lisibles, pas de halo.
Corriger les défauts visibles (dans les limites de l'interface) avant de continuer.

- [ ] **Step 4 : build Release (les outils doivent en être absents), commit**

Run : `Tools/build.sh && Tools/test.sh` → `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.
Run : `strings build/Build/Products/Release/DynamicNotch.app/Contents/MacOS/DynamicNotch | grep -c "render-states"` → `0`.

```bash
git add -A DynamicNotch DynamicNotch.xcodeproj
git commit -m "chore: simulation d'activités et rendu PNG des états (Debug)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14 : vérification finale et documentation

**Files :**
- Modify : `README.md`, `Resources/Privacy.md` (mentions de `~/Documents/DynamicNotch`), `DynamicNotchTests/README.md` (tableau des fichiers)

- [ ] **Step 1 : suite complète et build Release**

Run : `Tools/test.sh && Tools/build.sh`
Expected : `** TEST SUCCEEDED **` (les 11 classes de test), `** BUILD SUCCEEDED **`, aucune ligne `warning:` qui pointe vers un fichier créé ou réécrit par ce plan.

- [ ] **Step 2 : alignement au pixel sur l'encoche physique**

Run : `Tools/test.sh NotchGeometryTests` → 7 tests OK (x = 663, largeur 185 sur l'écran de référence).
Puis, sur la vraie machine (Release relancée), demander à l'utilisateur de confirmer à l'œil qu'en état fermé la coque est invisible (confondue avec l'encoche). Si le terminal a l'autorisation d'enregistrement de l'écran : `screencapture -x -R 600,0,312,40 "$TMPDIR/notch-closed.png"` et inspecter.

- [ ] **Step 3 : parcours des activités sur l'app Debug**

```bash
pkill -x DynamicNotch
for name in charging unplugged lowBattery pomodoroPhase filesAdded airDropSent; do
  build/Build/Products/Debug/DynamicNotch.app/Contents/MacOS/DynamicNotch --simulate "$name" &
  sleep 5; pkill -x DynamicNotch; sleep 1
done
```
Demander à l'utilisateur de regarder l'encoche pendant la boucle : chaque activité descend en carte puis se replie (ou disparaît) sans saccade ni flou.

- [ ] **Step 4 : documentation**

```bash
grep -rn "Documents/DynamicNotch\|documentsDirectory" README.md Resources DynamicNotchTests
```
Remplacer chaque mention de l'emplacement des données par `~/Library/Application Support/DynamicNotch` (en précisant que l'ancien dossier `~/Documents/DynamicNotch` est migré une fois puis laissé en place). Dans `DynamicNotchTests/README.md`, compléter le tableau « Files » avec une ligne par nouveau fichier de test (`DataMigrationTests`, `NotchGeometryTests`, `NotchShellShapeTests`, `ActivityCenterTests`, `PowerEventsTests`, `NotchPresentationTests`, `StopwatchModelTests`, `PomodoroModelTests`, `ActivityWiringTests`, `NowPlayingTrackTrackerTests` si la tâche 12 a été faite) et ce qu'il couvre.

- [ ] **Step 5 : commit final**

```bash
git add -A README.md Resources DynamicNotchTests
git commit -m "docs: emplacement des données et tests de la refonte

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
