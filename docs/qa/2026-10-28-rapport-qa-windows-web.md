# Rapport QA — client Daccord (Windows + web) — 28 octobre 2026

Build testé : `idris/main` @ `ceba851d` (version 0.2.27+6), identique à
l'installeur Windows (`%LOCALAPPDATA%\Programs\Daccord`, 25/10 17:20) et au
client web de la communauté (serveur
Accord de la communauté, espace « Maison », compte `idrissgaba`).

Méthode : parcours manuel piloté (Chrome pour le web, PowerShell/Win32 pour la
fenêtre Windows), chaque constat vérifié à l'écran puis rattaché au code.
Un seul compte était disponible : les scénarios à deux utilisateurs (non-lus,
notifications, indicateur de saisie, DM reçus) n'ont pas pu être validés.

---

## 1. Bugs

Sévérité : **P1** = bloquant / perte de fonction, **P2** = gênant au quotidien,
**P3** = cosmétique ou écart mineur.

### P1

| # | Plateforme | Constat | Reproduction | Attendu (Discord) | Piste / cause |
|---|---|---|---|---|---|
| B1 | Windows | Relancer l'app quand elle tourne déjà dans la zone de notification ouvre une **2ᵉ instance avec une fenêtre grise vide**, qui reste bloquée (même après avoir tué la 1ʳᵉ). | Fermer la fenêtre (réduite dans le tray) → double-cliquer le raccourci Daccord. | Une seule instance : la fenêtre existante est restaurée au premier plan. | Aucune garde single-instance (`windows/runner`, `lib/main.dart`). Ajouter un mutex nommé + restauration de la fenêtre (ou `windows_single_instance`). |
| B2 | Web | **Shift+Entrée envoie le message** au lieu d'insérer un retour à la ligne. | Taper « ligne 1 », Shift+Entrée, « ligne 2 » → deux messages partent. | Shift+Entrée = nouvelle ligne. | `composer.dart` `_onComposerKey` ignore tout sur `kIsWeb` et le champ est en `TextInputAction.send` ; `composer_input.dart` note que seuls les embedders desktop réclament le chord. Gérer Shift+Entrée aussi sur le web (ou passer en `newline` + envoi sur Entrée simple). |
| B3 | Web + Windows | En **édition de message**, Entrée insère un retour à la ligne au lieu de sauvegarder, et **Échap n'annule pas**. | Clic droit → Edit → Entrée / Échap. | Entrée = sauvegarder, Échap = annuler, Shift+Entrée = nouvelle ligne. | `message_row.dart` `_buildEditor` : `TextField(maxLines: 6, onSubmitted: _saveEdit)` sans `textInputAction` ni `onKeyEvent` (`onSubmitted` n'est jamais atteint en multi-lignes). |
| B4 | Web | Annuler/refuser l'invite de **partage d'écran** du navigateur laisse l'UI en état « partage actif » : bouton vert, icône « stop sharing », tuile fantôme dans la grille. | Rejoindre Chill → Partager l'écran → Annuler dans la boîte Chrome. | Retour à l'état « pas de partage ». | `voice.dart` `toggleScreenShare()` (l. 524-545) fait `state.copyWith(selfStream: enable)` même si `_session.setScreenShareEnabled` a échoué ; `voice_session.dart` `_guardMedia` (l. 758) avale l'erreur (`LiveKit screen share toggle failed: NotAllowedError`). Propager l'échec et ne pas basculer l'état. |
| B5 | Serveur (fork) | Tout message contenant un lien affiche **« (edited) »** sans avoir été modifié. | Envoyer `https://example.com`. | Pas de marqueur (l'unfurl n'est pas une édition). | `accordserver/src/db/messages.rs:450` : `UPDATE messages SET embeds = ?, edited_at = now`. Ne pas toucher `edited_at` lors de la mise à jour des embeds. |

### P2

