# Mouvement et panneau — design

Date : 2026-09-26 · Branche : `refonte/mouvement-panneau` (part de `refonte/coque-activites`)
Périmètre : chantier 1 sur 4 de la seconde vague (1 mouvement et panneau, 2 HUD volume et
luminosité, 3 connexions système, 4 outils rapides). Les chantiers 2 à 4 auront leur propre spec
et réutiliseront le langage de mouvement et les composants définis ici.

## Contexte

Retour utilisateur après la refonte de la coque : « gros manque de fonctionnalités, de choses
fluides type Apple, et la couleur n'est pas aussi noire que la vraie encoche ».

- **Couleur** : l'app dessine un noir pur (0, 0, 0, opacité 1, mesuré sur les rendus). L'écart
  vient du rétroéclairage mini-LED de l'écran XDR : l'encoche physique n'a pas de pixels, alors
  que le noir dessiné à côté reste légèrement éclairé quand la barre de menus ou le fond sont
  clairs. On ne peut pas corriger l'écran ; on réduit donc le noir dessiné hors de l'encoche au repos.
- **Fluidité** : l'utilisateur cible l'ouverture et la fermeture, les micro-interactions et le
  panneau lui-même (jugé basique).

## Décisions validées

| Sujet | Décision |
|---|---|
| Panneau | Direction A : accueil composé + onglets dans la rangée de l'encoche |
| Onglets | Accueil, Fichiers, Minuteurs, Notes, Agenda (ordre fixe) |
| Ouverture / fermeture | Morphing façon Dynamic Island (flou + zoom brefs pendant le mouvement, net au repos) |
| Noir au repos | Coque fermée strictement égale à l'encoche ; survol en hauteur seulement |
| Micro-interactions | SF Symbols animés, chiffres qui défilent, survol et appui, dépôts vivants, haptique |

## 1. Mouvement

### Ouverture et fermeture

- La coque garde ses ressorts (`expand` à l'ouverture, `collapse` à la fermeture) ; la règle
  « trois ressorts seulement » reste valable pour la coque. Les transitions de contenu ont leurs
  propres courbes, définies ci-dessous.
- Nouvelle transition de contenu `DS.Motion.emerge`, utilisée pour le panneau ouvert, les ailes
  compactes et les cartes étendues, en remplacement de l'actuelle (fondu + décalage) :
  - entrée : opacité 0 → 1, zoom 0,92 → 1 ancré en haut au centre, flou 6 → 0 pt ; animation
    `.spring(response: 0.38, dampingFraction: 0.82)` avec un délai de 0,03 s ;
  - sortie : opacité 1 → 0, zoom 1 → 0,95, flou 0 → 4 pt ; `.easeIn(duration: 0.18)`, sans délai.
- Implémentation par un `ViewModifier` de transition (opacité, `scaleEffect`, `blur`) appliqué via
  `AnyTransition.modifier(active:identity:)`. Au repos (état identité), zoom = 1 et flou = 0 :
  aucun rendu intermédiaire ne subsiste.
- La règle globale « aucun `scaleEffect` sur du texte » devient « aucun zoom ni flou sur du texte
  **au repos** ». Seules les transitions d'apparition et de disparition peuvent les utiliser.

### Changement d'onglet

- Pastille de sélection sous l'icône active, déplacée par `matchedGeometryEffect` (ressort `micro`).
- Le contenu de l'onglet entrant glisse de 24 pt dans le sens de la navigation (depuis la droite si
  l'onglet cible est à droite de l'actuel, depuis la gauche sinon) avec fondu et flou de 4 pt ;
  le contenu sortant glisse de 24 pt dans le sens opposé. Ressort `expand` à l'entrée, 0,15 s à la sortie.
- La hauteur du panneau suit l'onglet (voir §2) : le changement de hauteur passe par
  `NotchViewModel.transition(to:)` et donc par le ressort adapté (`expand` si plus grand, `collapse` sinon).

### Noir minimal au repos

