# CHANGELOG

---

## v2.0 — 30/03/2026

### 🇫🇷 Français

#### ✨ Refonte complète de l'interface

**Sidebar latérale fixe** : les filtres genre et catégorie sont déplacés dans une barre latérale fixe de 220px à gauche. Chaque filtre affiche un compteur du nombre de jeux correspondants. La sidebar inclut les filtres rapides (Tout, Nouveautés, Expire bientôt), les genres et les modes de jeu. Sur mobile (< 900px), la sidebar se réduit à 48px avec icônes seules.

**Stat cards en grille** : les statistiques passent d'une barre horizontale à 5 cartes individuelles en grille (Wishlist, En promo, Meilleure remise, Prix le plus bas, Prochain scan/Durée).

**Topbar** : barre de recherche + compteur de promos + roue crantée ⚙️ dans une barre supérieure compacte.

**Toolbar de tri** : boutons de tri avec le slider prix dans une barre dédiée sous les stats.

**CSS unifié via variables** : les 3 thèmes (Modern, Classic Steam, Light) utilisent des variables CSS (:root) pour les couleurs, ce qui réduit le code de ~300 lignes de CSS dupliqué à ~100 lignes d'overrides.

#### 🛒 Panier multi-jeux

Une case à cocher (✓) apparaît au survol de chaque vignette. En cliquant dessus, le jeu est sélectionné (bordure bleue) et une barre flottante apparaît en bas de l'écran. Cette barre affiche le nombre de jeux sélectionnés, le prix total et l'économie réalisée.

Le bouton **« 🎮 Ouvrir sur Steam (Web) »** ouvre les pages Steam de tous les jeux sélectionnés. La version Linux génère une page intermédiaire avec des liens cliquables (compatible avec tous les navigateurs). La version PowerShell ouvre directement chaque jeu dans un nouvel onglet via la technique du `<a>.click()` programmé avec un délai de 400ms entre chaque ouverture pour contourner les bloqueurs de popups.

Un tooltip au survol du bouton avertit l'utilisateur que les bloqueurs de pubs/popups peuvent empêcher l'ouverture multiple et qu'il faut autoriser cette page si nécessaire.

#### 📱 Mobile responsive avec hamburger

Sur mobile (< 900px), un bandeau en haut affiche le titre « 🎮 Steam Wishlist Sales Checker v2.0 » avec le menu ⚙️ à droite. Une barre topbar contient la recherche, le compteur de promos et le bouton ☰ qui fait glisser la sidebar avec un overlay sombre. Cliquer sur un filtre referme automatiquement la sidebar pour ne pas masquer les résultats.

#### ❓ Aide intégrée

Un bouton « ❓ Aide » dans la roue crantée ouvre une modale détaillant toutes les fonctionnalités : recherche, filtres, panier, dates de fin de promo, et arguments PowerShell avec création de raccourci Windows.

#### 📊 Métriques

| Fichier | v1.4 | v2.0 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 1175 lignes | 959 lignes | -216 |
| `Steam_Wishlist_Sales_Checker.ps1` | 945 lignes | 900 lignes | -45 |

Le code est plus court malgré l'ajout de fonctionnalités car le CSS est mieux factorisé via les variables CSS.

---

### 🇬🇧 English

#### ✨ Complete UI overhaul

**Fixed sidebar**: genre and category filters moved to a fixed 220px left sidebar. Each filter shows a count of matching games. Sidebar includes quick filters (All, New, Expiring soon), genres and game modes. On mobile (< 900px), sidebar collapses to 48px icons.

**Stat cards grid**: statistics moved from horizontal bar to 5 individual grid cards (Wishlist, On sale, Best discount, Lowest price, Next scan/Duration).

**Topbar**: search bar + promo counter + ⚙️ gear menu in a compact top bar.

**Sort toolbar**: sort buttons with price slider in a dedicated bar below stats.

**Unified CSS variables**: all 3 themes (Modern, Classic Steam, Light) use CSS variables (:root), reducing ~300 lines of duplicated CSS to ~100 lines of overrides.

