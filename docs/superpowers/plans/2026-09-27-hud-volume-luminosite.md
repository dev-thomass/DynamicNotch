# HUD volume et luminosité — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** remplacer le HUD de macOS (volume, muet, luminosité de l'écran intégré) par une carte qui sort de l'encoche, avec repli en cohabitation sans autorisation Accessibilité.

**Architecture :** un event tap de session décode les touches système et décide sans bloquer (via un instantané `MediaKeyPolicy`) de les consommer ; le traitement passe au `MediaKeyRouter` sur le fil principal, qui règle le son (volume principal virtuel CoreAudio) ou la luminosité (DisplayServices) derrière deux protocoles, puis publie un `HUDState` dans `HUDController`. Chaque `NotchViewModel` observe ce contrôleur : l'état de coque `.hud` passe avant les activités, et la rangée du haut du panneau ouvert affiche un indicateur.

**Tech Stack :** Swift 5 (mode 5), SwiftUI + AppKit, CoreGraphics (CGEventTap), CoreAudio/AudioToolbox, DisplayServices (privé, `dlopen`), ApplicationServices (`AXIsProcessTrusted`), XCTest.

**Spec :** `docs/superpowers/specs/2026-09-27-hud-volume-luminosite-design.md`

## Global Constraints

- Branche `refonte/hud-volume-luminosite`. Commits en français, préfixe conventionnel ; ligne `Co-Authored-By` selon le harnais de l'agent.
- Tout fichier Swift créé ou supprimé passe par `ruby Tools/xcproj.rb add <Cible> <fichiers…>` / `remove`.
- Tests : `Tools/test.sh [Classe]` (toujours non signé). Build : `Tools/build.sh [Debug|Release]`.
- Swift 5, macOS 14. Dans une closure `DispatchQueue.main.async/asyncAfter`, entourer les appels isolés au MainActor de `MainActor.assumeIsolated { … }`.
- **Les tests ne modifient jamais le volume ni la luminosité réels** : la logique se teste avec des doublures ; les implémentations système ne sont appelées qu'en lecture dans les tests.
- Touches gérées (codes `NX_KEYTYPE_*`) : 0 volume +, 1 volume −, 7 muet, 2 luminosité +, 3 luminosité −. Tout le reste est relâché.
- Pas : 1/16 ; avec ⌥⇧ : 1/64 ; niveaux bornés à [0, 1].
- Durée d'affichage du HUD : 1,5 s après le dernier changement.
- Carte HUD : 340 pt de large, `max(80, hauteur d'encoche + 48)` de haut, oreilles 10 pt (0 en pilule), rayon bas 24, ombre.
- Coque : noir opaque ; ressorts de coque uniquement `expand` / `collapse` / `micro` ; aucun zoom ni flou sur du texte au repos.

---

### Task 0 : spike de faisabilité (jetable)

**But :** vérifier sous macOS 26, depuis cette machine, (a) DisplayServices sous runtime renforcé avec les entitlements de l'app, (b) la lecture et le caractère réglable du volume principal virtuel, (c) le comportement de `CGEvent.tapCreate` et `AXIsProcessTrusted`. Rien n'est commité hormis le résultat consigné dans ce plan.

**Files :** scratch hors dépôt (`$TMPDIR/hud-spike/`) ; Modify : ce plan, section « Résultat du spike ».

- [ ] **Step 1 : écrire le spike**

```bash
mkdir -p "$TMPDIR/hud-spike" && cat > "$TMPDIR/hud-spike/spike.swift" <<'EOF'
import AppKit
import AudioToolbox
import CoreAudio

// (a) DisplayServices
typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
print("DisplayServices dlopen:", ds != nil)
var count: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetOnlineDisplayList(count, &ids, &count)
let builtin = ids.first { CGDisplayIsBuiltin($0) != 0 }
if let ds, let sym = dlsym(ds, "DisplayServicesGetBrightness"), let builtin {
    var v: Float = -1
    let r = unsafeBitCast(sym, to: GetFn.self)(builtin, &v)
    print("brightness:", r, v)
} else { print("brightness: indisponible (écran intégré:", builtin as Any, ")") }

// (b) volume principal virtuel
var device = AudioDeviceID(0)
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
var def = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &def, 0, nil, &size, &device)
var vol = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
var level: Float32 = -1
size = UInt32(MemoryLayout<Float32>.size)
let rv = AudioObjectGetPropertyData(device, &vol, 0, nil, &size, &level)
var settable: DarwinBoolean = false
AudioObjectIsPropertySettable(device, &vol, &settable)
print("volume:", rv, level, "settable:", settable.boolValue)

// (c) autorisation + tap
print("AXIsProcessTrusted:", AXIsProcessTrusted())
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                            eventsOfInterest: CGEventMask(1 << 14), callback: { _, _, e, _ in Unmanaged.passUnretained(e) }, userInfo: nil)
print("tap listenOnly créé:", tap != nil)
EOF
cd "$TMPDIR/hud-spike" && swiftc -o spike spike.swift && ./spike
```

- [ ] **Step 2 : même binaire sous runtime renforcé et entitlements de l'app**

```bash
cd "$TMPDIR/hud-spike"
codesign -f -s - --options runtime --entitlements /Users/thommac/DynamicNotch/DynamicNotch/DynamicNotch.entitlements spike && ./spike
```
Comparer la ligne `DisplayServices dlopen` / `brightness` avec l'étape 1. Si elle échoue seulement ici, refaire avec un fichier d'entitlements sans les clés `com.apple.security.hardened-process*` pour identifier la clé bloquante.

- [ ] **Step 3 : consigner et décider**

Compléter « Résultat du spike » ci-dessous (sorties brutes, décision) et commiter le plan.
- Si DisplayServices échoue sous runtime renforcé à cause d'une clé `hardened-process`, la tâche 7 retire cette clé de `DynamicNotch/DynamicNotch.entitlements` (le noter).
- `AXIsProcessTrusted` sera faux ici (processus du terminal) et le tap `nil` : c'est attendu ; l'interception réelle se vérifie à la main en tâche 8 avec l'app signée.

```bash
git add docs/superpowers/plans/2026-09-27-hud-volume-luminosite.md
git commit -m "docs: résultat du spike HUD"
```

#### Résultat du spike

