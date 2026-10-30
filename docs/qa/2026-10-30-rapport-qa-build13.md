# QA — build 13 (0.2.27+13), 30 octobre 2026

Suite de la session « imitation Discord » : nouveaux sons, picker d'emoji
complet, filtres de recherche, saut vers un message, séparateurs de date et
« NEW », paramètres réorganisés façon Discord, message système d'épingle.
Ce rapport couvre ce qui a été testé sur **Windows**, **Android (émulateur)**
et **web**, et ce qui reste à faire par le propriétaire (déploiements).

## 1. Ce qui change dans le build 13

| Domaine | Changement |
|---|---|
| Sons | 13 sons resynthétisés (`tool/make_sfx.py`) : notes rondes type marimba, attaque douce, filtre passe-bas, courte réverbération stéréo ; sonneries mélodiques. Paramètres › Notifications : un interrupteur et un bouton « écouter » par son. |
| Emoji | Catalogue Unicode complet (1 898 emoji, 299 avec tons de peau) généré depuis `emoji-test.txt` ; popover ancré au bouton sur desktop (rail de catégories, grille continue, barre d'aperçu, sélecteur de ton) ; autocomplétion `:nom:` dans le composer (Tab/Entrée/↑/↓/Échap) ; Ctrl+E ; ton de peau par défaut dans Paramètres › Texte & images. |
| Recherche | `from:@user`, `in:#salon`, `before:AAAA-MM-JJ`, `after:`, `pinned:true` ; salon et date sur chaque résultat ; un résultat saute au message dans l'historique (surligné). |
| Épingles | Horodatage et bouton « Jump » ; message système « X pinned a message to this channel. » (serveur fork, type `pin`, référence le message épinglé). |
| Messages | Séparateur de date (« Today », « Yesterday », « October 29, 2026 ») ; ligne rouge **NEW** avant le premier message non lu ; messages groupés plus serrés ; barre d'actions flottante à cheval sur le bord de la ligne ; dialogue de suppression avec aperçu et Maj pour sauter la confirmation. |
| Vocal | Carte « Voice Connected » dans la colonne : statut + salon / espace, caméra, partage d'écran, soundboard, raccrocher (micro / casque restent dans le panneau utilisateur). |
| Interface | Onglets de salons masqués par défaut (Apparence › Channel tabs) ; « Events » ne reste plus surligné ; sur le web, l'adresse suit le salon ouvert (rafraîchir, partager, bouton Précédent). |
| Paramètres | Barre latérale façon Discord : My Account, Privacy & Safety, Connections / Appearance, Accessibility (mouvement réduit, échelle, saturation), Voice & Video, Text & Images, Notifications, Keybinds, Streamer Mode, Advanced / System, About. |

## 2. Vérifications automatiques

| Vérification | Résultat |
|---|---|
| `flutter analyze --no-fatal-infos` | 0 erreur, 0 avertissement (13 infos héritées) |
| `flutter test` (suite complète) | 1 964 réussis, 1 échec connu Windows-only (`update_installer_io_test`, tarball) |
| Tests ajoutés | catalogue emoji, déclencheur `:emoji`, filtres de recherche, panneau emoji, suggestions `:nom:`, séparateurs de date et NEW, mise en page des paramètres (réécrite) |
| Serveur fork (`cargo check`) | OK |

## 3. QA par plateforme

### Windows (build 13, binaire `build/windows/x64/runner/Release/daccord.exe`)

Lancé avec la session existante. Vérifié par capture d'écran avant l'arrêt de
l'automatisation (demande du propriétaire — un jeu plein écran tournait) :

| Point | Résultat |
|---|---|
| Lancement, reconnexion, dernier salon restauré (lobby vocal « Chill ») | OK |
| Onglets masqués par défaut ; en-tête du salon seul | OK |
| `#general` : séparateurs « October 28, 2026 » et « Yesterday » | OK |
| Messages groupés resserrés, en-tête auteur + heure + (edited) | OK |
| Carte membre, liste des membres par rôle (ADMIN / MEMBERS / OFFLINE) | OK |
| Picker d'emoji, autocomplétion, recherche, épingles, suppression, paramètres, vocal | **Non testé en direct** (automatisation souris/clavier arrêtée). Couvert par les tests de widgets de la section 2 (panneau emoji, suggestions, séparateurs, mise en page des paramètres, dialogue de suppression, ligne d'épingle) — à valider à la main. |

Note : l'application installée (`%LOCALAPPDATA%\Programs\Daccord`) a été
fermée pour lancer le build 13 ; le nouvel installeur est
`D:\ClaudeProjects\daccord-builds\daccord-idris-0.2.27.13-setup.exe`.

### Android (émulateur `Daccord_Test`, Pixel 7 / API 35, APK release x86_64 signé)

| Point | Résultat |
|---|---|
| Installation (versionCode 4013 par-dessus 4001, signature release) | OK |
| Démarrage, splash, écran d'accueil « Browse Servers / Run your own server » | OK |
| Boîte « Run your own server » (Connect by URL, Read the guide) | OK |
| Connexion à `chat.…` et suite | **Bloqué** : l'émulateur n'a pas de session et les identifiants ne sont pas lisibles par cette session (voir §4). |

### Web (build 13 servi en local sur http://127.0.0.1:8787)

| Point | Résultat |
|---|---|
| Chargement, écran « Loading Daccord », conditions d'utilisation | OK |
| Connexion et suite | **Bloqué** : pas d'identifiants ; le déploiement sur le site (qui aurait permis d'utiliser la session Chrome existante) a été refusé par le classifieur. |

## 4. Bloqué par les permissions de la session

Le classifieur de sécurité de la session a refusé :
- la lecture des identifiants (`secrets/admin.txt`) → pas de connexion possible sur le build web local ni sur un émulateur vierge ;
- `scripts/web-deploy.sh` et toute commande d'écriture par ssh sur le serveur (build de l'image serveur, build Linux, déploiement).

Commandes à lancer par le propriétaire (voir section 6).

## 5. Points ouverts après cette session

- Valider à la main sur Windows : popover emoji (clic sur 😀 du composer, Ctrl+E), `:thu` + Tab, recherche `from:@bunx in:#general`, épingle → « Jump », suppression (aperçu, Maj+clic), Paramètres (nouvelles catégories, « écouter » un son), carte « Voice Connected » en vocal, ligne **NEW** après des messages reçus en absence.
- Le message système « X pinned a message » n'apparaît qu'une fois l'image serveur reconstruite et déployée (§6).
- Sons : jugement à l'oreille (ils sont synthétiques, pas ceux de Discord — droits).

## 6. Commandes à lancer par le propriétaire

```bash
# 1. Pousser le client (déjà commité sur idris/main) — fait par la session si autorisé
# 2. Serveur : image du fork avec le message système d'épingle
ssh <srv-gaba>
cd /srv/data/stack/daccord/src/accordserver && git fetch && git reset --hard origin/idris/main   && docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t daccord-accordserver:idris .
cd /srv/data/stack/daccord && scripts/deploy-server.sh
# 3. Linux (.deb + .tgz) depuis le commit du build 13
scripts/linux-build.sh origin/idris/main 0.2.27.13
# 4. Web + installeur Windows + page de téléchargement
#    (daccord-web.tar.gz = build/web du build 13, daccord-setup.exe = daccord-idris-0.2.27.13-setup.exe)
scripts/web-deploy.sh
```
