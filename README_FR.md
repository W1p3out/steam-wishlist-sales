# 🎮 Steam Wishlist Sales (v1.4)

Code généré avec Claude (Anthropic). Ceci est un projet d'apprentissage pour comprendre comment les commandes "curl" et "Invoke-RestMethod" peuvent récupérer des informations via l'API Steam. Un exécutable est également disponible pour Windows pour simplement vérifier les promotions de votre liste de souhaits Steam sans aucune installation, dans la page "Releases".

Surveille automatiquement votre wishlist Steam et affiche les jeux en promotion sur une page web élégante, auto-hébergée.

![Steam Wishlist Sales](screenshots/preview.png)

## Fonctionnalités

- **Scan automatique** de la wishlist via l'API Steam (toutes les 6h par défaut)
- **Badges de suivi** : badge bleu **NEW** pour les nouveaux jeux en promo, badge rouge **Prix 🔼** si le prix a augmenté, badge vert **Prix 🔽** si le prix a baissé depuis le dernier scan
- **Filtrer par nouveautés** : affiche uniquement les nouveaux jeux en promotion
- **Date de fin de la promotion** : affiche la date de fin de la promotion (dans la barre de recherche, entrer 'swsc:endofsales-on' pour activer, 'off' pour désactiver)
- **Cache intelligent** : seuls les nouveaux jeux en promo déclenchent des appels API, les autres sont lus depuis le cache local (scans 5x plus rapides)
- **Bouton vider le cache** (Linux/PHP) : un clic pour tout réinitialiser, avec confirmation
- **Filtres par genre** : Action, RPG, Indie... combinables avec la recherche textuelle
- **Double thème** : Modern (par défaut) ou Classic Steam rétro (2004-2010), persistant via cookie
- **Page web auto-hébergée** avec un design inspiré de Steam
- **Tri** : alphabétique, prix croissant/décroissant, % de promotion
- **Recherche** en temps réel par nom de jeu
- **Bouton d'actualisation manuelle** avec suivi en direct du scan
- **Statistiques** : nombre de promos, meilleure remise, prix le plus bas, prochain scan
- **Responsive** : s'adapte au mobile et au desktop
- **Léger** : page HTML statique, pas de base de données
- **Version Windows** : script PowerShell standalone inclus

## Prérequis

### Linux (version principale)

- **Linux** (Debian/Ubuntu recommandé)
- **Apache2** avec **PHP 8.x**
- **curl**, **jq**, **bc**
- Un **profil Steam public** avec une **wishlist publique**

### Windows (version standalone)

- **Windows 10/11** avec **PowerShell 5.1+**
- Aucune autre dépendance

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
| **Steam ID** | Votre identifiant Steam 64-bit (17 chiffres) | `76561198040773990` |
| **Port** | Port du serveur web | `2251` |
| **Heures de scan** | Heures de scan automatique (format cron) | `1,7,13,19` |