_(à compléter par l'exécutant : sorties brutes des étapes 1 et 2, décision sur les entitlements)_

---

### Task 1 : touches, pas et icônes (modèles purs)

**Files :**
- Create : `DynamicNotch/HUD/MediaKey.swift`, `DynamicNotch/HUD/HUDState.swift`, `DynamicNotchTests/MediaKeyTests.swift`

**Interfaces :**
- Produces :
  - `enum MediaKey: Equatable { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown; init?(keyCode: Int); var isVolume: Bool }`
  - `struct MediaKeyEvent: Equatable { let key: MediaKey; let isDown: Bool; let isRepeat: Bool; let fine: Bool; static func decode(subtype: Int, data1: Int, modifiers: NSEvent.ModifierFlags) -> MediaKeyEvent? }`
  - `enum LevelStep { static let coarse: Double; static let fine: Double; static func next(level: Double, up: Bool, fine: Bool) -> Double }`
  - `enum HUDKind: Hashable { case volume, brightness }`, `struct HUDState: Equatable { var kind: HUDKind; var level: Double; var isMuted: Bool; var percent: Int }`, `enum HUDIcon { static func systemImage(kind:level:isMuted:) -> String }`

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/MediaKeyTests.swift` :
```swift
//
//  MediaKeyTests.swift
//  DynamicNotchTests
//

import AppKit
import XCTest
@testable import DynamicNotch

final class MediaKeyTests: XCTestCase {
    private func data1(code: Int, down: Bool, repeat isRepeat: Bool = false) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
    }

    func test_decode_knownKeys() {
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true), modifiers: []),
                       MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false, fine: false))
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 1, down: false), modifiers: [])?.key, .volumeDown)
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 7, down: true), modifiers: [])?.key, .mute)
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 2, down: true), modifiers: [])?.key, .brightnessUp)
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 3, down: true), modifiers: [])?.key, .brightnessDown)
    }

    func test_decode_upDownRepeatAndFine() {
        let up = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: false), modifiers: [])
        XCTAssertEqual(up?.isDown, false)
        let rep = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true, repeat: true), modifiers: [])
        XCTAssertEqual(rep?.isRepeat, true)
        let fine = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true), modifiers: [.option, .shift])
        XCTAssertEqual(fine?.fine, true)
        let optionOnly = MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, down: true), modifiers: [.option])
        XCTAssertEqual(optionOnly?.fine, false)
    }

    func test_decode_ignoresOtherEvents() {
        XCTAssertNil(MediaKeyEvent.decode(subtype: 7, data1: data1(code: 0, down: true), modifiers: []))
        XCTAssertNil(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 16, down: true), modifiers: []), "lecture/pause")
        XCTAssertNil(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 21, down: true), modifiers: []), "rétroéclairage clavier")
        XCTAssertNil(MediaKeyEvent.decode(subtype: 8, data1: (0 << 16) | (0x0C << 8), modifiers: []), "état inconnu")
    }

    func test_levelStep() {
        XCTAssertEqual(LevelStep.next(level: 0.5, up: true, fine: false), 0.5625)
        XCTAssertEqual(LevelStep.next(level: 0.5, up: false, fine: false), 0.4375)
        XCTAssertEqual(LevelStep.next(level: 0.5, up: true, fine: true), 0.515625)
        XCTAssertEqual(LevelStep.next(level: 0.51, up: true, fine: false), 0.5625, "recalé sur la grille")
        XCTAssertEqual(LevelStep.next(level: 0.99, up: true, fine: false), 1)
        XCTAssertEqual(LevelStep.next(level: 0, up: false, fine: false), 0)
    }

    func test_hudIcon() {
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.5, isMuted: true), "speaker.slash.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0, isMuted: false), "speaker.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.2, isMuted: false), "speaker.wave.1.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.5, isMuted: false), "speaker.wave.2.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .volume, level: 0.9, isMuted: false), "speaker.wave.3.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .brightness, level: 0.3, isMuted: false), "sun.min.fill")
        XCTAssertEqual(HUDIcon.systemImage(kind: .brightness, level: 0.7, isMuted: false), "sun.max.fill")
    }

    func test_hudState_percent() {
        XCTAssertEqual(HUDState(kind: .volume, level: 0.625).percent, 63)
        XCTAssertEqual(HUDState(kind: .brightness, level: 1).percent, 100)
    }
}
```
Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/MediaKeyTests.swift && Tools/test.sh MediaKeyTests` → échec de compilation (`cannot find 'MediaKeyEvent'`).

- [ ] **Step 2 : implémenter**

`DynamicNotch/HUD/MediaKey.swift` :
```swift
//
//  MediaKey.swift
//  DynamicNotch
//
//  Touches système volume / luminosité, décodées depuis les événements
//  NX_SYSDEFINED (sous-type 8), et calcul des pas de réglage.
//

import AppKit

enum MediaKey: Equatable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    /// Codes `NX_KEYTYPE_*` d'IOKit (hidsystem/ev_keymap.h).
    init?(keyCode: Int) {
        switch keyCode {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        default: return nil
        }
    }

    var isVolume: Bool {
        switch self {
        case .volumeUp, .volumeDown, .mute: true
        case .brightnessUp, .brightnessDown: false
        }
    }
}

struct MediaKeyEvent: Equatable {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    /// ⌥⇧ maintenus : pas fin (1/64).
    let fine: Bool

    /// Décode un événement système : `data1` porte le code de touche (bits 16–31),
    /// l'état (bits 8–15 : 0x0A appui, 0x0B relâchement) et la répétition (bit 0).
    static func decode(subtype: Int, data1: Int, modifiers: NSEvent.ModifierFlags) -> MediaKeyEvent? {
        guard subtype == 8 else { return nil }
        guard let key = MediaKey(keyCode: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let state = (data1 & 0xFF00) >> 8
        guard state == 0x0A || state == 0x0B else { return nil }
        return MediaKeyEvent(
            key: key,
            isDown: state == 0x0A,
            isRepeat: data1 & 0x1 == 1,
            fine: modifiers.contains(.option) && modifiers.contains(.shift)
        )
    }
}

enum LevelStep {
    static let coarse = 1.0 / 16
    static let fine = 1.0 / 64

    /// Niveau suivant, recalé sur la grille du pas (comme macOS) et borné à [0, 1].
    static func next(level: Double, up: Bool, fine: Bool) -> Double {
        let step = fine ? Self.fine : coarse
        let index = (level / step).rounded() + (up ? 1 : -1)
        return min(1, max(0, index * step))
    }
}
```

`DynamicNotch/HUD/HUDState.swift` :
```swift
//
//  HUDState.swift
//  DynamicNotch
//
//  Ce que montre le HUD : type, niveau, muet ; et l'icône correspondante.
//

import Foundation

enum HUDKind: Hashable {
    case volume, brightness
}

struct HUDState: Equatable {
    var kind: HUDKind
    var level: Double
    var isMuted: Bool = false

    var percent: Int { Int((level * 100).rounded()) }
}

enum HUDIcon {
    static func systemImage(kind: HUDKind, level: Double, isMuted: Bool) -> String {
        switch kind {
        case .volume:
            if isMuted { return "speaker.slash.fill" }
            if level <= 0 { return "speaker.fill" }
            if level < 1.0 / 3 { return "speaker.wave.1.fill" }
            if level < 2.0 / 3 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}
```

Run :
```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/HUD/MediaKey.swift DynamicNotch/HUD/HUDState.swift
Tools/test.sh MediaKeyTests
```
Expected : 6 tests verts.

- [ ] **Step 3 : suite complète, commit**

Run : `Tools/test.sh` → `** TEST SUCCEEDED **`.
```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: décodage des touches système, pas de réglage et icônes du HUD"
```

---

### Task 2 : `HUDController`

**Files :**
- Create : `DynamicNotch/HUD/HUDController.swift`, `DynamicNotchTests/HUDControllerTests.swift`

**Interfaces :**
- Consumes : `ActivityScheduler`, `ScheduledWork`, `MainQueueScheduler`, `ActivityObservation` (DynamicNotch/Activities/) ; `ManualScheduler` (DynamicNotchTests/ActivityCenterTests.swift) ; `HUDState` (1).
- Produces : `@MainActor final class HUDController: ObservableObject { static let shared; static let displayDuration: TimeInterval = 1.5; init(scheduler:); @Published private(set) var current: HUDState?; private(set) var lastShown: HUDState?; func show(_:); func hide(); @discardableResult func observe(_:) -> ActivityObservation }`

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/HUDControllerTests.swift` :
```swift
//
//  HUDControllerTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
final class HUDControllerTests: XCTestCase {
    private var scheduler: ManualScheduler!
    private var hud: HUDController!

