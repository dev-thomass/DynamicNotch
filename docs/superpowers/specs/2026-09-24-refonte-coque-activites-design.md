# Refonte de la coque et moteur d'activités — design

Date : 2026-09-24 · Branche : `refonte/coque-activites`
Périmètre : sous-projets 1 (fondations « système ») et 2 (activités ponctuelles)
de la refonte de DynamicNotch. Les réglages natifs (sous-projet 3) et la remise
à plat des widgets (sous-projet 4) font l'objet de specs séparées.

## Contexte et problèmes constatés

Audit du 2026-09-24 sur MacBook Pro 14" M4 Pro, macOS 26.6.2, écran 1512×982 pt @2x,
encoche 185×32 pt (aux areas : gauche 0→663, droite 848→1512).

- **Flou** : silhouette rendue à `notchOpacity = 0.95` (le fond transparaît),
  texte des ailes en 9 pt SF Rounded (éclair 5,5 pt), `scaleEffect` au survol sur
  des vues contenant du texte, double bordure `.stroke` + `.strokeBorder`
  décalée d'un demi-point, halos d'ombre de 16 à 28 pt, transition d'ouverture
  en `.scale` sur tout le contenu.
- **Adaptation imparfaite** : encoche centrée mathématiquement (x = 663,5 au lieu
  de 663), coins en courbes quadratiques r = 8, ailes de largeur fixe 60 pt,
  fenêtre de toute la largeur × 620 pt reconstruite à chaque
  `didChangeScreenParameters`.
- **Pas d'animation d'événement** : `BatteryMonitor` interroge IOKit toutes les
  10 s ; aucune notion d'activité ponctuelle ; un seul ressort pour tout ; pas
  de continuité géométrique entre états.
- **Performance** : `StopwatchModel` (30 Hz) observé à la racine de `NotchView`.

## Décisions validées

| Sujet | Décision |
|---|---|
| Référence | Mélange : animations façon Dynamic Island, réglages natifs macOS (plus tard) |
| Approche | A — refondre la coque, conserver les widgets |
| Panneau ouvert | Noir opaque, cartes gris système sombre, sans halo |
| Ouverture | Survol = aperçu + haptique, clic = ouvrir |
| Modèle d'activité | Variante B : état étendu bref puis repli en ailes persistantes |
| Activités du lot | Branchement, débranchement, batterie faible, fin de phase Pomodoro, chrono, fichiers déposés, AirDrop envoyé, changement de morceau |

## 1. Géométrie et netteté

### `NotchGeometry` (nouveau, valeur pure, testable)

Construit à partir d'un `ScreenDescriptor` (frame, `backingScaleFactor`,
`safeAreaInsets.top`, aux areas gauche/droite, hauteur de barre de menus) — une
struct extraite de `NSScreen` pour pouvoir tester sans écran réel.

- Encoche matérielle : `x = auxLeft.maxX`, `largeur = auxRight.minX − auxLeft.maxX`,
  `hauteur = safeAreaInsets.top`. Plus de centrage calculé.
- Aux areas absentes ou aberrantes mais `safeAreaInsets.top > 0` : repli
  heuristique existant (12 % de la largeur), centré puis arrondi au pixel.
- Pas d'encoche : pilule de hauteur `NSStatusBar.system.thickness` (arrondie au
  pixel), largeur 190 pt, centrée.
- Toutes les valeurs de sortie passent par `pixelAligned(_:scale:)` :
  `(v * scale).rounded() / scale`.
- Expose `hardwareNotchRect`, `hasHardwareNotch` et un `windowFrame` (voir plus bas).

### `NotchShape` (réécrit)

