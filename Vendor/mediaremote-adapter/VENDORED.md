# mediaremote-adapter (vendored)

Source : https://github.com/ungive/mediaremote-adapter
Commit : 29718252613a5b0e210bdc64de0bd944ab379706 (2026-09-30)
Licence : BSD 3-Clause (voir LICENSE)

Copie sans modification de `bin/`, `include/` et `src/{adapter,private,utility}`
(le client de test et les scripts de développement ne sont pas repris).

Le framework est compilé à chaque build par `Tools/build-mediaremote-adapter.sh`
(phase « Build MediaRemoteAdapter » de la cible DynamicNotch) et copié dans
`DynamicNotch.app/Contents/Frameworks/`. L'app ne le lie pas : elle le passe
au script Perl, lancé avec `/usr/bin/perl`, binaire système autorisé à lire
MediaRemote depuis macOS 15.4.

Mise à jour : recopier ces dossiers depuis le dépôt et changer le commit ci-dessus.