    override func setUp() async throws {
        scheduler = ManualScheduler()
        hud = HUDController(scheduler: scheduler)
    }

    func test_show_thenHidesAfterDuration() {
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(hud.current, HUDState(kind: .volume, level: 0.5))
        scheduler.advance(by: 1.4)
        XCTAssertNotNil(hud.current)
        scheduler.advance(by: 0.1)
        XCTAssertNil(hud.current)
        XCTAssertEqual(hud.lastShown, HUDState(kind: .volume, level: 0.5), "gardé pour la sortie animée")
    }

    func test_eachShow_extends() {
        hud.show(HUDState(kind: .volume, level: 0.5))
        scheduler.advance(by: 1.4)
        hud.show(HUDState(kind: .volume, level: 0.5625))
        scheduler.advance(by: 1.4)
        XCTAssertEqual(hud.current?.level, 0.5625)
        scheduler.advance(by: 0.1)
        XCTAssertNil(hud.current)
    }

    func test_observers_notifiedOnChanges_only() {
        var received: [HUDState?] = []
        let observation = hud.observe { received.append($0) }
        hud.show(HUDState(kind: .volume, level: 0.5))
        hud.show(HUDState(kind: .volume, level: 0.5))
        hud.show(HUDState(kind: .brightness, level: 0.3))
        scheduler.advance(by: 1.5)
        hud.hide()
        XCTAssertEqual(received, [
            HUDState(kind: .volume, level: 0.5),
            HUDState(kind: .brightness, level: 0.3),
            nil,
        ])
        observation.cancel()
    }
}
```
Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/HUDControllerTests.swift && Tools/test.sh HUDControllerTests` → échec de compilation.

- [ ] **Step 2 : implémenter**

`DynamicNotch/HUD/HUDController.swift` :
```swift
//
//  HUDController.swift
//  DynamicNotch
//
//  Canal du HUD, prioritaire sur les activités : un état affiché 1,5 s après
//  le dernier changement. Partagé par toutes les encoches.
//

import Combine
import Foundation

@MainActor
final class HUDController: ObservableObject {
    static let shared = HUDController(scheduler: MainQueueScheduler())
    static let displayDuration: TimeInterval = 1.5

    @Published private(set) var current: HUDState?
    /// Dernier état affiché, conservé pendant l'animation de sortie.
    private(set) var lastShown: HUDState?

    private let scheduler: ActivityScheduler
    private var hideWork: ScheduledWork?
    private var observers: [UUID: (HUDState?) -> Void] = [:]

    init(scheduler: ActivityScheduler) {
        self.scheduler = scheduler
    }

    /// Affiche (ou met à jour) le HUD et repousse sa disparition.
    func show(_ state: HUDState) {
        hideWork?.cancel()
        lastShown = state
        hideWork = scheduler.schedule(after: Self.displayDuration) { [weak self] in
            self?.hide()
        }
        guard state != current else { return }
        current = state
        notify()
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard current != nil else { return }
        current = nil
        notify()
    }

    @discardableResult
    func observe(_ handler: @escaping (HUDState?) -> Void) -> ActivityObservation {
        let key = UUID()
        observers[key] = handler
        return ActivityObservation { [weak self] in
            self?.observers[key] = nil
        }
    }

    private func notify() {
        for handler in observers.values {
            handler(current)
        }
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/HUD/HUDController.swift && Tools/test.sh HUDControllerTests` → 3/3.

- [ ] **Step 3 : suite, commit**

Run : `Tools/test.sh` → vert.
```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: HUDController (affichage 1,5 s, prolongé à chaque changement)"
```

---

### Task 3 : contrôles système (volume CoreAudio, luminosité DisplayServices)

**Files :**
- Create : `DynamicNotch/HUD/SystemControls.swift`, `DynamicNotch/HUD/CoreAudioVolumeControl.swift`, `DynamicNotch/HUD/DisplayServicesBrightnessControl.swift`, `DynamicNotchTests/SystemControlsSmokeTests.swift`

**Interfaces :**
- Produces :
  - `@MainActor protocol VolumeControl: AnyObject { var isSettable: Bool { get }; var level: Double { get }; var isMuted: Bool { get }; func setLevel(_ level: Double); func setMuted(_ muted: Bool); var onVolumeChange: (() -> Void)? { get set }; var onDeviceChange: (() -> Void)? { get set } }`
  - `@MainActor protocol BrightnessControl: AnyObject { var isAvailable: Bool { get }; var level: Double { get }; func setLevel(_ level: Double) }`
  - `CoreAudioVolumeControl: VolumeControl`, `DisplayServicesBrightnessControl: BrightnessControl`

- [ ] **Step 1 : tests de fumée (lecture seule) qui échouent**

`DynamicNotchTests/SystemControlsSmokeTests.swift` :
```swift
//
//  SystemControlsSmokeTests.swift
//  DynamicNotchTests
//
//  Lecture seule : ces tests ne modifient jamais le volume ni la luminosité.
//

import XCTest
@testable import DynamicNotch

@MainActor
final class SystemControlsSmokeTests: XCTestCase {
    func test_volume_readsWithinRange() {
        let volume = CoreAudioVolumeControl()
        XCTAssertTrue((0 ... 1).contains(volume.level))
        _ = volume.isMuted
        _ = volume.isSettable
    }

    func test_brightness_readsWithinRange_whenAvailable() {
        let brightness = DisplayServicesBrightnessControl()
        if brightness.isAvailable {
            XCTAssertTrue((0 ... 1).contains(brightness.level))
        } else {
            XCTAssertEqual(brightness.level, 0)
        }
    }
}
```
Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/SystemControlsSmokeTests.swift && Tools/test.sh SystemControlsSmokeTests` → échec de compilation.

- [ ] **Step 2 : protocoles**

`DynamicNotch/HUD/SystemControls.swift` :
```swift
//
//  SystemControls.swift
//  DynamicNotch
//
//  Interfaces des réglages système utilisés par le HUD. Les implémentations
//  réelles parlent à CoreAudio et DisplayServices ; les tests utilisent des doublures.
//

import Foundation

@MainActor
protocol VolumeControl: AnyObject {
    /// La sortie actuelle permet-elle de régler le volume principal ?
    var isSettable: Bool { get }
    /// 0…1
    var level: Double { get }
    var isMuted: Bool { get }
    func setLevel(_ level: Double)
    func setMuted(_ muted: Bool)
    /// Volume ou muet modifié (par nous ou ailleurs), sur la file principale.
    var onVolumeChange: (() -> Void)? { get set }
    /// Sortie audio par défaut changée, sur la file principale.
    var onDeviceChange: (() -> Void)? { get set }
}

@MainActor
protocol BrightnessControl: AnyObject {
    /// Écran intégré présent et réglable.
    var isAvailable: Bool { get }
    /// 0…1 (0 si indisponible)
    var level: Double { get }
    func setLevel(_ level: Double)
}
```

- [ ] **Step 3 : volume CoreAudio**

`DynamicNotch/HUD/CoreAudioVolumeControl.swift` :
```swift
//
//  CoreAudioVolumeControl.swift
//  DynamicNotch
//
//  Volume de la sortie par défaut via le « volume principal virtuel »
//  d'AudioToolbox, celui que macOS utilise : il gère correctement les
//  sorties Bluetooth, AirPlay et USB (l'élément principal CoreAudio non).
//

import AudioToolbox
import CoreAudio

