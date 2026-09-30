# Installer DynamicNotch

DynamicNotch transforme l'encoche de ton Mac en petit panneau : fichiers,
AirDrop, notes, Pomodoro, chrono, agenda. Il fonctionne aussi sur un Mac sans
encoche (une pilule apparaît en haut de l'écran).

**Configuration requise :** macOS 14 Sonoma ou plus récent.

## 1. Télécharger

Ouvre la [dernière version](https://github.com/dev-thomass/DynamicNotch/releases/latest)
et télécharge le fichier **DynamicNotch-x.y.z.dmg**.

## 2. Installer

1. Double-clique sur le `.dmg`.
2. Glisse **DynamicNotch** sur le dossier **Applications**.
3. Éjecte le disque « DynamicNotch » (clic droit → Éjecter).

## 3. Premier lancement

DynamicNotch n'est pas distribué par l'App Store : au premier lancement, macOS
affiche « Apple n'a pas pu confirmer que DynamicNotch ne contient pas de
logiciel malveillant ». C'est normal, et ça n'arrive qu'une fois.

**Méthode la plus simple — le Terminal** (Applications → Utilitaires →
Terminal), colle cette ligne puis appuie sur Entrée :

```bash
xattr -dr com.apple.quarantine /Applications/DynamicNotch.app && open /Applications/DynamicNotch.app
```

**Ou sans Terminal :**

1. Double-clique sur DynamicNotch dans Applications, puis clique sur **OK**
   (ou « Terminé ») dans l'alerte.
2. Ouvre **Réglages Système → Confidentialité et sécurité**.
3. Tout en bas, à côté de « DynamicNotch a été bloqué », clique sur
   **Ouvrir quand même**, puis confirme avec ton mot de passe.

L'encoche s'ouvre toute seule au premier lancement : c'est bon signe.

## Utilisation

- **Survole** l'encoche pour l'aperçu, **clique** pour ouvrir le panneau.
- **Glisse un fichier** sur l'encoche pour le garder sous la main ou
  l'envoyer par AirDrop.
- Le menu **« … »** du panneau donne accès aux **Réglages** et à **Quitter**.
- Pour lancer DynamicNotch à chaque démarrage : Réglages → Comportement →
  « Lancer à l'ouverture de session ».
- Pour voir tes rendez-vous, clique sur « Autoriser l'agenda » dans l'onglet
  Agenda.

## Mises à jour

Rien à faire : DynamicNotch vérifie une fois par jour s'il existe une nouvelle
version et te propose de l'installer en un clic. Tu peux aussi vérifier à la
main : Réglages → Mises à jour → **Rechercher les mises à jour**.

## Désinstaller

1. Quitte DynamicNotch (menu « … » → Quitter).
2. Mets `/Applications/DynamicNotch.app` à la corbeille.
3. Facultatif, pour effacer aussi tes réglages et fichiers déposés : supprime
   le dossier `~/Library/Application Support/DynamicNotch`.

## Un souci ?

- **« DynamicNotch est endommagé »** : relance la commande Terminal de
  l'étape 3.
- **Rien ne s'affiche** : vérifie qu'une seule copie tourne (Moniteur
  d'activité), puis relance l'app depuis Applications.
- Sinon, [ouvre un ticket](https://github.com/dev-thomass/DynamicNotch/issues).