- Oreilles concaves en haut (rayon `topRadius`, 6 pt fermé) et coins bas continus
  (courbes cubiques approchant le squircle Apple, `bottomRadius` 10 pt fermé,
  jusqu'à 24 pt étendu / ouvert).
- `animatableData` = `AnimatablePair` de (largeur du corps, hauteur, rayon bas,
  rayon haut). La forme est dessinée **centrée dans un canevas de taille fixe**
  (la fenêtre) : seule la géométrie du tracé est interpolée ; aucune animation de
  `frame` ni de `scaleEffect` sur la coque.
- Variante pilule (pas d'encoche) : même forme avec `topRadius = 0` et
  `bottomRadius = hauteur / 2`, ce qui garde un seul chemin de code.

### Rendu

- Remplissage `Color.black` opaque. Le réglage `notchOpacity` est supprimé
  (lecture ignorée, clé non migrée).
- Ombre : aucune en `fermé` / `aperçu` / `compact` ; en `étendu` / `ouvert`,
  `black.opacity(0.35)`, rayon 10, y = 4.
- Typographie : SF Pro standard (`design: .default`), chiffres
  `.monospacedDigit()`. Nouvelles échelles dans `DSTokens.Typography` :
  - ailes : 13 pt semibold ;
  - titres d'activité : 15 pt semibold ; valeurs d'activité : 26 pt semibold ;
  - panneau : 13 pt corps, 11 pt minimum.
  Les tokens `.rounded` sont retirés.
- Survol : plus de `scaleEffect` sur du texte. Retour de survol = fond
  `white.opacity(0.08)` → `0.12`, comme les menus macOS.
- Bordures : un seul trait `strokeBorder` de 0,5 pt `white.opacity(0.10)`.
  `dsRimLight` et les tokens `glow*` sont supprimés.

### Fenêtre

- `NotchWindow` garde le style actuel (sans bordure, transparente, niveau
  `.statusBar + 8`, toutes les spaces).
- Cadre = rectangle englobant le plus grand état (panneau ouvert, réglages compris,
  + 24 pt de marge pour l'ombre), centré sur l'encoche, collé en haut de l'écran,
  aligné au pixel. Plus de fenêtre pleine largeur × 620 pt.
- `AppDelegate` ne reconstruit les contrôleurs que si l'ensemble
  `(displayID, frame, auxAreas)` a changé depuis le dernier passage.

### Stockage des réglages

- Le répertoire de persistance passe de `~/Documents/DynamicNotch` à
  `~/Library/Application Support/DynamicNotch`. Migration unique au premier
  lancement : copie des clés encore utilisées, les clés périmées
  (`animationBounce`, `prompterText`, `isProUnlocked`, `notchOpacity`, …) ne sont
  pas reprises. L'ancien dossier est laissé en place.
- Écritures sérialisées sur une file dédiée (fin des écritures concurrentes
  réordonnables), écriture atomique (`.atomic`).

### Cible de déploiement

macOS 14.0 minimum (au lieu de 13.0) pour `@Observable` et
`.contentTransition(.numericText(value:))`.

## 2. Machine d'états et animations

### `NotchPresentation`

```swift
enum NotchPresentation: Equatable {
    case closed
    case peek
    case compact(ActivityID)
    case expanded(ActivityID)
    case opened(OpenedContent)   // .widgets(page:), .menu, .settings
}
```

Remplace `NotchViewModel.Status` et `ContentType`. Portée par un
`NotchModel` `@Observable @MainActor` (un par écran) qui remplace
`NotchViewModel` ; les pages de widgets et leur persistance y sont déplacées
telles quelles.

| État | Taille du corps (pt) | Rayon bas |
|---|---|---|
| `closed` | encoche matérielle (185 × 32) | 10 |
| `peek` | encoche élargie de 12 pt et allongée de 4 pt | 12 |
| `compact` | encoche + largeur d'aile gauche + droite (mesurées, min 36 chacune) | 12 |
| `expanded` | 340 × 80 au total, hauteur d'encoche comprise | 24 |
| `opened` | 600 × 180 ; menu 600 × 200 ; réglages 880 × 560 (inchangé dans ce lot) | 28 |

La largeur des ailes est mesurée via une `PreferenceKey` sur le contenu réel
(arrondie au pixel), pas une constante.

### Ressorts (`DS.Motion`, seuls autorisés pour la coque)

- `expand` : `.spring(response: 0.42, dampingFraction: 0.78)` : ouverture, expansion.
- `collapse` : `.spring(response: 0.32, dampingFraction: 0.95)` : fermeture, repli.
- `micro` : `.spring(response: 0.25, dampingFraction: 0.8)` : aperçu, survol.

Le choix du ressort dépend de la transition (état plus grand → `expand`, plus
petit → `collapse`) ; il est calculé à un seul endroit (`NotchModel.transition(to:)`)
qui enveloppe le changement d'état dans `withAnimation`.

### Chorégraphie du contenu

- Entrée : `.opacity` + `.offset(y: -6)`, délai 0,08 s, animation `expand`.
- Sortie : `.opacity` en 0,12 s, sans délai.
- Aucune transition de contenu n'utilise `.scale`.
- `matchedGeometryEffect` (namespace par écran) entre l'élément principal
  compact et étendu : glyphe batterie, pastille Pomodoro, pochette.
- Chiffres : `.contentTransition(.numericText(value:))` (pourcentage, chrono,
  minuteur Pomodoro, décompte calendrier).

### Interruptions

- Clic pendant `expanded` → `opened` directement, depuis la forme en cours
  (interpolation de ressort continue grâce à `animatableData`).
- Toute transition peut en interrompre une autre ; pas de `DispatchQueue.asyncAfter`
  pour enchaîner des états, uniquement des tâches annulables (`Task` + `sleep`)
  détenues par `ActivityCenter`.

### Observation

- `BatteryMonitor`, `StopwatchModel`, `PomodoroModel`, `CalendarStore`,
  `NowPlayingModel`, `AppSettings` passent en `@Observable`.
- `NotchView` n'observe plus les modèles de widgets. Seule la vue d'aile de
  l'activité active lit le modèle concerné. Les `@StateObject` sur objets reçus
  ou singletons deviennent des propriétés simples (`@Bindable` si besoin).
- L'aile chrono se rafraîchit à la seconde (`TimelineView(.periodic(from:by: 1))`) ;
  l'horloge de 30 Hz du widget ne tourne que lorsque le panneau affiche le chrono.

## 3. Moteur d'activités

### Types

```swift
struct Activity: Identifiable, Equatable {
    let id: ActivityID            // .charging, .unplugged, .lowBattery(level), .pomodoroPhase, .stopwatch, .filesAdded(count), .airDropSent, .nowPlaying
    let kind: Kind                // .transient(duration) | .persistent
    let priority: Int
    let createdAt: Date
}
```

`ActivityCenter` (`@Observable @MainActor`, instance unique partagée par les écrans) :

- `transient: Activity?` (en cours d'affichage), `queue: [Activity]`,
  `persistent: [Activity]` (conditions vraies).
- `post(_:)` : ajoute une ponctuelle ; `setPersistent(_:active:)` : active ou
  désactive une persistante.
- Sortie : `current: (Activity, Mode)?` avec `Mode = .compact | .expanded`.
  - Une ponctuelle en cours → `.expanded` pendant sa durée.
  - Sinon la persistante de plus haute priorité → `.compact`.
  - Sinon `nil` → `closed`.
- Priorités persistantes : Pomodoro (40) > chrono (30) > musique (20) > charge (10).
  Ponctuelles : toujours au-dessus des persistantes. Deux ponctuelles
  → traitées dans l'ordre d'arrivée ; une ponctuelle en file depuis plus de 5 s est
  abandonnée ; une ponctuelle identique à celle en cours la prolonge au lieu de
  s'empiler.
- Si un écran est en `opened`, `NotchModel` ignore `current` et le relit à la fermeture ;
  les ponctuelles arrivées pendant l'ouverture sont abandonnées.
- Horloge injectable (`protocol ActivityClock { func now() -> Date; func sleep(for:) async throws }`)
  pour les tests.

### Sources

| Source | Détection | Ponctuelle | Persistante |
|---|---|---|---|
| Charge | `IOPSNotificationCreateRunLoopSource` (remplace la minuterie de 10 s) ; front montant de `isPluggedIn` | `.charging` 2,2 s : grande batterie (glyph partagé), « En charge », « Pleine dans … » (`kIOPSTimeToFullChargeKey`, masqué si inconnu), % vert | ailes ⚡ + % tant que branché (si l'aile batterie est activée dans les réglages) |
| Débranchement | front descendant de `isPluggedIn` | `.unplugged` 1,5 s : « Sur batterie · 64 % » | — |
| Batterie faible | niveau franchit 20 % puis 10 % en décharge | `.lowBattery` 3 s, batterie rouge, « Batterie faible · 10 % » ; une alerte par seuil, réarmée au branchement | — |
| Pomodoro | `PomodoroModel.advancePhase()` publie un événement | `.pomodoroPhase` 2,5 s : « Pause · 5 min » / « Au travail · 25 min », son `NSSound(named: "Glass")` | ailes pastille de phase + temps restant pendant une phase |
| Chrono | `running` | — | ailes mm:ss |
| Fichiers | `TrayDrop.load(_:)` réussi | `.filesAdded(n)` 1,2 s : ✓ « n fichier(s) ajouté(s) » | — |
| AirDrop | `NSSharingServiceDelegate.sharingService(_:didShareItems:)` | `.airDropSent` 1,2 s : ✓ « Envoyé » | — |
| Musique | Changement de titre dans `NowPlayingModel` | `.nowPlaying` 2 s : pochette, titre, artiste | ailes pochette + barres audio animées pendant la lecture |

Les sources n'importent pas SwiftUI ; elles appellent `ActivityCenter` via une
petite interface (`ActivitySink`) injectée, pour être testables.

### MediaRemote (à vérifier en premier)

Première tâche de l'implémentation : un spike jetable qui vérifie si
`MRMediaRemoteGetNowPlayingInfo` renvoie des données sous macOS 26.6 depuis un
binaire non Apple.
1. Si oui : on garde l'implémentation actuelle et on remplace le polling de 3 s
   par `MRMediaRemoteRegisterForNowPlayingNotifications`.
2. Sinon : adaptateur via `/usr/bin/perl` (approche mediaremote-adapter), à
   isoler derrière `NowPlayingProvider`.
3. Si les deux échouent : l'activité musique est retirée de ce lot et signalée.

### Simulation (Debug uniquement)

Un sous-menu « Simuler une activité » dans le menu de l'app (`#if DEBUG`)
déclenche chaque ponctuelle et bascule chaque persistante.

## 4. Tests et vérification

- **Brancher la cible de tests** `DynamicNotchTests` dans le projet (via Xcode ou
  le gem `xcodeproj`) ; corriger `PersistTests` (store thread-safe, attente de
  l'écriture).
- **Tests unitaires :**
  - `NotchGeometry` : encoche 185 pt de l'écran de référence → x = 663 ;
    aux areas absentes ; pas d'encoche ; alignement au pixel à 1x et 2x.
  - `ActivityCenter` avec une horloge factice : priorités, file, expiration à 5 s,
    prolongation, retour à la persistante, suppression pendant `opened`.
  - Détection des fronts de charge et des seuils de batterie faible, à partir de
    dictionnaires IOPS factices.
  - `NotchModel.transition(to:)` : choix du ressort `expand` / `collapse`.
- **Vérification visuelle :** captures d'écran de chaque état via le menu de
  simulation (nécessite l'autorisation d'enregistrement de l'écran pour le
  terminal, sinon captures fournies par l'utilisateur), et contrôle au pixel
  du calage de la forme `closed` sur l'encoche physique.
- **Build Release** sans warnings nouveaux.

## Hors périmètre

- Fenêtre Réglages native (sous-projet 3) : les réglages restent dans le panneau
  ouvert, seule leur typographie suit les nouveaux tokens.
- Bugs et animations internes des widgets (sous-projet 4), sauf ce qui est requis
  ici : publication d'événements par Pomodoro, TrayDrop et Share, et observation
  `@Observable`.
- Plusieurs activités affichées simultanément (îlot scindé en deux).

## Amendements (rédaction du plan, 2026-09-24)

La lecture détaillée du code pendant la rédaction du plan a conduit à ces ajustements.
Ils remplacent les passages correspondants plus haut.

1. **`@Observable` reporté au sous-projet 4.** `NotchViewModel` garde son nom et reste
   `ObservableObject` (18 fichiers en dépendent, et `@PublishedPersist` exige
   `ObservableObject`). Il devient `@MainActor`, et `status` + `contentType` sont
   remplacés par `presentation: NotchPresentation` (`contentType` reste un accesseur
   calculé). Le problème de performance est réglé autrement : `NotchView`
   n'observe plus aucun modèle de widget, chaque vue d'aile observe seulement son
   modèle (`@ObservedObject`), et le chrono calcule son temps à partir de dates
   (plus de minuterie à 30 Hz ; affichage via `TimelineView`). La cible macOS 14
   est conservée (`MainActor.assumeIsolated`, `onChange` à deux paramètres).
2. **Largeur des ailes** : calculée à partir d'un gabarit typographique par activité
   (« 100 % », « 00:00 », « 60 min »), mesuré avec `NSFont` en 13 pt semi-gras à
   chiffres fixes, et non par `PreferenceKey`. C'est déterministe, testable, sans
   boucle de layout et sans « respiration » quand les chiffres changent. Les deux
   ailes ont la même largeur (la coque reste centrée sur l'encoche).
3. **Ailes calendrier conservées** (activité persistante `calendarSoon`, priorité 15,
   entre musique et charge) pour ne pas régresser par rapport à l'app actuelle.
4. **Minuterie d'`ActivityCenter`** : un `ActivityScheduler` injectable qui renvoie
   un travail annulable (`ScheduledWork`) remplace l'horloge + `Task.sleep`. Les
   tests avancent le temps de façon synchrone.
5. **Coins** : quarts de cercle approchés en Bézier (k = 0,448). À ces rayons (6 à 28 pt),
   l'écart avec un squircle est imperceptible.
6. **Migration des données** : le dossier `CopiedItems` (fichiers du plateau) migre
   avec `Config`, tout le répertoire de l'app passe dans Application Support
   (`dataDirectory`).
7. **Simulation** : l'app n'a pas de barre de menus visible, donc le menu « Simuler une
   activité » devient une tuile dans le menu de l'encoche (Debug), plus l'argument
   de lancement `--simulate <activité>`. S'y ajoute `--render-states <dossier>`, qui
   rend chaque état en PNG via `ImageRenderer` : la vérification visuelle ne dépend
   plus de l'autorisation d'enregistrement de l'écran.
8. **Spike MediaRemote** : un premier essai sans lecture en cours renvoie un
   dictionnaire vide, ce qui ne permet pas de conclure. Le spike doit être refait
   avec une musique en lecture (tâche 1 du plan).
9. **Ponctuelles pendant l'ouverture** : la plus récente est rejouée à la fermeture si
   elle a moins de 5 s (sinon abandonnée) — sans cela l'activité « fichiers ajoutés »
   n'apparaissait jamais.
10. **Branchement des sources** par closures (`onChange`, `onPhaseChange`,
    `onItemsAdded`, `Share.onAirDropSent`) plutôt qu'une interface `ActivitySink` ;
    `BatteryMonitor` importe SwiftUI pour sa teinte.
11. **Aile musique** : elle reste désactivée tant que la tâche 12 (MediaRemote) n'est
    pas faite.