@MainActor
final class CoreAudioVolumeControl: VolumeControl {
    var onVolumeChange: (() -> Void)?
    var onDeviceChange: (() -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var valueListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.attach(to: Self.readDefaultDevice())
                self.onDeviceChange?()
            }
        }
        deviceListener = listener
        var address = Self.defaultOutput
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        attach(to: Self.readDefaultDevice())
    }

    var isSettable: Bool {
        var address = Self.volume
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    var level: Double {
        var address = Self.volume
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard device != kAudioObjectUnknown,
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return Double(min(1, max(0, value)))
    }

    var isMuted: Bool {
        var address = Self.mute
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    func setLevel(_ level: Double) {
        var address = Self.volume
        var value = Float32(min(1, max(0, level)))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    func setMuted(_ muted: Bool) {
        var address = Self.mute
        guard AudioObjectHasProperty(device, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: écouteurs

    /// Rebranche les écouteurs volume et muet sur `newDevice`.
    private func attach(to newDevice: AudioDeviceID) {
        if let valueListener, device != kAudioObjectUnknown {
            var volume = Self.volume
            var mute = Self.mute
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, valueListener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, valueListener)
        }
        device = newDevice
        guard device != kAudioObjectUnknown else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onVolumeChange?() }
        }
        valueListener = listener
        var volume = Self.volume
        var mute = Self.mute
        AudioObjectAddPropertyListenerBlock(device, &volume, .main, listener)
        if AudioObjectHasProperty(device, &mute) {
            AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener)
        }
    }

    private static func readDefaultDevice() -> AudioDeviceID {
        var address = defaultOutput
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }
}
```

- [ ] **Step 4 : luminosité DisplayServices**

`DynamicNotch/HUD/DisplayServicesBrightnessControl.swift` :
```swift
//
//  DisplayServicesBrightnessControl.swift
//  DynamicNotch
//
//  Luminosité de l'écran intégré via le framework privé DisplayServices
//  (chargé à l'exécution). Indisponible sans écran intégré (Mac de bureau,
//  capot fermé) ou si les symboles manquent : les touches restent à macOS.
//

import AppKit

@MainActor
final class DisplayServicesBrightnessControl: BrightnessControl {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let get: GetFn?
    private let set: SetFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        get = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        set = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    }

    var isAvailable: Bool { set != nil && read() != nil }

    var level: Double { read() ?? 0 }

    func setLevel(_ level: Double) {
        guard let set, let display = builtinDisplay else { return }
        _ = set(display, Float(min(1, max(0, level))))
    }

    private func read() -> Double? {
        guard let get, let display = builtinDisplay else { return nil }
        var value: Float = 0
        guard get(display, &value) == 0 else { return nil }
        return Double(min(1, max(0, value)))
    }

    private var builtinDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
```

- [ ] **Step 5 : tests, build, commit**

```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/HUD/SystemControls.swift DynamicNotch/HUD/CoreAudioVolumeControl.swift DynamicNotch/HUD/DisplayServicesBrightnessControl.swift
Tools/test.sh SystemControlsSmokeTests && Tools/test.sh && Tools/build.sh
```
Expected : 2/2, suite verte, `** BUILD SUCCEEDED **` sans nouvel avertissement.
```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: contrôles système du HUD (volume principal virtuel, luminosité intégrée)"
```

---

### Task 4 : politique et routeur des touches

**Files :**
- Create : `DynamicNotch/HUD/MediaKeyRouter.swift`, `DynamicNotchTests/MediaKeyRouterTests.swift`

**Interfaces :**
- Consumes : `MediaKey`, `MediaKeyEvent`, `LevelStep` (1) ; `HUDController`, `HUDState` (1–2) ; `VolumeControl`, `BrightnessControl` (3).
- Produces :
  - `final class MediaKeyPolicy: @unchecked Sendable { struct Snapshot: Equatable { var replaceEnabled, trusted, volumeSettable, brightnessAvailable: Bool }; func update(_:); var current: Snapshot; func shouldConsume(_ key: MediaKey) -> Bool }`
  - `@MainActor final class MediaKeyRouter { init(volume:brightness:hud:policy:playFeedback:); let policy; var replaceEnabled: Bool; var trusted: Bool; func refreshPolicy(); func apply(_ event: MediaKeyEvent); func volumeChangedExternally() }`

- [ ] **Step 1 : tests qui échouent**

`DynamicNotchTests/MediaKeyRouterTests.swift` :
```swift
//
//  MediaKeyRouterTests.swift
//  DynamicNotchTests
//

import XCTest
@testable import DynamicNotch

@MainActor
private final class FakeVolume: VolumeControl {
    var isSettable = true
    var level = 0.5
    var isMuted = false
    var onVolumeChange: (() -> Void)?
    var onDeviceChange: (() -> Void)?
    func setLevel(_ level: Double) { self.level = level }
    func setMuted(_ muted: Bool) { isMuted = muted }
}

@MainActor
private final class FakeBrightness: BrightnessControl {
    var isAvailable = true
    var level = 0.5
    func setLevel(_ level: Double) { self.level = level }
}

@MainActor
final class MediaKeyRouterTests: XCTestCase {
    private var volume: FakeVolume!
    private var brightness: FakeBrightness!
    private var hud: HUDController!
    private var feedbacks = 0
    private var router: MediaKeyRouter!

    override func setUp() async throws {
        volume = FakeVolume()
        brightness = FakeBrightness()
        hud = HUDController(scheduler: ManualScheduler())
        feedbacks = 0
        router = MediaKeyRouter(volume: volume, brightness: brightness, hud: hud, policy: MediaKeyPolicy()) { [unowned self] in
            feedbacks += 1
        }
        router.replaceEnabled = true
        router.trusted = true
        router.refreshPolicy()
    }

    private func press(_ key: MediaKey, fine: Bool = false) {
        router.apply(MediaKeyEvent(key: key, isDown: true, isRepeat: false, fine: fine))
    }

    func test_volumeUp_stepsAndShowsHUD_withFeedback() {
        press(.volumeUp)
        XCTAssertEqual(volume.level, 0.5625)
        XCTAssertEqual(hud.current, HUDState(kind: .volume, level: 0.5625, isMuted: false))
        XCTAssertEqual(feedbacks, 1)
    }

    func test_fineStep() {
        press(.volumeDown, fine: true)
        XCTAssertEqual(volume.level, 0.484375)
    }

    func test_volumeUp_unmutes() {
        volume.isMuted = true
        press(.volumeUp)
        XCTAssertFalse(volume.isMuted)
    }

    func test_mute_toggles() {
        press(.mute)
        XCTAssertTrue(volume.isMuted)
        XCTAssertEqual(hud.current?.isMuted, true)
        press(.mute)
        XCTAssertFalse(volume.isMuted)
    }

    func test_brightness_steps_withoutFeedback() {
        press(.brightnessDown)
        XCTAssertEqual(brightness.level, 0.4375)
        XCTAssertEqual(hud.current, HUDState(kind: .brightness, level: 0.4375, isMuted: false))
        XCTAssertEqual(feedbacks, 0)
    }

    func test_keyUp_doesNothing() {
        router.apply(MediaKeyEvent(key: .volumeUp, isDown: false, isRepeat: false, fine: false))
        XCTAssertEqual(volume.level, 0.5)
        XCTAssertNil(hud.current)
    }