#### 🛒 Multi-game cart

A checkbox (✓) appears when hovering over each card. Clicking it selects the game (blue border) and a floating bar appears at the bottom of the screen. This bar shows the number of selected games, total price and savings.

The **"🎮 Open on Steam (Web)"** button opens Steam pages for all selected games. The Linux version generates an intermediate page with clickable links (compatible with all browsers). The PowerShell version opens each game directly in a new tab using the programmatic `<a>.click()` technique with a 400ms delay between each opening to bypass popup blockers.

A tooltip on hover warns the user that ad/popup blockers may prevent multiple openings and must be allowed for this page if needed.

#### 📱 Mobile responsive with hamburger menu

On mobile (< 900px), a top banner shows the title "🎮 Steam Wishlist Sales Checker v2.0" with the ⚙️ menu on the right. A topbar contains the search, promo counter and the ☰ button that slides the sidebar with a dark overlay. Clicking a filter automatically closes the sidebar to avoid hiding results.

#### ❓ Built-in help

A "❓ Help" button in the gear menu opens a modal detailing all features: search, filters, cart, end-of-sale dates, and PowerShell arguments with Windows shortcut creation.

#### 📊 Metrics

| File | v1.4 | v2.0 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 1175 lines | 959 lines | -216 |
| `Steam_Wishlist_Sales_Checker.ps1` | 945 lines | 900 lines | -45 |

Code is shorter despite added features because CSS is better factored via CSS variables.

---

## v1.4 — 28/03/2026

### 🇫🇷 Français

#### ✨ Nouvelles fonctionnalités

**Dates de fin de promotion (optionnel, countdown en temps réel)**
Une fonction optionnelle scrape les pages store Steam pour récupérer les dates de fin de promotion. Un countdown en temps réel s'affiche sous chaque carte ("⏳ 2j 5h 34min" qui défile chaque seconde). Les promos expirant dans ≤3 jours sont en rouge gras. Le scraping supporte deux patterns Steam : le timestamp `InitDailyDealTimer` (précis à la seconde) et le texte "prend fin le DD mois" / "Offer ends DD month" (français + anglais, heure fixée à 18:00). Activation Linux : `swsc:endofsales-on` dans la barre de recherche. PowerShell : `-ScrapeEndDates`.

**Filtre "Expire bientôt"**
Un bouton rouge "⏳ Expire bientôt" apparaît automatiquement quand des dates de fin sont disponibles. Affiche uniquement les jeux dont la promo expire dans moins de 48 heures. Se combine avec tous les autres filtres (recherche, genre, catégorie, prix, nouveautés).

**Roue crantée (⚙️)**
Les boutons "Classic Steam", "Vider le cache" et "Actualiser" sont remplacés par un menu ⚙️. Regroupe : Actualiser le scan, Vider le cache (en rouge), choix de thème avec checkmark, et un lien "Calendrier des Soldes" vers SteamDB.

**Thème Light (☀️)**
Nouveau thème clair : fond #f0f2f5, cartes blanches, accent bleu #1a73e8, vert #2e7d32. Complet sur tous les éléments (cartes, filtres, stats, gear menu, slider, badges, countdown). Persistant via cookie.

#### 🔧 Modifications techniques

- **Bash** : variables `ENDOFSALES_FLAG` / `SALE_DATES_FILE`, étape 6 de scraping avec double pattern (regex `InitDailyDealTimer` + grep `prend fin le|Offer ends`), conversion FR→EN des mois via sed, `sale_dates.json`, JS countdown via `setInterval(1000)`, cookie `swsc_endofsales`, `data-endts` sur les cartes, filtre `matchExpiring` (48h), bouton `expiringBtn` auto-visible, `setTheme()` 3 thèmes, menu gear avec `click` hors zone pour fermer, CSS Light complet (59 règles).
- **PowerShell** : paramètre `-ScrapeEndDates`, scraping avec double pattern (regex + mapping 24 mois FR/EN), `$SaleDates` → `SALE_DATES` injecté dans le HTML, countdown identique, `toggleExpiring()`, CSS Light identique, gear menu identique.
- **run.php** : handler `endofsales=on` (crée flag + lance scan) et `off` (supprime flag + données).