| # | Plateforme | Constat | Reproduction | Attendu | Piste / cause |
|---|---|---|---|---|---|
| B6 | Web + Windows | Après **Reply**, le composer n'a pas le focus : ce qu'on tape part dans le vide. | Survol → icône Répondre → taper. | Focus immédiat dans le composer. | `composer.dart` `didUpdateWidget` ne fait pas `requestFocus()` quand `replyingTo` change. |
| B7 | Web + Windows | **Autocomplétion @mention** : Entrée envoie le message brut (`@idr`) au lieu d'accepter la suggestion ; pas de navigation clavier. | Taper `@idr` puis Entrée. | Entrée/Tab acceptent la suggestion, ↑/↓ naviguent. | `mention_popup.dart` n'intercepte aucune touche. |
| B8 | Web + Windows | **Onglets** : le libellé n'est pas mis à jour au renommage du salon (onglet « Musique » pour le salon « Chill ») ; deux onglets « general » identiques pour deux espaces ; les onglets s'accumulent sans limite. | Renommer un salon ; ouvrir `#general` dans deux espaces. | Libellé vivant, espace distingué, ou pas d'onglets (Discord n'en a pas). | `open_tab.dart` stocke `name` à l'ouverture ; `open_tabs.dart`. |
| B9 | Web | Le **composer DM** affiche « Message # » (nom vide), et le composer DM n'a ni pièces jointes ni stickers. | Icône DM → Kingo. | « Message @Kingo ». | `composer.dart:761` utilise `channelName`, vide pour un DM. |
| B10 | Windows | **Emoji** rendus en carré vide ou en monochrome (🎶, 🔊) alors qu'ils sont en couleur sur le web ; parfois corrigé après redémarrage. | Lire les messages de Bogos Bot dans Chill. | Emoji couleur partout. | Pas de police emoji couleur embarquée ; dépend du fallback Segoe UI Emoji. Embarquer Noto Color Emoji (ou forcer la famille) sur desktop. |
| B11 | Web (thème Dark) | **`code` inline** sans fond visible (indiscernable du texte) ; correct en thème Midnight. | Envoyer `` `code` ``. | Fond gris + monospace. | Couleur de fond du `code_span_builder` trop proche du fond du panneau en Dark (`markdown_viewer`). |
| B12 | Web + Windows | **Sélecteur d'emoji** : feuille modale centrée plein écran (style mobile) au lieu d'un popover ancré ; catalogue réduit (~300 emoji, « Smileys » affiche 66 entrées) ; pas de tons de peau ; pas d'autocomplétion `:smi` dans le composer. | Icône réaction / taper `:smi`. | Popover ancré, catalogue Unicode complet, autocomplétion. | `emoji_picker.dart` (`showModalBottomSheet`), `emoji_catalog.dart`. |
| B13 | Web + Windows | **Markdown brut** affiché dans l'aperçu de réponse, le dialogue des épingles et les résultats de recherche (`**gras** _italique_`). | Répondre à un message formaté. | Texte rendu (ou sans balises). | Aperçus construits sur `message.content` brut. |
| B14 | Web + Windows | **Épingles** : pas de message système « X a épinglé un message » ; dialogue sans horodatage ni « Aller au message ». | Clic droit → Pin → icône épingle. | Message système + saut. | Aucun type de message « pin » géré côté client (`accord_message_events.dart`). |
| B15 | Web + Windows | **Salon vocal** : un clic ouvre une page « Join Voice » au lieu de rejoindre ; une fois connecté, deux barres de contrôle redondantes (sidebar + bas de page), la barre sidebar compresse 8 icônes sur 180 px. | Cliquer « Chill ». | Rejoindre au clic ; une barre « Voice Connected » claire. | `voice_lobby.dart`, `voice_bar.dart`, `voice_view.dart`. |
| B16 | Web + Windows | **Paramètres** (utilisateur et espace) : pages plein écran avec flèche retour, **Échap ne ferme rien** ; la page Voix & Vidéo s'étire sur 1 900 px sans largeur max (toggles à l'extrême droite). | Gear → Échap. | Overlay fermable par Échap, contenu borné (~740 px). | `accord_settings_screen.dart`, `voice_settings_screen.dart`. |
| B17 | Web + Windows | **Carte membre** : modale centrée au lieu d'un popover ancré ; « @Bogos Bot » affiché comme pseudo (avec espace) ; menu contextuel membre réduit (pas « Mentionner », « Rôles », « Bloquer »). | Cliquer un membre. | Popover Discord. | `accord_member_popout.dart:32` (`showDialog`). |