    func test_policy() {
        XCTAssertTrue(router.policy.shouldConsume(.volumeUp))
        XCTAssertTrue(router.policy.shouldConsume(.brightnessUp))

        volume.isSettable = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.mute))
        XCTAssertTrue(router.policy.shouldConsume(.brightnessDown))

        brightness.isAvailable = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.brightnessDown))

        volume.isSettable = true
        router.trusted = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.volumeUp))

        router.trusted = true
        router.replaceEnabled = false
        router.refreshPolicy()
        XCTAssertFalse(router.policy.shouldConsume(.volumeUp))
    }

    func test_externalVolumeChange_showsHUD() {
        volume.level = 0.25
        router.volumeChangedExternally()
        XCTAssertEqual(hud.current, HUDState(kind: .volume, level: 0.25, isMuted: false))
    }
}
```
Run : `ruby Tools/xcproj.rb add DynamicNotchTests DynamicNotchTests/MediaKeyRouterTests.swift && Tools/test.sh MediaKeyRouterTests` → échec de compilation.

- [ ] **Step 2 : implémenter**

`DynamicNotch/HUD/MediaKeyRouter.swift` :
```swift
//
//  MediaKeyRouter.swift
//  DynamicNotch
//
//  Décide quelles touches consommer (réponse immédiate, lisible hors du
//  MainActor depuis le rappel du tap) et applique les touches consommées :
//  pas de volume ou de luminosité, muet, affichage du HUD, son de retour.
//

import Foundation

/// Instantané protégé par verrou : le rappel du tap le lit sans attendre le fil principal.
final class MediaKeyPolicy: @unchecked Sendable {
    struct Snapshot: Equatable {
        var replaceEnabled = false
        var trusted = false
        var volumeSettable = false
        var brightnessAvailable = false
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()

    func update(_ new: Snapshot) {
        lock.lock()
        snapshot = new
        lock.unlock()
    }

    var current: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func shouldConsume(_ key: MediaKey) -> Bool {
        let s = current
        guard s.replaceEnabled, s.trusted else { return false }
        return key.isVolume ? s.volumeSettable : s.brightnessAvailable
    }
}

@MainActor
final class MediaKeyRouter {
    let policy: MediaKeyPolicy
    var replaceEnabled = true
    var trusted = false

    private let volume: VolumeControl
    private let brightness: BrightnessControl
    private let hud: HUDController
    private let playFeedback: () -> Void

    init(
        volume: VolumeControl,
        brightness: BrightnessControl,
        hud: HUDController,
        policy: MediaKeyPolicy,
        playFeedback: @escaping () -> Void
    ) {
        self.volume = volume
        self.brightness = brightness
        self.hud = hud
        self.policy = policy
        self.playFeedback = playFeedback
        volume.onVolumeChange = { [weak self] in self?.volumeChangedExternally() }
        volume.onDeviceChange = { [weak self] in self?.refreshPolicy() }
    }

    /// Recalcule la réponse immédiate du tap.
    func refreshPolicy() {
        policy.update(MediaKeyPolicy.Snapshot(
            replaceEnabled: replaceEnabled,
            trusted: trusted,
            volumeSettable: volume.isSettable,
            brightnessAvailable: brightness.isAvailable
        ))
    }

    /// Applique une touche consommée. Les relâchements ne font rien.
    func apply(_ event: MediaKeyEvent) {
        guard event.isDown else { return }
        switch event.key {
        case .volumeUp, .volumeDown:
            let up = event.key == .volumeUp
            if up, volume.isMuted { volume.setMuted(false) }
            volume.setLevel(LevelStep.next(level: volume.level, up: up, fine: event.fine))
            showVolume()
            playFeedback()
        case .mute:
            volume.setMuted(!volume.isMuted)
            showVolume()
        case .brightnessUp, .brightnessDown:
            let up = event.key == .brightnessUp
            brightness.setLevel(LevelStep.next(level: brightness.level, up: up, fine: event.fine))
            hud.show(HUDState(kind: .brightness, level: brightness.level))
        }
    }

    /// Volume changé hors de nos touches (Centre de contrôle, autre app, cohabitation).
    func volumeChangedExternally() {
        showVolume()
    }

    private func showVolume() {
        hud.show(HUDState(kind: .volume, level: volume.level, isMuted: volume.isMuted))
    }
}
```

Run : `ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/HUD/MediaKeyRouter.swift && Tools/test.sh MediaKeyRouterTests` → 8/8.

- [ ] **Step 3 : suite, commit**

Run : `Tools/test.sh` → vert.
```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: politique et routeur des touches volume et luminosité"
```

---

### Task 5 : event tap, autorisation et branchement dans l'app

**Files :**
- Create : `DynamicNotch/HUD/MediaKeyTap.swift`, `DynamicNotch/HUD/VolumeFeedback.swift`
- Modify : `DynamicNotch/AppSettings.swift`, `DynamicNotch/AppDelegate.swift` (après `ActivityWiring.shared.install()`)

**Interfaces :**
- Consumes : `MediaKeyRouter`, `MediaKeyPolicy` (4), `CoreAudioVolumeControl`, `DisplayServicesBrightnessControl` (3), `HUDController.shared` (2).
- Produces : `AppSettings.replaceSystemHUD: Bool` (clé `replaceSystemHUD`, défaut `true`), `AppSettings.volumeFeedback: Bool?` (clé `volumeFeedback`, défaut `nil`) ; `enum VolumeFeedback { static var systemPreference: Bool; static var isEnabled: Bool; static func play() }` ; `@MainActor final class MediaKeyTap { static let shared; func install(router:); var isTrusted: Bool; func requestTrust() }`.

Pas de test unitaire : le tap et l'autorisation dépendent du système ; la logique est couverte par la tâche 4. Vérification : build, lancement sans plantage, et contrôle manuel en tâche 8.

- [ ] **Step 1 : réglages**

Dans `DynamicNotch/AppSettings.swift`, après la dernière propriété `wing…`, ajouter :
```swift

    // MARK: HUD

    /// Remplace le HUD de macOS (touches interceptées) quand l'autorisation
    /// Accessibilité est accordée ; sinon, cohabitation.
    @PublishedPersist(key: "replaceSystemHUD", defaultValue: true)
    var replaceSystemHUD: Bool

    /// Son lors du changement de volume. `nil` : suit la préférence macOS.
    @PublishedPersist(key: "volumeFeedback", defaultValue: nil)
    var volumeFeedback: Bool?
```

- [ ] **Step 2 : son de retour**

`DynamicNotch/HUD/VolumeFeedback.swift` :
```swift
//
//  VolumeFeedback.swift
//  DynamicNotch
//
//  Petit son joué après un changement de volume, comme macOS quand
//  « Émettre un son lors du changement de volume » est coché.
//

import AppKit

@MainActor
enum VolumeFeedback {
    /// Préférence macOS (domaine global) « com.apple.sound.beep.feedback ».
    static var systemPreference: Bool {
        (UserDefaults.standard.object(forKey: "com.apple.sound.beep.feedback") as? Int) == 1
    }

    static var isEnabled: Bool {
        AppSettings.shared.volumeFeedback ?? systemPreference
    }

