# Distribuer DynamicNotch et publier des mises à jour

Tout passe par GitHub : le workflow [`release.yml`](../.github/workflows/release.yml)
compile l'app, la signe, fabrique le `.dmg` et publie une **GitHub Release**.
Les copies installées vérifient chaque jour le flux
`releases/latest/download/appcast.xml` et proposent la mise à jour
([Sparkle](https://sparkle-project.org)).

```
tag v1.2.0 ──► release.yml ──► Release « v1.2.0 »
                                 ├─ DynamicNotch-1.2.0.dmg   ← première installation
                                 ├─ DynamicNotch-1.2.0.zip   ← mise à jour Sparkle (signée EdDSA)
                                 └─ appcast.xml              ← lu par les apps installées
```

## 1. Configuration (une seule fois)

Sur ton Mac, à la racine du dépôt :

```bash
./Tools/setup-updates.sh
```

Le script crée la clé de signature des mises à jour, la range dans ton
trousseau macOS et l'enregistre dans le secret GitHub `SPARKLE_PRIVATE_KEY`
(avec [`gh`](https://cli.github.com) s'il est installé et connecté ; sinon il
copie la clé et ouvre la page des secrets du dépôt).

> ⚠️ **Garde cette clé précieusement** (copie-la aussi dans ton gestionnaire
> de mots de passe). Si tu la perds, les copies déjà installées ne pourront
> plus se mettre à jour : il faudrait renvoyer le `.dmg` à tout le monde. Le
> workflow refuse d'ailleurs de publier avec une clé différente de celle de
> la version précédente.

## 2. Publier une version

**Depuis GitHub (le plus simple)** : onglet **Actions → Release → Run
workflow**, branche `main`, saisis la version (ex. `1.2.0`) et, si tu veux,
une phrase de notes de version. Environ 5 minutes plus tard, la release est en
ligne.

**Ou en ligne de commande :**

```bash
git switch main && git pull
git tag -a v1.2.0 -m "- Nouveau widget météo
- Correction du glisser-déposer"
git push origin v1.2.0
```

Les notes de version viennent, dans l'ordre : du champ « notes » du formulaire,
du message du tag annoté, sinon des commits `feat:` / `fix:` / `perf:` depuis la
version précédente. Elles s'affichent dans la fenêtre de mise à jour.

Règles :

- une version = un numéro jamais utilisé (le workflow refuse les doublons) ;
- le numéro de build (date UTC, ex. `202609301200`) est calculé
  automatiquement : c'est lui que Sparkle compare, il augmente toujours ;
- publie depuis `main`, une fois le code testé.

## 3. Envoyer l'app à un ami

Envoie-lui simplement ce lien :
**<https://github.com/dev-thomass/DynamicNotch/blob/main/docs/INSTALLATION.md>**

Il y trouve le téléchargement, l'installation et l'autorisation du premier
lancement. Ensuite, les mises à jour arrivent toutes seules.

Installe toi aussi ta copie « de tous les jours » depuis la Release : une app
lancée depuis Xcode n'embarque pas la clé et ne se met jamais à jour
(Réglages → Mises à jour affiche « Indisponibles sur cette build »).

## Tester avant de publier

Chaque push sur une branche lance le même workflow **à blanc** : build
universel (Apple Silicon + Intel), signature, `.dmg`, appcast signé avec une
clé jetable — sans rien publier. Le `.dmg` est téléchargeable dans l'onglet
**Actions → le run → Artifacts** (14 jours).

## Signature Apple (facultatif, payant)

Sans compte Apple Developer, l'app est signée « ad hoc » : elle fonctionne et
se met à jour normalement, mais le **premier** lancement demande l'autorisation
décrite dans [INSTALLATION.md](INSTALLATION.md), et macOS peut redemander
l'accès au Calendrier après une mise à jour.

Avec un compte Apple Developer (99 $/an), ajoute ces secrets au dépôt et le
workflow signera avec ton **Developer ID** puis fera notariser l'app par
Apple — plus aucune alerte au premier lancement :

| Secret | Contenu |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Certificat « Developer ID Application » exporté en `.p12`, encodé : `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | Mot de passe choisi à l'export du `.p12` |
| `NOTARY_APPLE_ID` | E-mail de ton compte Apple Developer |
| `NOTARY_TEAM_ID` | Team ID (10 caractères, developer.apple.com → Membership) |
| `NOTARY_PASSWORD` | Mot de passe d'app créé sur appleid.apple.com |

Tu peux passer de ad hoc à Developer ID à tout moment : Sparkle accepte le
changement tant que la clé EdDSA reste la même.

## Fichiers concernés

| Fichier | Rôle |
|---|---|
| `.github/workflows/release.yml` | Build, signature, notarisation, DMG, appcast, Release |
| `Tools/setup-updates.sh` | Création de la clé et du secret (une fois) |
| `Tools/release/sparkle-key.swift` | Génération / vérification des clés EdDSA (CryptoKit) |
| `Tools/release/sign-app.sh` | Signature de l'app et de Sparkle (ad hoc ou Developer ID) |
| `Tools/release/release.py` | Notes de version et `appcast.xml` |
| `Tools/release/DynamicNotch.entitlements` | Entitlements des builds distribuées |
| `DynamicNotch/Updater.swift` | Intégration Sparkle dans l'app |