### P3

| # | Plateforme | Constat |
|---|---|---|
| B18 | Web | Nom tronqué « idrissg… » dans le panneau utilisateur (sidebar plus étroite que sur Windows). |
| B19 | Web + Windows | Messages groupés : espacement vertical trop grand entre les lignes d'un même auteur. |
| B20 | Web + Windows | « Events » reste surligné dans la liste après fermeture du dialogue ; la barre d'actions au survol recouvre l'en-tête « idrissgaba used /play ». |
| B21 | Web + Windows | Recherche : pas de filtres (`from:`, `in:`, `has:`), pas de salon/date par résultat. |
| B22 | Web | Pas de route par salon (`/spaces` constant) : impossible de rafraîchir/partager l'URL d'un salon ; le bouton Précédent du navigateur est inerte. |
| B23 | Web + Windows | Suppression : pas d'aperçu du message dans la confirmation, pas de Shift+clic pour sauter la confirmation. |
| B24 | Web + Windows | Thread ouvert dans une modale (Discord : panneau latéral) ; pas de liste des threads du salon. |
| B25 | Web + Windows | Dialogue « Delete space » et autres actions dangereuses accessibles sans saisie du nom (Discord demande de retaper le nom). Non testé jusqu'au bout. |

---

## 2. Écarts de parité Discord (fonctionnalités absentes)

### Raccourcis clavier — rien n'existe hors du composer

Vérifié dans le code : aucun `Shortcuts`/`CallbackShortcuts` applicatif ; seules
touches gérées : Entrée (envoi), Shift+Entrée (desktop natif uniquement),
Ctrl+V (collage), Échap dans 3 dialogues, touche PTT rebindable. À implémenter
(liste Discord par défaut) :

| Raccourci | Action |
|---|---|
| Ctrl+K | Quick switcher (salons, DM, espaces) |
| Alt+↑ / Alt+↓ | Salon précédent / suivant |
| Alt+Shift+↑ / ↓ | Salon non lu précédent / suivant |
| Ctrl+Alt+↑ / ↓ | Espace précédent / suivant |
| Ctrl+Shift+M | Couper / rétablir le micro |
| Ctrl+Shift+D | Sourdine casque |
| ↑ (composer vide) | Éditer son dernier message |
| Échap | Annuler édition/réponse, fermer overlay, marquer le salon lu |
| Shift+Échap | Marquer l'espace comme lu |
| Ctrl+E | Ouvrir le sélecteur d'emoji |
| Ctrl+B / I / U / Ctrl+Shift+X | Entourer la sélection en gras / italique / souligné / barré |
| Tab / ↑ ↓ | Naviguer et accepter mentions, emoji, commandes |
| Ctrl+/ | Afficher la liste des raccourcis |
| Ctrl+Shift+U | Afficher/masquer la liste des membres |
| PageUp / PageDown | Faire défiler l'historique |
| Ctrl+Shift+A | Capture d'écran (desktop) |

Et une page **Keybinds** dans les paramètres (liste, réassignation, PTT global).

### Paramètres utilisateur manquants