#### 📊 Métriques

| Fichier | v1.3 | v1.4 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 958 lignes | 1175 lignes | +217 |
| `Steam_Wishlist_Sales_Checker.ps1` | 741 lignes | 945 lignes | +204 |
| `run.php` | 48 lignes | 65 lignes | +17 |

---

### 🇬🇧 English

#### ✨ New features

**End-of-sale dates (optional, live countdown)**
An optional feature scrapes Steam store pages to retrieve promotion end dates. A live countdown displays below each card ("⏳ 2d 5h 34min" ticking every second). Promos expiring within ≤3 days are shown in bold red. Scraping supports two Steam patterns: the `InitDailyDealTimer` timestamp (precise to the second) and the text "prend fin le DD month" / "Offer ends DD month" (French + English, time defaults to 18:00). Linux activation: `swsc:endofsales-on` in the search bar. PowerShell: `-ScrapeEndDates`.

**"Expiring soon" filter**
A red "⏳ Expire bientôt" button automatically appears when end dates are available. Displays only games whose promo expires within 48 hours. Combines with all other filters (search, genre, category, price, new).

**Gear menu (⚙️)**
"Classic Steam", "Clear cache" and "Refresh" buttons replaced by a ⚙️ dropdown menu. Groups: Refresh scan, Clear cache (red), theme selection with checkmark, and a "Sales Calendar" link to SteamDB.

**Light theme (☀️)**
New light theme: #f0f2f5 background, white cards, blue #1a73e8 accent, green #2e7d32. Complete coverage of all elements (cards, filters, stats, gear menu, slider, badges, countdown). Persisted via cookie.

#### 🔧 Technical changes

- **Bash**: `ENDOFSALES_FLAG` / `SALE_DATES_FILE` variables, step 6 scraping with dual pattern (regex `InitDailyDealTimer` + grep `prend fin le|Offer ends`), FR→EN month conversion via sed, `sale_dates.json`, JS countdown via `setInterval(1000)`, `swsc_endofsales` cookie, `data-endts` on cards, `matchExpiring` filter (48h), auto-visible `expiringBtn`, `setTheme()` for 3 themes, gear menu with outside-click close, full Light CSS (59 rules).
- **PowerShell**: `-ScrapeEndDates` parameter, dual pattern scraping (regex + 24-month FR/EN mapping), `$SaleDates` → `SALE_DATES` injected into HTML, identical countdown, `toggleExpiring()`, identical Light CSS, identical gear menu.
- **run.php**: `endofsales=on` handler (creates flag + triggers scan) and `off` (deletes flag + data).

#### 📊 Metrics

| File | v1.3 | v1.4 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 958 lines | 1175 lines | +217 |
| `Steam_Wishlist_Sales_Checker.ps1` | 741 lines | 945 lines | +204 |
| `run.php` | 48 lines | 65 lines | +17 |

---

## v1.3 — 04/03/2026

### 🇫🇷 Français

#### ✨ Nouvelles fonctionnalités

**Slider de fourchette de prix**
Un curseur "En dessous de X€" intégré dans la barre de tri permet de filtrer les jeux par prix maximal de vente. Le filtre se combine avec la recherche textuelle, les filtres par genre, par catégorie et le filtre Nouveautés. Stylisé dans les deux thèmes (Modern et Classic Steam).

**Tri Z→A et Metacritic**
Deux nouveaux boutons de tri : Z→A (ordre alphabétique inversé) et Metacritic (du score le plus élevé au plus bas). S'ajoutent aux tris existants A→Z, Prix ↑, Prix ↓ et % Promo.