- `closed` : `topRadius = 0` (plus d'oreilles), largeur et hauteur exactement celles de l'encoche.
  Plus aucun pixel noir hors de l'encoche physique.
- `peek` : même largeur que l'encoche, hauteur + 3 pt, `topRadius = 0`, rayon bas inchangé
  (10 pt sur encoche matérielle).
- Les oreilles (6 pt) apparaissent à partir de `compact` ; 10 pt en `expanded` / `opened` (inchangé).
- Mode pilule (pas d'encoche) : inchangé.

## 2. Structure du panneau

### Rangée de l'encoche (hauteur de l'encoche, 32 pt)

- **À gauche de l'encoche**, `DSTabBar` : 5 icônes SF Symbols 14 pt medium, zones de clic de 30 × 26 pt,
  espacement 4 pt, alignées sur le bord droit de la zone gauche (au plus près de l'encoche) :
  `house.fill` Accueil, `tray.full.fill` Fichiers, `timer` Minuteurs, `note.text` Notes, `calendar` Agenda.
  L'onglet actif : icône blanche sur pastille `white.opacity(0.14)` rayon 8 ; inactifs :
  `textSecondary`. Infobulle (`.help`) avec le nom de l'onglet.
- **À droite de l'encoche** : pourcentage de batterie (`caption`, `textSecondary`, masqué sur Mac
  sans batterie) puis `DSIconButton` `ellipsis` ouvrant un `NSMenu` natif : « Réglages… »,
  « Vider les fichiers… » (confirmation existante), séparateur, « Quitter DynamicNotch » (confirmation existante).
- Supprimés : le titre « DynamicNotch », la navigation ‹ 1/4 ›, le bouton de fermeture,
  `NotchHeaderView`, `NotchMenuView` (son contenu passe dans le menu `…`), `DSNotchHeader`.
- Les réglages restent le contenu `opened(.settings)` actuel (880 × 560). Dans cet état, la zone
  gauche de la rangée affiche un `DSIconButton` `chevron.left` suivi de « Réglages » (`bodyEmphasis`)
  à la place des onglets ; le bouton revient au dernier onglet. Leur refonte native est un chantier ultérieur.

### Tailles

`ContentType` devient :

```swift
enum ContentType: Hashable {
    case tab(NotchTab)
    case settings
}

enum NotchTab: Int, CaseIterable, Codable {
    case home, files, timers, notes, agenda
}
```

| Contenu | Taille du corps (pt) |
|---|---|
| `.tab(.home)`, `.tab(.files)`, `.tab(.timers)` | 640 × 190 |
| `.tab(.notes)` | 640 × 220 |
| `.tab(.agenda)` | 640 × 260 |
| `.settings` | 880 × 560 (inchangé) |

`NotchPresentation.motion(from:to:)` compare la surface du corps pour deux états `opened`
(plus grande → `expand`, plus petite → `collapse`, égale → `expand`) ; le reste de la règle est inchangé.

### Onglets

Contenu posé sous la rangée de l'encoche, marges 16 pt, espacement entre modules 10 pt.

- **Accueil** : trois `DSModule` côte à côte (largeurs 1,2 / 1 / 1) :
  - **Aujourd'hui** : jour de la semaine en `caption`, date en `displayMedium` (« ven. 26 »), puis
    les deux prochains événements du jour (heure en chiffres fixes + titre, une ligne chacun) ou
    « Rien de prévu » ; clic → onglet Agenda. Sans accès au calendrier : bouton « Autoriser l'agenda ».
  - **Fichiers** : miniatures des 3 derniers fichiers (vignettes 36 pt rayon 8) + « +N », ou
    « Glissez des fichiers ici » ; zone de dépôt ; clic → onglet Fichiers.
  - **Actions** : grille 2 × 2 de `DSIconButton` 36 pt avec légende 11 pt : AirDrop (ouvre le
    sélecteur de fichiers, comme la tuile actuelle ; accepte aussi un dépôt), Chrono (démarre ou met en
    pause ; l'icône bascule `play.fill` ↔ `pause.fill`), Pomodoro (démarre ou met en pause),
    Note (ouvre l'onglet Notes et place le focus dans le texte).
- **Fichiers** : l'étagère actuelle (`TrayView`) en pleine largeur, défilement horizontal, avec à
  gauche la zone AirDrop (`ShareView`) en module étroit (120 pt) et un bouton « Tout supprimer »
  (confirmation existante) en bas à droite.
- **Minuteurs** : deux modules de même largeur : chrono (chiffres `displayLarge` à chasse fixe,
  boutons démarrer/pause et remise à zéro) et Pomodoro (anneau de progression continu, phase,
  temps restant, boutons démarrer/pause, passer, remise à zéro). Réutilise `StopwatchModel` et `PomodoroModel`.
- **Notes** : l'éditeur de la note rapide (`NoteView`) en pleine largeur, police `body`.
- **Agenda** : liste des événements du jour (heure de début–fin en chiffres fixes, pastille de la
  couleur du calendrier, titre), défilante ; journée vide → événements de demain sous le titre
  « Demain » ; aucun événement → « Rien de prévu aujourd'hui ni demain » ; sans accès → bouton
  « Autoriser l'agenda ». `CalendarStore` expose une liste `todayEvents` (et `tomorrowEvents`) en
  plus de `nextEvent`.

### Comportements

- Le dernier onglet est persistant (`@PublishedPersist` clé `lastTab`, défaut `.home`) et rouvert
  à chaque ouverture par clic.
- Ouverture par glisser-déposer sur l'encoche → onglet Fichiers (sans modifier `lastTab`).
- Le système de pages (`widgetPages`, `currentPage`, `toggleWidget`, `addPage`, `removePage`,
  `nextPage`, `previousPage`, l'enum `Widget`) et la section « Widgets » des réglages sont supprimés.
  La clé persistée `widgetPages` est ignorée.
- Le widget Now Playing n'a pas d'onglet dans ce chantier (la musique reste désactivée tant que la
  tâche 12 de la spec précédente n'est pas faite) ; son fichier reste en place, non affiché.

## 3. Micro-interactions et composants

### Composants (`DSComponents.swift`)

- `DSModule` : fond `#1c1c1e` (nouveau token `DS.Color.module`), rayon 16 continu, padding 12,
  légende optionnelle `caption` / `textSecondary` en haut ; survol si cliquable : fond
  `white.opacity(0.08)` superposé → 0,14 à l'appui.
- `DSIconButton` : cercle de 30 pt (36 pt en taille `.large`), fond `white.opacity(0.10)`,
  survol 0,16, appui : opacité 0,75 + zoom 0,96 (icône seule, pas de texte à l'intérieur) ;
  ressort `micro` ; déclenche `.symbolEffect(.bounce, value:)` sur l'icône à chaque action.
- `DSTabBar` : voir §2.
- Supprimés s'ils ne servent plus : `DSIconTile`, `DSCard`, `DSPill`, `DSDivider`, `DSNotchHeader`
  (et leurs entrées dans `DSGallery`).

### SF Symbols animés (macOS 14)

- Rebond (`.bounce`) sur l'icône d'une action déclenchée : actions rapides, onglet sélectionné.
- Morphing lecture ↔ pause : `.contentTransition(.symbolEffect(.replace))`.
- AirDrop : `.symbolEffect(.variableColor.iterative)` pendant qu'un envoi est en cours
  (entre `begin()` et le retour du délégué de `Share`).
- Carte « En charge » : l'éclair du glyphe batterie pulse (`.symbolEffect(.pulse)`).

### Chiffres

- Toutes les valeurs affichées avec `.contentTransition(.numericText(value:))` changent dans une
  transaction animée : `.animation(DS.Motion.micro, value: <valeur>)` sur le `Text`
  (pourcentage de batterie, chrono, Pomodoro, décompte de l'agenda, compteurs de fichiers).
- Le chrono de l'aile : `TimelineView` ancré sur `startedAt` et en pause quand le chrono est arrêté.
- L'anneau du Pomodoro : `TimelineView(.animation)` quand il tourne, progression calculée à la date
  courante (plus de saccade toutes les 0,5 s).

### Glisser-déposer

- Zone de dépôt survolée : contour 1 pt `white.opacity(0.35)` au lieu de 0,12, fond
  `white.opacity(0.10)`, icône qui rebondit une fois (`.bounce`) à l'entrée du survol.
- Fichiers ajoutés : insertion avec ressort (`.opacity` + zoom 0,8 → 1 sur la vignette seule).
  Suppression : effet « poof » existant.

### Haptique

Au changement d'onglet, au dépôt accepté et au démarrage d'un minuteur, via le `hapticSender`
existant (motif `.levelChange`, throttlé à 0,5 s, actif seulement si « Retour haptique » est coché).

## 4. Tests et vérification

- **Unitaires** :
  - `NotchPresentation.metrics` : `closed` = encoche exacte, `topRadius` 0 ; `peek` = même largeur,
    +3 pt ; tailles par onglet ; `motion` entre deux onglets de tailles différentes.
  - `NotchViewModel` : ouverture par clic → `lastTab` ; ouverture par dépôt → `.files` sans changer
    `lastTab` ; sélection d'un onglet persiste `lastTab` ; retour depuis les réglages → dernier onglet.
  - Sens de glissement entre onglets (`NotchTab.slideEdge(from:to:)`).
  - `CalendarStore` : tri et filtrage de `todayEvents` / `tomorrowEvents` à partir d'une liste
    d'événements factices (logique extraite en fonction pure).
- **Rendu Debug** : `--render-states` produit en plus un PNG par onglet (`opened-home.png`, …).
- **À l'œil (utilisateur)** : ouverture et fermeture, changement d'onglet, survol, actions
  rapides, dépôt de fichier, encoche fermée invisible.

## Hors périmètre

- HUD volume et luminosité, connexions système, outils rapides (chantiers 2 à 4).
- Réglages natifs (fenêtre macOS) et personnalisation des onglets.
- Lecteur musique.
