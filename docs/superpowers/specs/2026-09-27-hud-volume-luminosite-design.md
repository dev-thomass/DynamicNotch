# HUD volume et luminosité — design

Date : 2026-09-27 · Branche : `refonte/hud-volume-luminosite` (part de `refonte/mouvement-panneau`)
Périmètre : chantier 2 sur 4 de la seconde vague. Remplace le HUD de macOS (volume, muet,
luminosité de l'écran intégré) par une carte qui sort de l'encoche.

## Contexte

Un premier HUD a existé (commits `aafd8ee` → `adcf133`) puis a été retiré le 2026-05-10
(`33f064e`) pour trois raisons : le HUD natif restait visible sans l'autorisation Accessibilité,
latence sur certaines touches, interception fragile (plantage d'isolation MainActor dans le
rappel du tap, volume non modifiable sur Bluetooth/USB via l'élément principal CoreAudio).
Ce design reprend l'idée en corrigeant chacune de ces causes.

## Décisions validées

| Sujet | Décision |
|---|---|
| HUD d'Apple | Remplacé (touches interceptées et consommées) ; cohabitation en repli sans autorisation |
| Forme | B : carte sous l'encoche (icône, barre, pourcentage) |
| Panneau ouvert | Retour dans la rangée du haut (icône + mini-barre à la place de la batterie, 1,5 s) |
| Architecture | Canal HUD dédié, prioritaire sur les activités |
| Signature | Équipe personnelle Apple (compte gratuit ajouté par l'utilisateur dans Xcode) ; ad hoc tant qu'il n'est pas configuré |

## 1. Captation et réglage

### Interception (`MediaKeyTap`)

- `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: 1 << NX_SYSDEFINED (14), …)`, ajouté à la run loop principale.
- Le rappel C ne fait que : décoder l'événement (`NSEvent(cgEvent:)`, `subtype == 8`,
  `data1` → code de touche `(data1 & 0xFFFF0000) >> 16`, état appuyé `((data1 & 0xFF00) >> 8) == 0x0A`,
  répétition `data1 & 0x1`), puis décider synchrone de **consommer** (retour `nil`) ou **relâcher**
  (retour de l'événement) selon une réponse calculée sans bloquer, et poster le traitement sur le
  fil principal (`DispatchQueue.main.async`). Aucun appel isolé au MainActor depuis le rappel.
- Touches gérées : `NX_KEYTYPE_SOUND_UP` (0), `NX_KEYTYPE_SOUND_DOWN` (1), `NX_KEYTYPE_MUTE` (7),
  `NX_KEYTYPE_BRIGHTNESS_UP` (2), `NX_KEYTYPE_BRIGHTNESS_DOWN` (3). Tout le reste est relâché
  (rétroéclairage clavier, lecture/pause, etc.). Les relâchements de touche (key up) des touches
  gérées sont consommés aussi quand l'appui l'a été.
- Consommer une touche n'est décidé que si : l'option « Remplacer le HUD de macOS » est active,
  l'autorisation Accessibilité est accordée, et le contrôle concerné est réglable
  (`VolumeControl.isSettable` / `BrightnessControl.isAvailable`). Sinon : relâchée.
- `kCGEventTapDisabledByTimeout` / `ByUserInput` → réactivation immédiate (`CGEvent.tapEnable`).
- L'autorisation est lue par `AXIsProcessTrusted()` ; relue toutes les 2 s tant qu'elle est refusée
  (le tap est (re)créé dès qu'elle devient accordée), et à chaque ouverture des réglages.

### Volume (`VolumeControl`, implémentation CoreAudio)

- Périphérique : sortie par défaut (`kAudioHardwarePropertyDefaultOutputDevice`), suivie par
  écouteur (changement de sortie → rebranchement des écouteurs).
- Niveau : `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (AudioToolbox,
  `AudioObjectGetPropertyData` / `SetPropertyData`, scope sortie). Muet : `kAudioDevicePropertyMute`.
- `isSettable` : `AudioObjectIsPropertySettable` sur le volume virtuel.
- Écouteurs `AudioObjectAddPropertyListenerBlock` sur volume virtuel et muet (file principale) :
  publient les changements venus d'ailleurs (Centre de contrôle, autre app) au `HUDController`.
- Pas : 1/16 ; avec ⌥⇧ : 1/64 ; borné à [0, 1]. Monter le volume depuis muet dé-mute.
  Baisser jusqu'à 0 ne coupe pas le son (comme macOS).

### Luminosité (`BrightnessControl`, implémentation DisplayServices)

- `dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")`,
  symboles `DisplayServicesGetBrightness(CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32`
  et `DisplayServicesSetBrightness(CGDirectDisplayID, Float) -> Int32`.
- Écran : l'écran intégré (`CGDisplayIsBuiltin`). `isAvailable` = écran intégré présent, symboles
  résolus et lecture réussie. Sinon les touches sont relâchées (macOS gère, y compris écrans externes).
- Pas : 1/16 ; avec ⌥⇧ : 1/64 ; borné à [0, 1].
- Pas d'écouteur : en cohabitation, la luminosité ne produit pas de HUD maison.

### Son de retour

Si `UserDefaults(suiteName: ".GlobalPreferences")?.bool(forKey: "com.apple.sound.beep.feedback")`
vaut vrai (et que le réglage de l'app ne l'a pas désactivé), jouer le son système
`/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff` si présent,
sinon `NSSound(named: "Pop")`, après chaque changement de volume (pas de son pour la luminosité).

## 2. Affichage

### `HUDController`

- `@MainActor final class HUDController: ObservableObject`, instance partagée.
- `@Published private(set) var current: HUDState?` avec
  `struct HUDState: Equatable { var kind: HUDKind; var level: Double; var isMuted: Bool }`,
  `enum HUDKind { case volume, brightness }`.
- `show(_ state: HUDState)` : publie l'état et (re)programme la disparition à 1,5 s via un
  `ActivityScheduler` injectable (réutilise le protocole existant) ; chaque appel prolonge.
- `observe(_:)` → jeton (même modèle qu'`ActivityCenter`) pour les modèles de coque.

### État de coque `hud`

- `NotchPresentation.hud(HUDKind)`. Métriques : `bodyWidth` 340, `bodyHeight` `max(80, notch.height + 48)`,
  `topRadius` oreilles larges (10 sur encoche matérielle, 0 en pilule), `bottomRadius` 24, ombre.
- Ressorts : l'état `hud` a la même « magnitude » qu'`expanded` (30) ; entrée `expand`, sortie `collapse`.
- `NotchViewModel.restingPresentation` : `hud` si `HUDController.current != nil` (et panneau fermé),
  sinon activité, sinon `closed`. Un HUD pendant un aperçu (`peek`) l'emporte.
  Changements de `HUDController.current` → `activityDidChange()` généralisé (`restingDidChange()`).
- Contenu (`HUDCardView`), sous l'encoche comme `ExpandedActivityView` :
  - icône 22 pt : volume `speaker.slash.fill` (muet), `speaker.fill` (0), `speaker.wave.1.fill` (< 1/3),
    `speaker.wave.2.fill` (< 2/3), `speaker.wave.3.fill` ; luminosité `sun.min.fill` (< 0,5) sinon
    `sun.max.fill` ; `.contentTransition(.symbolEffect(.replace))` ;
  - barre : rail 6 pt `white.opacity(0.2)`, remplissage blanc (`opacity(0.35)` si muet), largeur
    animée `DS.Motion.micro` ;
  - pourcentage `DS.Typography.bodyEmphasis`, chiffres fixes, `.numericText(value:)` animé, 44 pt de large.
- Transition d'apparition : `.emerge` ; tant que l'état reste `hud`, seule la barre et le texte bougent
  (même identité de vue pour volume et luminosité : `.id("hud")`).

### Panneau ouvert

`NotchTopRow` : si `HUDController.current != nil`, la zone batterie affiche l'icône (13 pt) et une
mini-barre de 60 × 4 pt à la place du pourcentage de batterie ; transition `.opacity`.

### Plusieurs écrans

Chaque `NotchViewModel` observe `HUDController.shared` : le HUD apparaît sur toutes les encoches.

## 3. Réglages, signature, tests

### Réglages

Section « HUD » dans `NotchSettingsView` :
- « Remplacer le HUD de macOS » (`AppSettings.replaceSystemHUD`, défaut `true`) ;
- état de l'autorisation (« Autorisée » / « Non autorisée ») relu à l'affichage, bouton
  « Ouvrir Réglages Système » (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`)
  qui appelle aussi `AXIsProcessTrustedWithOptions` avec l'invite ;
- « Son lors du changement de volume » (`AppSettings.volumeFeedback`, défaut `nil` → préférence macOS).

### Signature et projet

- `ENABLE_APP_SANDBOX = NO` pour la cible app (Debug et Release).
- `Tools/build.sh` et `Tools/test.sh` : si la variable `DEVELOPMENT_TEAM` est définie (ou si
  `security find-identity -v -p codesigning` trouve un « Apple Development »), construire avec
  `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<id> -allowProvisioningUpdates` ; sinon comportement actuel
  (non signé).
- Tâche initiale : **spike jetable** qui vérifie sous macOS 26 (1) tap de session + consommation des
  touches système, (2) DisplayServices sous runtime renforcé et entitlements « enhanced security »
  (les retirer s'ils bloquent le `dlopen`), (3) écriture du volume principal virtuel. Si (1) échoue,
  arrêt et retour à l'utilisateur.

### Tests unitaires

- Décodage `data1` → `MediaKey` (`.volumeUp`, `.volumeDown`, `.mute`, `.brightnessUp`, `.brightnessDown`,
  `nil` sinon ; appui/relâchement ; répétition).
- `LevelStep.next(level:direction:fine:)` : 1/16, 1/64, bornes.
- `HUDIcon.systemImage(kind:level:muted:)`.
- `HUDController` : apparition, prolongation, disparition à 1,5 s (`ManualScheduler`).
- `MediaKeyRouter` (logique de décision, sans CoreAudio) avec des doublures `VolumeControl` /
  `BrightnessControl` : consomme/relâche selon réglage, autorisation, disponibilité ; applique le pas ;
  dé-mute en montant ; publie le HUD.
- `NotchPresentation.metrics(.hud)` et `motion` ; `NotchViewModel` : priorité HUD > activité > fermé,
  panneau ouvert non interrompu.

### Contrôles à l'œil (utilisateur)

HUD d'Apple absent, volume sur haut-parleurs et Bluetooth, muet, luminosité, appuis rapides,
⌥⇧ fin, retour dans la rangée du haut panneau ouvert, repli sans autorisation.

## Hors périmètre

Luminosité des écrans externes (DDC), rétroéclairage clavier, touches multimédia, choix de la
sortie audio, volume par application.