> 💡 **Trouver votre Steam ID** : rendez-vous sur [steamid.io](https://steamid.io/) et entrez votre profil Steam.

> ⚠️ **Votre profil et votre wishlist doivent être publics** pour que le scan fonctionne.

## Utilisation Windows (PowerShell)

```powershell
.\SteamWishlistSales.ps1 -SteamID 76561198040773990
.\SteamWishlistSales.ps1 -SteamID 76561198040773990 -Country us
.\SteamWishlistSales.ps1 76561198040773990 -ClearCache
.\SteamWishlistSales.ps1 76561198040773990 -ScrapeEndDates
```

Le script génère un fichier HTML dans `%TEMP%` et l'ouvre automatiquement dans le navigateur. Le cache est stocké dans `%APPDATA%\SteamWishlistSales\`.

| Paramètre | Description | Défaut |
|---|---|---|
| **SteamID** | Votre Steam ID 64-bit | (demandé interactivement) |
| **Country** | Code pays pour les prix | `fr` |
| **OutputPath** | Chemin du HTML généré | `%TEMP%\steam-wishlist-sales.html` |
| **ClearCache** | Vider le cache avant le scan | désactivé |
| **ScrapeEndDates** | Ajoute la date de fin de la promo | désactivé |

## Installation manuelle (Linux)

### 1. Installer les dépendances

```bash
sudo apt update
sudo apt install curl jq bc apache2 php libapache2-mod-php sudo
```

### 2. Copier les fichiers

```bash
sudo mkdir -p /opt/steam-wishlist-sales
sudo cp scripts/steam-wishlist-sales.sh /opt/steam-wishlist-sales/
sudo chmod +x /opt/steam-wishlist-sales/steam-wishlist-sales.sh

sudo mkdir -p /var/www/steam-wishlist-sales
sudo cp web/run.php web/update.php /var/www/steam-wishlist-sales/

# Initialiser le cache
echo '{}' | sudo tee /var/www/steam-wishlist-sales/cache.json
sudo chmod 644 /var/www/steam-wishlist-sales/cache.json
sudo chown www-data:www-data /var/www/steam-wishlist-sales/cache.json
```

### 3. Configurer le Steam ID

```bash
sudo nano /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

```bash
STEAM_ID="VOTRE_STEAM_ID_ICI"
```

### 4. Configurer Apache

Créez le fichier `/etc/apache2/sites-available/steam-wishlist-sales.conf` :

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

Ajoutez le port dans `/etc/apache2/ports.conf` :

```bash
echo "Listen 2251" >> /etc/apache2/ports.conf
```

```bash
sudo a2enmod headers
sudo a2ensite steam-wishlist-sales
sudo systemctl restart apache2
```

### 5. Configurer les permissions

```bash
echo "www-data ALL=(ALL) NOPASSWD: /opt/steam-wishlist-sales/steam-wishlist-sales.sh" | sudo tee /etc/sudoers.d/steam-wishlist-sales
sudo chmod 440 /etc/sudoers.d/steam-wishlist-sales
```

### 6. Configurer le cron

```bash
crontab -e
```

```
5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1
```

### 7. Premier scan

```bash
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

Le premier scan récupère tous les jeux (~5 min pour ~1500 jeux). Les suivants sont bien plus rapides grâce au cache.

## Utilisation

### Accéder à la page

```
http://VOTRE_IP:2251/
```

### Fonctionnalités de la page

- **Tri** : boutons A→Z, Prix ↑, Prix ↓, % Promo
- **Recherche** : barre de recherche en temps réel
- **Filtres genre** : cliquez sur un genre pour filtrer (combinable avec la recherche)
- **Thème** : bouton Classic Steam / Modern dans le header (sauvegardé via cookie)
- **Actualisation** : bouton ↻ Actualiser avec log en direct
- **Prochain scan** : compte à rebours dans la barre de statistiques
- **Lien Steam** : cliquez sur une carte pour ouvrir la page Steam du jeu

## Architecture

```
steam-wishlist-sales/
├── install.sh                     # Script d'installation automatique
├── uninstall.sh                   # Script de désinstallation
├── SteamWishlistSales.ps1         # Version Windows (standalone)
├── README.md                      # Ce fichier
├── README_EN.md                   # README en anglais
├── CHANGELOG.md                   # Historique des versions
├── LICENSE
├── screenshots/
│   └── preview.png
├── scripts/
│   └── steam-wishlist-sales.sh    # Script principal de scan
└── web/
    ├── run.php                    # Déclencheur de scan manuel
    └── update.php                 # Page de suivi du scan en cours
```

### Fichiers générés à l'exécution

```
/var/www/steam-wishlist-sales/
├── index.html                     # Page HTML générée
└── cache.json                     # Cache des noms/images/genres
```

### Fonctionnement technique

Le script `steam-wishlist-sales.sh` fonctionne en 5 étapes :

1. **Wishlist** — Récupère la liste complète des app IDs via `IWishlistService/GetWishlist` (1 appel API)
2. **Prix** — Récupère les prix par lots de 30 via `appdetails?filters=price_overview` (~46 appels)
3. **Filtrage** — Identifie les jeux ayant un `discount_percent > 0`
4. **Noms/Genres** — Consulte le cache, puis récupère uniquement les jeux manquants via `appdetails` (genres extraits de `.data.genres[]`)
5. **HTML** — Génère la page `index.html` avec grille, filtres genre, double thème CSS, et JavaScript interactif

### Durée d'un scan

| Wishlist | Premier scan | Scans suivants (cache) |
|---|---|---|
| ~500 jeux | ~2min | ~20s |
| ~1000 jeux | ~4min | ~30s |
| ~1500 jeux | ~5min | ~1min |

### API Steam utilisées

| Endpoint | Usage | Auth requise |
|---|---|---|
| `IWishlistService/GetWishlist/v1/` | Liste des app IDs de la wishlist | Non (profil public) |
| `store.steampowered.com/api/appdetails` | Prix, noms, images, genres | Non |

## Dépannage

### Le scan ne trouve aucun jeu

- Vérifiez que votre **profil Steam est public**
- Vérifiez que votre **wishlist est publique**
- Testez : `curl -sL "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=VOTRE_ID"`

### Le cache semble corrompu

```bash
# Linux
sudo rm /var/www/steam-wishlist-sales/cache.json
echo '{}' | sudo tee /var/www/steam-wishlist-sales/cache.json
sudo chown www-data:www-data /var/www/steam-wishlist-sales/cache.json
```

```powershell
# Windows
.\SteamWishlistSales.ps1 76561198040773990 -ClearCache
```

### Le bouton Actualiser ne fonctionne pas

- Vérifiez les permissions sudo : `sudo -u www-data sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh`
- Vérifiez les logs : `tail -f /var/log/apache2/steam-wishlist-sales-error.log`

### Erreur de parsing PowerShell

Le script PowerShell doit être encodé en UTF-8 avec BOM. Si vous éditez le fichier, sauvegardez-le en "UTF-8 with BOM" dans votre éditeur.

## Désinstallation

```bash
sudo ./uninstall.sh
```

## Licence

MIT — voir [LICENSE](LICENSE)