    private static let sound: NSSound? =
        NSSound(contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff", byReference: true)
        ?? NSSound(named: "Pop")

    static func play() {
        guard isEnabled, let sound else { return }
        sound.stop()
        sound.play()
    }
}
```

- [ ] **Step 3 : event tap**

`DynamicNotch/HUD/MediaKeyTap.swift` :
```swift
//
//  MediaKeyTap.swift
//  DynamicNotch
//
//  Event tap de session sur les événements système (NX_SYSDEFINED). Le
//  rappel C décide immédiatement (MediaKeyPolicy, sans MainActor) de
//  consommer ou relâcher, puis confie l'application de la touche au fil
//  principal. Créé seulement quand le remplacement est actif et
//  l'autorisation Accessibilité accordée ; réactivé si macOS le coupe.
//

import AppKit
import ApplicationServices
import Combine

/// Données partagées avec le rappel C (thread quelconque).
final class MediaKeyTapContext: @unchecked Sendable {
    let policy: MediaKeyPolicy
    let deliver: @Sendable (MediaKeyEvent) -> Void
    var port: CFMachPort?

    init(policy: MediaKeyPolicy, deliver: @escaping @Sendable (MediaKeyEvent) -> Void) {
        self.policy = policy
        self.deliver = deliver
    }
}

private func mediaKeyTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<MediaKeyTapContext>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = context.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, // NX_SYSDEFINED
          let nsEvent = NSEvent(cgEvent: event),
          let keyEvent = MediaKeyEvent.decode(
              subtype: Int(nsEvent.subtype.rawValue),
              data1: nsEvent.data1,
              modifiers: nsEvent.modifierFlags
          ),
          context.policy.shouldConsume(keyEvent.key)
    else { return Unmanaged.passUnretained(event) }

    context.deliver(keyEvent)
    return nil
}

@MainActor
final class MediaKeyTap {
    static let shared = MediaKeyTap()

    private var router: MediaKeyRouter?
    private var context: MediaKeyTapContext?
    private var source: CFRunLoopSource?
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Installé une seule fois, au lancement.
    func install(router: MediaKeyRouter) {
        guard self.router == nil else { return }
        self.router = router
        context = MediaKeyTapContext(policy: router.policy) { event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { MediaKeyTap.shared.router?.apply(event) }
            }
        }

        AppSettings.shared.$replaceSystemHUD
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.router?.replaceEnabled = enabled
                self?.refresh()
            }
            .store(in: &cancellables)

        // L'autorisation peut arriver pendant que l'app tourne : relecture toutes les 2 s.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
        refresh()
    }

    /// Ouvre l'invite système d'autorisation Accessibilité.
    func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func refresh() {
        guard let router else { return }
        router.trusted = isTrusted
        router.refreshPolicy()
        let wanted = router.replaceEnabled && router.trusted
        if wanted, source == nil {
            createTap()
        } else if !wanted, source != nil {
            removeTap()
        }
    }

    private func createTap() {
        guard let context else { return }
        let refcon = Unmanaged.passUnretained(context).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << 14),
            callback: mediaKeyTapCallback,
            userInfo: refcon
        ) else {
            Log.app.error("création du tap des touches système impossible")
            return
        }
        context.port = port
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        source = runLoopSource
    }

    private func removeTap() {
        if let port = context?.port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        context?.port = nil
        source = nil
    }
}
```

- [ ] **Step 4 : branchement au lancement**

Dans `DynamicNotch/AppDelegate.swift`, juste après `ActivityWiring.shared.install()`, ajouter :
```swift
        // HUD volume / luminosité : interception des touches si autorisée.
        let mediaKeys = MediaKeyRouter(
            volume: CoreAudioVolumeControl(),
            brightness: DisplayServicesBrightnessControl(),
            hud: .shared,
            policy: MediaKeyPolicy(),
            playFeedback: { VolumeFeedback.play() }
        )
        MediaKeyTap.shared.install(router: mediaKeys)
```

- [ ] **Step 5 : build, tests, lancement, commit**

```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/HUD/MediaKeyTap.swift DynamicNotch/HUD/VolumeFeedback.swift
Tools/build.sh && Tools/test.sh
pkill -x DynamicNotch; open build/Build/Products/Release/DynamicNotch.app; sleep 3; pgrep -x DynamicNotch
```
Expected : `** BUILD SUCCEEDED **` sans nouvel avertissement, `** TEST SUCCEEDED **`, un PID (l'app tourne ; sans autorisation elle est en cohabitation).
```bash
git add -A DynamicNotch DynamicNotch.xcodeproj
git commit -m "feat: interception des touches système et branchement du HUD"
```

---

### Task 6 : état de coque `hud`, carte et indicateur du panneau

**Files :**
- Create : `DynamicNotch/HUD/HUDCardView.swift`
- Modify : `DynamicNotch/Shell/NotchPresentation.swift`, `DynamicNotch/NotchViewModel.swift`, `DynamicNotch/NotchViewModel+Events.swift`, `DynamicNotch/NotchView.swift`, `DynamicNotch/Shell/NotchTopRow.swift`, `DynamicNotchTests/NotchPresentationTests.swift`, `DynamicNotchTests/NotchViewModelTests.swift`

**Interfaces :**
- Consumes : `HUDController`, `HUDState`, `HUDKind`, `HUDIcon` (1–2).
- Produces : `NotchPresentation.hud(HUDKind)` ; `NotchViewModel.init(geometry:activities:hud:)` (`hud: HUDController? = nil` → `.shared`), `NotchViewModel.hud`, `hudObservation` ; `HUDCardView(notchHeight:)`, `HUDLevelBar(level:dimmed:height:)`.

- [ ] **Step 1 : tests qui échouent**

Dans `DynamicNotchTests/NotchPresentationTests.swift`, ajouter :
```swift
    func test_hud_metrics_andMotion() {
        XCTAssertEqual(metrics(.hud(.volume)), ShellMetrics(bodyWidth: 340, bodyHeight: 80, topRadius: 10, bottomRadius: 24, hasShadow: true))
        XCTAssertEqual(metrics(.hud(.brightness), hardware: false).topRadius, 0)
        XCTAssertEqual(NotchPresentation.motion(from: .closed, to: .hud(.volume)), .expand)
        XCTAssertEqual(NotchPresentation.motion(from: .hud(.volume), to: .compact(.charging)), .collapse)
        XCTAssertEqual(NotchPresentation.motion(from: .hud(.volume), to: .hud(.brightness)), .expand)
    }
```

Dans `DynamicNotchTests/NotchViewModelTests.swift` :
1. ajouter la propriété `private var hud: HUDController!` ; dans `setUp()`, après `center = …`, ajouter `hud = HUDController(scheduler: scheduler)` ;
2. dans `makeViewModel()`, remplacer `NotchViewModel(geometry: .preview, activities: center)` par `NotchViewModel(geometry: .preview, activities: center, hud: hud)` ;
3. ajouter en fin de classe :
```swift
    // MARK: HUD

    func test_hud_takesPrecedence_overActivity_thenRestsOnActivity() {
        center.setPersistent(.charging, active: true)
        let vm = makeViewModel()
        XCTAssertEqual(vm.presentation, .compact(.charging))
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(vm.presentation, .hud(.volume))
        hud.show(HUDState(kind: .brightness, level: 0.4))
        XCTAssertEqual(vm.presentation, .hud(.brightness))
        scheduler.advance(by: 1.5)
        XCTAssertEqual(vm.presentation, .compact(.charging))
        vm.destroy()
    }

    func test_hud_doesNotInterruptOpenedPanel() {
        let vm = makeViewModel()
        vm.notchOpen(.boot)
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(vm.presentation, .opened(.tab(.home)))
        vm.notchClose()
        XCTAssertEqual(vm.presentation, .hud(.volume))
        vm.destroy()
    }

    func test_hud_overridesPeek() {
        AppSettings.shared.popOnHoverEnabled = true
        let vm = makeViewModel()
        vm.notchPop()
        XCTAssertEqual(vm.presentation, .peek)
        hud.show(HUDState(kind: .volume, level: 0.5))
        XCTAssertEqual(vm.presentation, .hud(.volume))
        vm.destroy()
    }
