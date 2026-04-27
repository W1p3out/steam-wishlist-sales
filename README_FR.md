# 🎮 Steam Wishlist Sales (v2.0)

Code généré avec Claude (Anthropic). Ceci est un projet d'apprentissage pour comprendre comment les commandes "curl" et "Invoke-RestMethod" peuvent récupérer des informations via l'API Steam. Un exécutable est également disponible pour Windows pour simplement vérifier les promotions de votre liste de souhaits Steam sans aucune installation, dans la page "Releases".

Surveille automatiquement votre wishlist Steam et affiche les jeux en promotion sur une page web élégante, auto-hébergée.

![Steam Wishlist Sales](screenshots/preview.gif)

## Fonctionnalités

- **Scan automatique** de la wishlist via l'API Steam (toutes les 6h par défaut, configurable)
- **Badges de suivi** : badge bleu **NEW** pour les nouveaux jeux en promo, badge rouge **Prix 🔼** si le prix a augmenté, badge vert **Prix 🔽** si le prix a baissé
- **Badge de remise coloré** : vert (≥70%), orange (30-69%), rouge (<30%)
- **Score Metacritic** : badge coloré vert/jaune/rouge affiché à côté du prix
- **Description au survol** : tooltip affichant la description courte du jeu
- **Filtres par genre** : Action, RPG, Indie, Racing, Strategy... (21 genres)
- **Filtres par catégorie** : Solo, Multijoueur, Co-op, PvP, MMO, LAN, Écran partagé...
- **Filtre Nouveautés** : affiche uniquement les nouveaux jeux en promotion
- **⏳ Filtre "Expire bientôt"** : affiche les promos expirant dans moins de 72h (si dates de fin activées)
- **Dates de fin de promo** (optionnel, désactivé par défaut) : active le scraping des pages Steam pour récupérer les dates de fin. Un countdown en temps réel "⏳ 2j 5h 34min" s'affiche alors sous chaque carte. Activation : `swsc:endofsales-on` (Linux) ou `-ScrapeEndDates` (PowerShell/exe)
- **Slider de prix** : filtrer les jeux en dessous d'un prix maximum
- **🛒 Panier multi-jeux** : cochez ✓ sur les vignettes pour sélectionner plusieurs jeux. Une barre flottante affiche le total et l'économie réalisée. Le bouton « Ouvrir sur Steam (Web) » ouvre les pages Steam de tous les jeux sélectionnés en un clic
- **Cache intelligent** : seuls les nouveaux jeux en promo déclenchent des appels API (scans 5x plus rapides)
- **Tri** : A→Z, Z→A, prix croissant/décroissant, % promo, score Metacritic
- **Recherche** en temps réel par nom de jeu
- **3 thèmes** : Modern (défaut), Classic Steam rétro (2004-2010), Light (☀️) — persistants via cookie
- **⚙️ Roue crantée** : menu unifié pour actualiser, vider le cache, changer de thème, calendrier des soldes
- **Statistiques** : nombre de promos, meilleure remise, prix le plus bas, prochain scan
- **Responsive** : s'adapte au mobile et au desktop
- **Léger** : page HTML statique, pas de base de données
- **Version Windows** : script PowerShell standalone inclus + **exécutable (.exe)** téléchargeable dans la page [Releases](https://github.com/W1p3out/steam-wishlist-sales-checker/releases)

## Prérequis

### Linux (version principale)

- **Linux** (Debian/Ubuntu recommandé)
- **Apache2** avec **PHP 8.x**
- **curl**, **jq**, **bc**
- Un **profil Steam public** avec une **wishlist publique**

### Windows (version standalone)

- **Windows 10/11** avec **PowerShell 5.1+** (script .ps1)
- Ou l'**exécutable (.exe)** disponible dans les [Releases](https://github.com/W1p3out/steam-wishlist-sales-checker/releases) — aucune dépendance requise

## Installation rapide (Linux en utilisateur root)

```bash
git clone https://github.com/W1p3out/steam-wishlist-sales-checker
cd steam-wishlist-sales-checker
chmod +x install.sh uninstall.sh
./install.sh
```

Le script d'installation vous demandera :

| Paramètre | Description | Exemple |
|---|---|---|
| **Steam ID** | Votre identifiant Steam 64-bit (17 chiffres) | `12345678901234567` |
| **Port** | Port du serveur web | `2251` |
| **Heures de scan** | Heures de scan automatique (format cron) | `1,7,13,19` |

> 💡 **Trouver votre Steam ID** : rendez-vous sur [steamid.io](https://steamid.io/) et entrez votre profil Steam.

> ⚠️ **Votre profil et votre wishlist doivent être publics** pour que le scan fonctionne.

## Utilisation Windows (PowerShell)

```powershell
.\Steam_Wishlist_Sales_Checker.ps1 -SteamID 12345678901234567
.\Steam_Wishlist_Sales_Checker.ps1 -SteamID 12345678901234567 -Country us
.\Steam_Wishlist_Sales_Checker.ps1 12345678901234567 -ClearCache
.\Steam_Wishlist_Sales_Checker.ps1 12345678901234567 -ScrapeEndDates
.\Steam_Wishlist_Sales_Checker.ps1 12345678901234567 -ClearCache -ScrapeEndDates
```

Le script génère un fichier HTML dans `%TEMP%` et l'ouvre automatiquement dans le navigateur. Le cache est stocké dans `%APPDATA%\SteamWishlistSales\`.

| Paramètre | Description | Défaut |
|---|---|---|
| **SteamID** | Votre Steam ID 64-bit | (demandé interactivement) |
| **Country** | Code pays pour les prix | `fr` |
| **OutputPath** | Chemin du HTML généré | `%TEMP%\steam-wishlist-sales.html` |
| **ClearCache** | Vider le cache avant le scan | désactivé |
| **ScrapeEndDates** | Scraper les dates de fin de promotion | désactivé |

## Dates de fin de promotion (optionnel)

Le scraping des dates de fin est une fonction optionnelle qui ajoute un countdown en temps réel sur chaque carte de jeu.

### Activation sur Linux

Tapez `swsc:endofsales-on` dans la barre de recherche puis Entrée. Cela crée un flag, lance un scan avec scraping et affiche les dates. Les scans cron suivants scraperont aussi tant que le flag existe. Pour désactiver : tapez `swsc:endofsales-off`.

### Activation sur PowerShell

```powershell
.\Steam_Wishlist_Sales_Checker.ps1 12345678901234567 -ScrapeEndDates
```

### Fonctionnement

Le scraping récupère les dates de fin via deux patterns Steam :
- **Pattern 1** : `InitDailyDealTimer` — timestamp Unix précis
- **Pattern 2** : texte "prend fin le 6 avril" / "Offer ends 6 April" — FR + EN supportés

⚠️ Le scraping est lent (~1 req/s par jeu) et repose sur le HTML public de Steam. Si Steam modifie son markup, `swsc:endofsales-off` ou retirer `-ScrapeEndDates` désactive tout proprement sans impacter le reste.

## Commandes spéciales (barre de recherche Linux)

| Commande | Action |
|---|---|
| `swsc:endofsales-on` | Active le scraping des dates de fin + lance un scan |
| `swsc:endofsales-off` | Désactive le scraping et supprime les données |

## Installation manuelle (Linux)

### 1. Installer les dépendances

```bash
sudo apt update
sudo apt install curl jq bc apache2 php libapache2-mod-php
```

### 2. Copier les fichiers

```bash
sudo mkdir -p /opt/steam-wishlist-sales
sudo cp scripts/steam-wishlist-sales.sh /opt/steam-wishlist-sales/
sudo chmod +x /opt/steam-wishlist-sales/steam-wishlist-sales.sh

sudo mkdir -p /var/www/steam-wishlist-sales
sudo cp web/run.php web/update.php /var/www/steam-wishlist-sales/

echo '{}' | sudo tee /var/www/steam-wishlist-sales/cache.json
sudo chmod 644 /var/www/steam-wishlist-sales/cache.json
sudo chown www-data:www-data /var/www/steam-wishlist-sales/cache.json
```

### 3. Configurer le Steam ID

```bash
sudo nano /opt/steam-wishlist-sales/steam-wishlist-sales.sh
# Modifier : STEAM_ID="VOTRE_STEAM_ID_ICI"
```

### 4. Configurer Apache

Créez `/etc/apache2/sites-available/steam-wishlist-sales.conf` :

```apache
<VirtualHost *:2251>
    DocumentRoot /var/www/steam-wishlist-sales
    DirectoryIndex index.html
    <Directory /var/www/steam-wishlist-sales>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    <FilesMatch "\.(html|php)$">
        Header set Cache-Control "no-cache, no-store, must-revalidate"
        Header set Pragma "no-cache"
        Header set Expires "0"
    </FilesMatch>
    ErrorLog ${APACHE_LOG_DIR}/steam-wishlist-sales-error.log
    CustomLog ${APACHE_LOG_DIR}/steam-wishlist-sales-access.log combined
</VirtualHost>
```

Ajoutez le port dans `/etc/apache2/ports.conf` (**pas** dans le vhost !) :

```bash
echo "Listen 2251" >> /etc/apache2/ports.conf
sudo a2enmod headers
sudo a2ensite steam-wishlist-sales
sudo systemctl restart apache2
```

### 5. Permissions et cron

```bash
echo "www-data ALL=(ALL) NOPASSWD: /opt/steam-wishlist-sales/steam-wishlist-sales.sh" | sudo tee /etc/sudoers.d/steam-wishlist-sales
sudo chmod 440 /etc/sudoers.d/steam-wishlist-sales

# Ajouter le cron (4 scans/jour)
(crontab -l 2>/dev/null; echo "5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1") | crontab -
```

### 6. Premier scan

```bash
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

## Architecture

```
steam-wishlist-sales/
├── install.sh                     # Installation automatique
├── uninstall.sh                   # Désinstallation
├── update.sh                      # Mise à jour (patch en place)
├── Steam_Wishlist_Sales_Checker.ps1         # Version Windows (standalone)
├── README.md                      # Documentation (EN)
├── README_FR.md                   # Documentation (FR)
├── CHANGELOG.md                   # Historique des versions
├── scripts/
│   └── steam-wishlist-sales.sh    # Script principal (7 étapes)
└── web/
    ├── run.php                    # Déclencheur de scan + gestion flags
    └── update.php                 # Suivi en direct du scan
```

### Fichiers générés

```
/var/www/steam-wishlist-sales/
├── index.html                     # Page HTML générée
├── cache.json                     # Cache noms/images/genres/metacritic/desc/cats
├── previous_sales.json            # Snapshot des prix (badges)
├── sale_dates.json                # Dates de fin de promo (optionnel)
└── endofsales.flag                # Flag du scraping (optionnel)
```

### Durée d'un scan

| Wishlist | Premier scan | Scans suivants | Avec end-of-sales |
|---|---|---|---|
| ~500 jeux | ~2min | ~20s | +2min |
| ~1000 jeux | ~4min | ~30s | +3min |
| ~1500 jeux | ~5min | ~1min | +5min |

## Dépannage

### Le scan ne trouve aucun jeu
Vérifiez que votre profil et wishlist Steam sont publics. Testez : `curl -sL "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=VOTRE_ID"`

### Metacritic/description ne s'affichent pas
Ces champs ont été ajoutés en v1.3. Videz le cache une fois : `-ClearCache` (PS) ou bouton dans ⚙️ (Linux).

### Les dates de fin ne s'affichent pas
Vérifiez que le scraping est activé. Toutes les promos n'ont pas de date de fin — les grosses soldes saisonnières n'utilisent pas de countdown individuel.

### Le bouton "Ouvrir sur Steam (Web)" n'ouvre pas tous les jeux

Si seul le premier jeu s'ouvre, votre navigateur bloque l'ouverture de plusieurs onglets. Pour résoudre :
- **Chrome/Edge** : cliquez sur l'icône de popup bloquée dans la barre d'adresse → "Toujours autoriser"
- **Firefox** : cliquez sur la barre jaune en haut → "Autoriser les popups"
- Désactivez votre **bloqueur de pubs** pour cette page si nécessaire

### Erreur UTF-8 PowerShell
Le script doit être encodé en UTF-8 avec BOM. Sauvegardez en "UTF-8 with BOM" si vous l'éditez.

## Mise à jour

### Mise à jour automatique (patch en place)

Pour les mises à jour mineures (ex: v2.0 → v2.0.1), un script `update.sh` est fourni. Il modifie directement le script installé sans toucher à votre configuration (Steam ID, heures de scan, pays) :

```bash
sudo ./update.sh
```

Le script :
1. **Sauvegarde** l'ancien script (`.bak`)
2. **Patche** le code en place avec Python (regex multiligne)
3. **Met à jour** le numéro de version via `sed`
4. **Vérifie** le résultat — en cas d'échec, restaure automatiquement la sauvegarde
5. Relancez un scan pour regénérer le HTML : `sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh`

### Mise à jour manuelle (remplacement complet)

Pour les mises à jour majeures (ex: v2.0 → v3.0), remplacez le script et réinjectez votre configuration :

```bash
# Sauvegarder votre Steam ID
grep "^STEAM_ID=" /opt/steam-wishlist-sales/steam-wishlist-sales.sh

# Copier le nouveau script
sudo cp scripts/steam-wishlist-sales.sh /opt/steam-wishlist-sales/

# Réinjecter votre Steam ID
sudo sed -i 's/^STEAM_ID=.*/STEAM_ID="VOTRE_STEAM_ID"/' /opt/steam-wishlist-sales/steam-wishlist-sales.sh

# Relancer un scan
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

> **Rappel** : le nouveau script contient un Steam ID placeholder (`12345678901234567`). Si vous copiez sans réinjecter votre ID, le scan retournera une erreur 400.

## Désinstallation

```bash
sudo ./uninstall.sh
```

## Licence

MIT — voir [LICENSE](LICENSE)