**Filtres par catégorie (Solo, Co-op, Multi...)**
Les catégories de jeu (Single-player, Multi-player, Co-op, PvP, MMO, etc.) sont récupérées depuis l'API `appdetails` et stockées dans le cache. Une barre de filtres dédiée permet de n'afficher que les jeux correspondant à un mode de jeu. Se combine avec tous les autres filtres.

**Score Metacritic**
Le score Metacritic est récupéré depuis l'API `appdetails` et stocké dans le cache. Quand disponible, un petit badge coloré s'affiche à côté du prix : vert (≥75), jaune (≥50), rouge (<50). Les jeux sans score Metacritic n'affichent rien.

**Description courte au survol**
La description courte de chaque jeu (champ `short_description` de l'API) est ajoutée en attribut `title` sur chaque carte. Un simple survol de la vignette affiche la description dans le tooltip natif du navigateur.

#### 🔧 Modifications techniques

- **Bash** : extraction de `.data.metacritic.score` et `.data.short_description` dans le jq d'appdetails, enrichissement du JSON avec les champs `metacritic` et `desc`, génération du badge Metacritic conditionnel et de l'attribut `title` dans le template jq des cartes, calcul de `MAX_PRICE_EUR` pour le slider, HTML du slider dans la section HTMLMETA interpolée, CSS `.metacritic` / `.mc-high` / `.mc-mid` / `.mc-low` et `.price-slider-wrap` pour les deux thèmes, listeners JS `priceMin` / `priceMax` avec contrainte croisée, filtre `matchPrice` dans `applyFilters()`.
- **PowerShell** : extraction de `metacritic.score` et `short_description` dans la boucle appdetails, propriétés `Metacritic` et `Desc` sur l'objet Game, génération de `$McHtml` conditionnel et `$SafeDesc` pour l'attribut `title`, calcul de `$MaxPriceEur`, HTML du slider, CSS et JS identiques au Bash.

#### 📊 Métriques

| Fichier | v1.2 | v1.3 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 865 lignes | 958 lignes | +93 |
| `Steam_Wishlist_Sales_Checker.ps1` | 639 lignes | 741 lignes | +102 |

---

### 🇬🇧 English

#### ✨ New features

**Price range slider**
A "Below X€" slider integrated into the sort toolbar lets you filter games by maximum sale price. The filter combines with text search, genre filters, category filters, and the New filter. Styled in both themes (Modern and Classic Steam).

**Z→A and Metacritic sorting**
Two new sort buttons: Z→A (reverse alphabetical) and Metacritic (highest score first). Added alongside existing A→Z, Price ↑, Price ↓, and Discount % sorts.

**Category filters (Solo, Co-op, Multi...)**
Game categories (Single-player, Multi-player, Co-op, PvP, MMO, etc.) are fetched from the `appdetails` API and stored in the cache. A dedicated filter bar lets you display only games matching a specific play mode. Combines with all other filters.

**Metacritic score**
The Metacritic score is fetched from the `appdetails` API and stored in the cache. When available, a small color-coded badge appears next to the price: green (≥75), yellow (≥50), red (<50). Games without a Metacritic score show nothing.

**Short description on hover**
Each game's short description (from the `short_description` API field) is added as a `title` attribute on each card. Simply hovering over the thumbnail displays the description in the browser's native tooltip.

#### 🔧 Technical changes

- **Bash**: extraction of `.data.metacritic.score` and `.data.short_description` in the appdetails jq, JSON enrichment with `metacritic` and `desc` fields, conditional Metacritic badge and `title` attribute in the card jq template, `MAX_PRICE_EUR` computation for the slider, slider HTML in the interpolated HTMLMETA section, `.metacritic` / `.mc-high` / `.mc-mid` / `.mc-low` and `.price-slider-wrap` CSS for both themes, `priceMin` / `priceMax` JS listeners with cross-constraint, `matchPrice` filter in `applyFilters()`.
- **PowerShell**: extraction of `metacritic.score` and `short_description` in the appdetails loop, `Metacritic` and `Desc` properties on the Game object, conditional `$McHtml` and `$SafeDesc` for the `title` attribute, `$MaxPriceEur` computation, slider HTML, CSS and JS identical to Bash.

#### 📊 Metrics

| File | v1.2 | v1.3 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 865 lines | 958 lines | +93 |
| `Steam_Wishlist_Sales_Checker.ps1` | 639 lines | 741 lines | +102 |

---

## v1.2 — 03/03/2026

### 🇫🇷 Français

#### ✨ Nouvelles fonctionnalités

**Badges de suivi (New / Prix 🔼 / Prix 🔽)**
Le script sauvegarde désormais les prix de vente de chaque scan dans un fichier `previous_sales.json` (Linux) ou `previous_sales_<ID>.json` (Windows, dans `%APPDATA%`). Au scan suivant, une comparaison automatique s'effectue : un badge bleu **NEW** apparaît sur les jeux qui n'étaient pas en promo au scan précédent, un badge rouge **Prix 🔼** signale une hausse de prix depuis le dernier scan, et un badge vert **Prix 🔽** indique une baisse. Ces badges s'affichent en haut à gauche de l'image de chaque carte (le badge de remise reste en haut à droite). Au premier scan, aucun badge n'est affiché puisqu'il n'y a pas encore de données de référence.

**Badge de remise coloré selon le niveau de promotion**
Le badge `-XX%` en haut à droite change de couleur selon l'intensité de la remise : vert pour les grosses promos (70-100%), orange pour les promos moyennes (30-69%), rouge pour les petites promos (0-29%). Permet de repérer d'un coup d'œil les meilleures affaires. Stylisé dans les deux thèmes (Modern et Classic Steam).

**Bouton « Vider le cache »**
Un bouton rouge discret 🗑️ dans le header permet de supprimer le cache et les données de comparaison. Un message de confirmation `confirm()` avertit l'utilisateur que le prochain scan sera plus long. Sur Linux/PHP, le bouton appelle `run.php?clear-cache=1` via `fetch()` avec retour visuel (✅ Cache vidé !) sans quitter la page ni relancer de scan. Sur PowerShell, le bouton affiche les instructions pour relancer avec `-ClearCache` et le chemin du fichier cache.

**Filtre « Nouveautés »**
Un bouton 🆕 dans la barre de filtres permet d'afficher uniquement les jeux nouvellement en promotion (badge NEW). Ce filtre se combine avec la recherche textuelle et les filtres par genre : on peut par exemple chercher les nouveaux RPG en promo.

#### 🔧 Modifications techniques

- **Bash** : nouvelle variable `PREVIOUS_SALES_FILE`, étape 5 de comparaison avec `jq --slurpfile`, classes CSS conditionnelles `badge-high`/`badge-mid`/`badge-low` dans le template jq, attribut `data-badge` sur chaque carte, CSS status-badge / clear-cache-btn / new-only-btn pour les deux thèmes, fonction `clearCache()` via `fetch()` avec feedback visuel, fonction `toggleNewOnly()`, `applyFilters()` enrichi avec filtre `showNewOnly`, sélecteur `:not(.new-only-btn)` pour isoler le bouton Nouveautés des filtres genre.
- **PowerShell** : variable `$BadgeClass` conditionnelle, même logique de badges et filtres, bouton vider le cache avec `alert()` affichant le chemin et la commande `-ClearCache`, `data-cache-path` sur le body.
- **run.php** : le paramètre `clear-cache=1` supprime les fichiers et retourne un simple texte de confirmation sans lancer de scan.

#### 📊 Métriques

| Fichier | v1.1 | v1.2 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 751 lignes | 860 lignes | +109 |
| `Steam_Wishlist_Sales_Checker.ps1` | 544 lignes | 639 lignes | +95 |

---

### 🇬🇧 English

#### ✨ New features

**Tracking badges (New / Price 🔼 / Price 🔽)**
The script now saves sale prices from each scan into a `previous_sales.json` file (Linux) or `previous_sales_<ID>.json` (Windows, in `%APPDATA%`). On the next scan, an automatic comparison takes place: a blue **NEW** badge appears on games that were not on sale in the previous scan, a red **Price 🔼** badge signals a price increase since the last scan, and a green **Price 🔽** badge indicates a price drop. These badges are displayed in the top-left corner of each card image (the discount badge remains top-right). On the first scan, no badges are shown since there is no reference data yet.

**Color-coded discount badge**
The `-XX%` badge in the top-right corner now changes color based on the discount level: green for major discounts (70-100%), orange for moderate discounts (30-69%), red for small discounts (0-29%). Makes it easy to spot the best deals at a glance. Styled in both themes (Modern and Classic Steam).

**"Clear cache" button**
A discreet red 🗑️ button in the page header lets you wipe the cache and comparison data. A `confirm()` dialog warns the user that the next scan will take longer. On Linux/PHP, the button calls `run.php?clear-cache=1` via `fetch()` with visual feedback (✅ Cache cleared!) without leaving the page or triggering a new scan. On PowerShell, the button displays instructions to rerun with `-ClearCache` and the cache file path.

**"New releases" filter**
A 🆕 button in the filter bar lets you display only newly discounted games (NEW badge). This filter combines with text search and genre filters — for example, you can search for new RPGs on sale.

#### 🔧 Technical changes

- **Bash**: new `PREVIOUS_SALES_FILE` variable, step 5 comparison using `jq --slurpfile`, conditional CSS classes `badge-high`/`badge-mid`/`badge-low` in jq template, `data-badge` attribute on each card, status-badge / clear-cache-btn / new-only-btn CSS for both themes, `clearCache()` function via `fetch()` with visual feedback, `toggleNewOnly()` function, enhanced `applyFilters()` with `showNewOnly` filter, `:not(.new-only-btn)` selector to isolate the New filter from genre buttons.
- **PowerShell**: conditional `$BadgeClass` variable, same badge and filter logic, clear cache button with `alert()` showing the path and `-ClearCache` command, `data-cache-path` on body.
- **run.php**: `clear-cache=1` parameter now deletes files and returns a plain text confirmation without triggering a scan.

#### 📊 Metrics

| File | v1.1 | v1.2 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 751 lines | 860 lines | +109 |
| `Steam_Wishlist_Sales_Checker.ps1` | 544 lines | 639 lines | +95 |

---

## v1.1 — 28/02/2026

### 🇫🇷 Français

#### ✨ Nouvelles fonctionnalités

**Cache intelligent**
Le script conserve désormais un fichier de cache persistant (`cache.json` sur Linux, `%APPDATA%\SteamWishlistSales\cache_<ID>.json` sur Windows) qui stocke les noms, images et genres de chaque jeu déjà récupéré. Lors des scans suivants, seuls les nouveaux jeux en promo déclenchent un appel à l'API Steam — les autres sont lus directement depuis le cache. En pratique, un premier scan de ~165 jeux prend environ 5 minutes ; les suivants passent sous la minute si la plupart des jeux sont déjà connus. Le log affiche clairement la répartition entre jeux en cache et jeux à récupérer. Sur Windows, le paramètre `-ClearCache` permet de forcer un rafraîchissement complet.

**Filtres par genres Steam**
L'appel à l'API `appdetails` extrait désormais les genres de chaque jeu (Action, RPG, Indie, Aventure, Stratégie…). Ces genres sont affichés sous forme de petits tags sur chaque carte, et une barre de filtres cliquables apparaît au-dessus de la grille. Un clic sur un genre filtre instantanément l'affichage. Le filtre par genre se combine avec la recherche textuelle existante : on peut par exemple chercher "dark" parmi les RPG uniquement. Les genres sont également sauvegardés dans le cache.

**Thème Classic Steam**
Un bouton dans le header permet de basculer entre le thème moderne actuel et un thème rétro inspiré de l'interface Steam 2004-2010 : fond vert olive, police Tahoma, boutons avec dégradés biseautés façon Windows XP, cartes sans coins arrondis ni animations, badge de promo en vert plat. Le choix de thème est sauvegardé dans un cookie (1 an de durée) et restauré automatiquement à chaque visite.

#### 🔧 Modifications techniques

- **Bash** : nouvelle variable `CACHE_FILE`, extraction des genres via jq dans l'étape 4, génération des boutons de genre et de l'attribut `data-genres` sur chaque carte, ajout du CSS complet du thème Classic en overrides `body.classic`, nouveau JavaScript pour les filtres combinés et le toggle de thème.
- **PowerShell** : nouveau paramètre `-ClearCache`, stockage du cache dans `%APPDATA%`, gestion du cache via hashtable PowerShell et `ConvertTo-Json`/`ConvertFrom-Json`, extraction des genres depuis `$AppData.data.genres`, encodage UTF-8 avec BOM, remplacement de tous les caractères Unicode non-ASCII dans le code PS par des équivalents ASCII ou des entités HTML pour assurer la compatibilité Windows PowerShell 5.1.
- **install.sh** : initialise `cache.json` avec les bonnes permissions lors de l'installation.
- **HTML** : attribut `data-genres` sur chaque carte, section `.genres-row` avec tags `.genre-tag`, barre `.genre-filters`, fonction JavaScript `applyFilters()` combinant recherche + genre, fonction `toggleTheme()` avec persistance cookie.

#### 📊 Métriques

| Fichier | v1.0 | v1.1 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 686 lignes | 751 lignes | +65 |
| `Steam_Wishlist_Sales_Checker.ps1` | 352 lignes | 544 lignes | +192 |

---

### 🇬🇧 English

#### ✨ New features

**Smart cache**
The script now maintains a persistent cache file (`cache.json` on Linux, `%APPDATA%\SteamWishlistSales\cache_<ID>.json` on Windows) storing the name, image, and genres of every previously fetched game. On subsequent scans, only new games on sale trigger an API call — everything else is read straight from cache. In practice, a first scan of ~165 games takes about 5 minutes; subsequent runs drop under one minute when most games are already known. The log clearly shows the breakdown between cached and new games. On Windows, the `-ClearCache` parameter forces a full refresh.

**Steam genre filters**
The `appdetails` API call now extracts each game's genres (Action, RPG, Indie, Adventure, Strategy…). These are displayed as small tags on each card, and a clickable filter bar appears above the grid. Clicking a genre instantly filters the view. The genre filter combines with the existing text search — for example, you can search "dark" among RPGs only. Genres are also saved in the cache.

**Classic Steam theme**
A button in the header toggles between the current modern theme and a retro theme inspired by the 2004-2010 Steam UI: olive-green background, Tahoma font, beveled gradient buttons reminiscent of Windows XP, cards with no rounded corners or animations, and flat green discount badges. The theme preference is stored in a cookie (1-year expiry) and automatically restored on each visit.

#### 🔧 Technical changes

- **Bash**: new `CACHE_FILE` variable, genre extraction via jq in step 4, genre button generation and `data-genres` attribute on each card, full Classic theme CSS as `body.classic` overrides, new JavaScript for combined filters and theme toggling.
- **PowerShell**: new `-ClearCache` parameter, cache stored in `%APPDATA%`, cache management via PowerShell hashtable with `ConvertTo-Json`/`ConvertFrom-Json`, genre extraction from `$AppData.data.genres`, UTF-8 BOM encoding, all non-ASCII Unicode characters in PS code replaced with ASCII equivalents or HTML entities for Windows PowerShell 5.1 compatibility.
- **install.sh**: initializes `cache.json` with proper permissions during installation.
- **HTML**: `data-genres` attribute on each card, `.genres-row` section with `.genre-tag` elements, `.genre-filters` bar, `applyFilters()` JavaScript function combining search and genre, `toggleTheme()` function with cookie persistence.

#### 📊 Metrics

| File | v1.0 | v1.1 | Delta |
|---|---|---|---|
| `steam-wishlist-sales.sh` | 686 lines | 751 lines | +65 |
| `Steam_Wishlist_Sales_Checker.ps1` | 352 lines | 544 lines | +192 |