Sections présentes : Account, App, System, Advanced. Manquent par rapport à
Discord : **Keybinds**, **Notifications** avancées (sons par événement,
overrides par serveur/salon, aperçu dans les toasts), **Texte & Images**
(aperçus, spoilers, emoji animés, conversions), **Langue**, **Accessibilité**
(saturation, contraste, taille de police), **Apparence** (police, densité au-delà
du mode compact, échelle de zoom par Ctrl+molette), **Confidentialité &
sécurité** (DM depuis les serveurs, demandes d'amis, scan de contenu),
**Activité/statut**, **Paramètres Windows** (lancer au démarrage, démarrer
réduit — seul « Réduire dans la zone de notification » existe).

### Espace / salons

- Pas de menu déroulant sur le nom de l'espace (Discord) ; le bouton ⋮ ne propose
  que Inviter, Créer un salon, Réordonner, Paramètres. Manquent : Créer une
  catégorie, Paramètres de notification de l'espace, Marquer comme lu, Quitter
  l'espace, Profil par espace, Masquer les salons muets.
- Pas de séparateur « NOUVEAUX MESSAGES » dans l'historique (aucune
  implémentation trouvée).
- Pas de sélecteur **GIF** (Tenor/Giphy) dans le composer.
- Pas de quick switcher.
- Threads : pas de panneau latéral ni de liste des threads actifs.
- DM : pas de page d'accueil « Messages privés / Amis » avec liste latérale ;
  tout passe par une modale.

---

## 3. Ce qui fonctionne (vérifié)

- Synchronisation temps réel Windows ↔ web (message envoyé sur Windows reçu
  instantanément sur le web, sans rafraîchir).
- Envoi, édition (via bouton Save), suppression avec confirmation, réponse,
  réaction, épinglage, thread, transfert (dialogue), copier lien/texte,
  marquer non lu, sélection multiple.
- Markdown : gras, italique, barré, `:smile:` → emoji, liens + embed de
  prévisualisation, spoilers.
- Recherche (messages + membres), événements (liste + création), découverte de
  serveurs, ajout de serveur (URL / parcourir / fédéré), DM et amis.
- Paramètres espace : rôles, audit, bannis, signalements, emoji, stickers,
  soundboard, webhooks, AutoMod, écran d'accueil, Arcade, transfert, suppression.
- Niveaux de notification par salon (Défaut / Tout / Mentions / Rien / Muet).
- Statut (En ligne / Inactif / Ne pas déranger / Invisible), statut
  personnalisé, changement de compte, déconnexion.
- Voix : rejoindre / couper micro / quitter sur les deux plateformes ; sur
  Windows, sélecteur de partage d'écran Flutter (Écran / Fenêtre, qualité
  480p→2160p, 15/30/60 fps) et annulation propre par Échap.
- Windows : fermeture vers la zone de notification (processus conservé),
  option correspondante dans les paramètres, fenêtre réduite à 700×500 reste
  utilisable (liste des membres repliée).
- Thèmes (Dark, Midnight, Light, Nord, Monokai, Solarized) et couleur d'accent.

---

## 4. Non testé / limites de la session

- Scénarios à deux comptes : badges non-lus, notifications système, sons,
  indicateur de saisie, réception de DM, mentions reçues.
- Qualité audio/vidéo réelle (seule l'UI a été vérifiée).
- Partage d'écran web : la boîte native de Chrome bloque l'automatisation ;
  le cas « refus » a été simulé en code (B4), le cas « accepté » n'a pas été
  joué.
- Pièces jointes (boîte de fichier native), messages vocaux, sondages,
  stickers, soundboard, Arcade, événements programmés en détail.
- Android, Linux, macOS.

---

## 5. Nettoyage

Messages de test laissés dans `#general` (espace Maison), à supprimer :
« QA test 1 … » (épinglé), « QA reply test @idr », « QA from Windo »,
« QA from Windo`Hello from Windows app », « line one », « Test 😄 ok ».
Le message « line two » a été supprimé pendant le test de suppression.