```
Run : `Tools/test.sh NotchPresentationTests` → échec de compilation (`.hud` inconnu).

- [ ] **Step 2 : état de coque**

Dans `DynamicNotch/Shell/NotchPresentation.swift` :
- ajouter le cas `case hud(HUDKind)` après `case expanded(ActivityID)` ;
- dans `metrics`, remplacer `case .expanded:` par `case .expanded, .hud:` (même géométrie) ;
- dans `magnitude`, remplacer `case .expanded: 30` par `case .expanded, .hud: 30`.

- [ ] **Step 3 : modèle**

Dans `DynamicNotch/NotchViewModel.swift` :
1. après `let activities: ActivityCenter`, ajouter :
```swift
    let hud: HUDController
    /// Abonnement à `HUDController`, posé par `setupCancellables()`.
    var hudObservation: ActivityObservation?
```
2. remplacer la signature et le début d'`init` par :
```swift
    init(geometry: NotchGeometry = .preview, activities: ActivityCenter? = nil, hud: HUDController? = nil) {
        self.geometry = geometry
        self.activities = activities ?? .shared
        self.hud = hud ?? .shared
```
(le reste d'`init` inchangé) ;
3. remplacer `restingPresentation` par :
```swift
    /// État de repos : le HUD, sinon l'activité en cours, sinon l'encoche nue.
    var restingPresentation: NotchPresentation {
        if let state = hud.current { return .hud(state.kind) }
        guard let display = activities.current else { return .closed }
        return display.mode == .expanded ? .expanded(display.id) : .compact(display.id)
    }
```
4. remplacer `activityDidChange()` par :
```swift
    /// Appelé par `ActivityCenter` et `HUDController` : le panneau ouvert n'est
    /// jamais interrompu ; l'aperçu (survol) ne l'est que par le HUD.
    func activityDidChange() {
        guard !presentation.isOpened else { return }
        if presentation == .peek, hud.current == nil { return }
        transition(to: restingPresentation)
    }
```
5. dans `destroy()`, après `activityObservation = nil`, ajouter `hudObservation?.cancel()` et `hudObservation = nil`.

Dans `DynamicNotch/NotchViewModel+Events.swift`, après le bloc `activityObservation = activities.observe { … }`, ajouter :
```swift
        hudObservation = hud.observe { [weak self] _ in
            self?.activityDidChange()
        }
```

Run : `Tools/test.sh NotchViewModelTests && Tools/test.sh NotchPresentationTests` → verts.

- [ ] **Step 4 : carte et indicateur**

`DynamicNotch/HUD/HUDCardView.swift` :
```swift
//
//  HUDCardView.swift
//  DynamicNotch
//
//  Carte du HUD sous l'encoche (icône, barre, pourcentage) et mini-barre
//  réutilisée par la rangée du haut du panneau ouvert.
//

import SwiftUI

struct HUDCardView: View {
    let notchHeight: CGFloat
    @ObservedObject private var hud = HUDController.shared

    var body: some View {
        let state = hud.current ?? hud.lastShown ?? HUDState(kind: .volume, level: 0)
        VStack(spacing: 0) {
            Spacer(minLength: notchHeight)
            HStack(spacing: 12) {
                Image(systemName: HUDIcon.systemImage(kind: state.kind, level: state.level, isMuted: state.isMuted))
                    .font(.system(size: 22, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30)
                HUDLevelBar(level: state.level, dimmed: state.isMuted, height: 6)
                Text("\(state.percent) %")
                    .font(DS.Typography.bodyEmphasis)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(state.percent)))
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(height: 36)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .foregroundStyle(DS.Color.textPrimary)
        .animation(DS.Motion.micro, value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.kind == .volume ? "Volume \(state.percent) %" : "Luminosité \(state.percent) %"))
    }
}

/// Rail + remplissage ; au minimum un point quand le niveau est nul.
struct HUDLevelBar: View {
    let level: Double
    let dimmed: Bool
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Color.white.opacity(dimmed ? 0.35 : 1))
                    .frame(width: max(height, geometry.size.width * min(1, max(0, level))))
            }
        }
        .frame(height: height)
    }
}
```

Dans `DynamicNotch/NotchView.swift`, dans `content`, après le cas `.expanded`, ajouter :
```swift
        case .hud:
            HUDCardView(notchHeight: vm.deviceNotchRect.height)
                .id("hud")
                .transition(.emerge)
```

Dans `DynamicNotch/Shell/NotchTopRow.swift` :
- ajouter `@ObservedObject private var hud = HUDController.shared` sous `battery` ;
- dans `trailing`, remplacer le bloc `if battery.hasBattery { … }` par :
```swift
            if let state = hud.current {
                HStack(spacing: 6) {
                    Image(systemName: HUDIcon.systemImage(kind: state.kind, level: state.level, isMuted: state.isMuted))
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    HUDLevelBar(level: state.level, dimmed: state.isMuted, height: 4)
                        .frame(width: 60)
                }
                .foregroundStyle(DS.Color.textSecondary)
                .animation(DS.Motion.micro, value: state)
                .transition(.opacity)
            } else if battery.hasBattery {
                Text("\(battery.percent) %")
                    .font(DS.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textSecondary)
                    .contentTransition(.numericText(value: Double(battery.percent)))
                    .animation(DS.Motion.micro, value: battery.percent)
                    .transition(.opacity)
            }
```
  et ajouter au `HStack` de `trailing` le modificateur `.animation(DS.Motion.micro, value: hud.current != nil)`.

- [ ] **Step 5 : tests, build, commit**

```bash
ruby Tools/xcproj.rb add DynamicNotch DynamicNotch/HUD/HUDCardView.swift
Tools/test.sh && Tools/build.sh
```
Expected : `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **` sans nouvel avertissement.
```bash
git add -A DynamicNotch DynamicNotchTests DynamicNotch.xcodeproj
git commit -m "feat: état de coque HUD, carte sous l'encoche et indicateur du panneau"
```

---

### Task 7 : réglages, sandbox, signature, outils Debug

**Files :**
- Modify : `DynamicNotch/NotchSettingsView.swift`, `DynamicNotch.xcodeproj/project.pbxproj` (sandbox), `DynamicNotch/DynamicNotch.entitlements` (seulement si le spike l'a demandé), `Tools/build.sh`, `DynamicNotch/Debug/DebugTools.swift`, `DynamicNotch/Shell/NotchTopRow.swift` (menu Debug)

**Interfaces :**
- Consumes : `AppSettings.replaceSystemHUD`, `volumeFeedback`, `VolumeFeedback.systemPreference`, `MediaKeyTap.shared.isTrusted/requestTrust()` (5) ; `HUDController.shared` (2).
- Produces : section « HUD » des réglages ; `Tools/build.sh` signé si une équipe est disponible ; simulation `hudVolume` / `hudBrightness` ; rendus `hud-volume.png` / `hud-brightness.png`.

- [ ] **Step 1 : section « HUD » des réglages**

Dans `NotchSettingsView` :
1. ajouter `@State private var hudTrusted = MediaKeyTap.shared.isTrusted` avec les autres propriétés ;
2. dans `body`, dans la première colonne (`VStack` qui contient `behaviorSection`), ajouter `hudSection` sous `behaviorSection` ;
3. ajouter, avant `// MARK: display` :
```swift
    // MARK: HUD

    private var hudSection: some View {
        sectionCard(title: "HUD volume et luminosité", systemImage: "speaker.wave.2") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Toggle(isOn: $settings.replaceSystemHUD) {
                    settingLabel("Remplacer le HUD de macOS",
                                 subtitle: "Les touches volume et luminosité s'affichent dans l'encoche")
                }
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: hudTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(hudTrusted ? DS.Color.success : DS.Color.warning)
                    Text(hudTrusted ? "Accessibilité autorisée" : "Accessibilité non autorisée")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                    Spacer()
                    if !hudTrusted {
                        DSButton("Ouvrir Réglages Système", role: .secondary, size: .small) {
                            MediaKeyTap.shared.requestTrust()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                Toggle(isOn: Binding(
                    get: { settings.volumeFeedback ?? VolumeFeedback.systemPreference },
                    set: { settings.volumeFeedback = $0 }
                )) {
                    settingLabel("Son lors du changement de volume", subtitle: nil)
                }
            }
        }
        .onAppear { hudTrusted = MediaKeyTap.shared.isTrusted }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            hudTrusted = MediaKeyTap.shared.isTrusted
        }
    }

```
4. dans `confirmAndReset()`, ajouter `settings.replaceSystemHUD = true` et `settings.volumeFeedback = nil`.

- [ ] **Step 2 : sandbox désactivée**

```bash
sed -i '' 's/ENABLE_APP_SANDBOX = YES;/ENABLE_APP_SANDBOX = NO;/g' DynamicNotch.xcodeproj/project.pbxproj
grep -c "ENABLE_APP_SANDBOX = NO;" DynamicNotch.xcodeproj/project.pbxproj
```
Expected : `2`. Si le résultat du spike (tâche 0) a identifié une clé `hardened-process` qui bloque DisplayServices, la retirer de `DynamicNotch/DynamicNotch.entitlements` maintenant (sinon ne pas toucher au fichier).

- [ ] **Step 3 : build signé si possible**

Remplacer tout `Tools/build.sh` par :
```bash
#!/bin/bash
# Construit l'app dans build/Build/Products/<Configuration>.
# Argument optionnel : Debug ou Release (défaut).
# Signature : si DEVELOPMENT_TEAM est défini, ou si un certificat « Apple Development »
# est dans le trousseau, build signé avec cette équipe (l'autorisation Accessibilité
# tient alors d'un build à l'autre). Sinon, build non signé.
set -o pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
if [ -z "$DEVELOPMENT_TEAM" ]; then
  DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1)
fi
if [ -n "$DEVELOPMENT_TEAM" ]; then
  echo "Signature : équipe $DEVELOPMENT_TEAM"
  SIGN_ARGS=(CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" -allowProvisioningUpdates)
else
  echo "Signature : aucune (build non signé)"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration "$CONFIG" \
  -derivedDataPath build "${SIGN_ARGS[@]}" \
  build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v "appintentsmetadataprocessor" | tail -60
```
Run : `Tools/build.sh` → la première ligne indique le mode ; `** BUILD SUCCEEDED **`.

- [ ] **Step 4 : outils Debug**

Dans `DynamicNotch/Debug/DebugTools.swift` :
- dans `ActivitySimulator.run(_:center:)`, avant `default:`, ajouter :
```swift
            case "hudVolume":
                HUDController.shared.show(HUDState(kind: .volume, level: 0.62))
            case "hudBrightness":
                HUDController.shared.show(HUDState(kind: .brightness, level: 0.4))
```
- dans `StateRenderer.renderAll(to:)`, après la boucle des activités, ajouter :
```swift
            states.append(("hud-volume", .hud(.volume)))
            states.append(("hud-brightness", .hud(.brightness)))
```
  et, dans la boucle de rendu, juste avant `let vm = NotchViewModel(geometry: geometry)`, ajouter :
```swift
                if case let .hud(kind) = state {
                    HUDController.shared.show(HUDState(kind: kind, level: kind == .volume ? 0.62 : 0.4))
                }
```
Dans `DynamicNotch/Shell/NotchTopRow.swift`, dans `NotchMoreMenu.show(for:)`, remplacer `for name in ActivityID.samples.map(\.debugName)` par `for name in ActivityID.samples.map(\.debugName) + ["hudVolume", "hudBrightness"]`.

- [ ] **Step 5 : build, tests, rendu, commit**

```bash
Tools/test.sh && Tools/build.sh Debug
OUT="$TMPDIR/notch-states-hud" && rm -rf "$OUT"
build/Build/Products/Debug/DynamicNotch.app/Contents/MacOS/DynamicNotch --render-states "$OUT"
```
Expected : `** TEST SUCCEEDED **`, 28 états. Ouvrir `hud-volume.png` et `hud-brightness.png` : carte 340 pt sous l'encoche, icône, barre, pourcentage, rien de tronqué.
```bash
git add -A DynamicNotch Tools DynamicNotch.xcodeproj
git commit -m "feat: réglages du HUD, sandbox désactivée, build signé si possible, outils Debug"
```

---

### Task 8 : vérification finale et documentation

**Files :**
- Modify : `README.md`, `DynamicNotchTests/README.md`

- [ ] **Step 1 : documentation**

Dans `README.md` :
- dans « Highlights », ajouter après la puce des onglets :
```markdown
- **Volume & brightness HUD** — replaces the macOS HUD with a card that slides out
  of the notch (needs Accessibility permission; falls back to showing it alongside
  the system HUD without it). Built-in display brightness only.
```
- dans « Build », ajouter à la fin :
```markdown
To keep the Accessibility permission between builds, sign with your free personal
team: add your Apple ID in Xcode → Settings → Accounts, then `Tools/build.sh`
picks the "Apple Development" certificate automatically (or set `DEVELOPMENT_TEAM`).
```
Dans `DynamicNotchTests/README.md`, ajouter au tableau : `MediaKeyTests`, `HUDControllerTests`, `SystemControlsSmokeTests` (lecture seule), `MediaKeyRouterTests`, avec une ligne chacun.

- [ ] **Step 2 : suite, Release, relance**

```bash
Tools/test.sh && Tools/build.sh
pkill -x DynamicNotch; open build/Build/Products/Release/DynamicNotch.app; sleep 3; pgrep -x DynamicNotch
```
Expected : `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`, un PID.

- [ ] **Step 3 : contrôles à l'œil (utilisateur)**

À faire par l'utilisateur, une fois le compte Apple ajouté dans Xcode, le build refait (`Tools/build.sh`) et DynamicNotch autorisé dans Réglages Système > Confidentialité > Accessibilité :
1. volume +/− : carte sous l'encoche, HUD d'Apple absent ; ⌥⇧ pas fin ;
2. muet : icône barrée, barre atténuée ;
3. luminosité +/− sur l'écran intégré ;
4. AirPods ou casque Bluetooth : le volume change bien ;
5. panneau ouvert : mini-barre à droite de l'encoche ;
6. autorisation retirée : HUD d'Apple de retour, carte maison pour le volume.

- [ ] **Step 4 : commit**

```bash
git add README.md DynamicNotchTests/README.md
git commit -m "docs: HUD volume et luminosité, signature pour l'autorisation"
```
