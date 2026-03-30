# 🎮 Steam Wishlist Sales (v1.4)

Code written with Claude (Anthropic). This is a learning project to see how "curl" and "Invoke-RestMethod" commands can grab information from the Steam API. An executable is also available for Windows to simply check your wishlist sales without any installation, in the Releases page.

Automatically monitors your Steam wishlist and displays discounted games on a sleek, self-hosted web page.

![Steam Wishlist Sales](screenshots/preview.png)
![Steam Wishlist Sales](screenshots/preview2.png)

## Features

- **Automatic scanning** of your wishlist via the Steam API (every 6 hours by default, configurable)
- **Tracking badges**: blue **NEW** badge for newly discounted games, red **Price 🔼** if price went up, green **Price 🔽** if price dropped
- **Colored discount badge**: green (≥70%), orange (30-69%), red (<30%)
- **Metacritic score**: colored badge green/yellow/red displayed next to the price
- **Description on hover**: tooltip showing the game's short description
- **Genre filters**: Action, RPG, Indie, Racing, Strategy... (21 genres)
- **Category filters**: Single-player, Multi-player, Co-op, PvP, MMO, LAN, Split Screen...
- **New only filter**: show only newly discounted games
- **⏳ "Expiring soon" filter**: show promos expiring within 72 hours
- **End-of-sale dates** (optional): live countdown "⏳ 2d 5h 34min" ticking every second
- **Price slider**: filter games below a maximum price
- **Smart cache**: only new sale entries trigger API calls (5x faster scans)
- **Sorting**: A→Z, Z→A, price ascending/descending, discount %, Metacritic score
- **Real-time search** by game name
- **3 themes**: Modern (default), Classic Steam retro (2004-2010), Light (☀️) — persisted via cookie
- **⚙️ Gear menu**: unified menu for refresh, clear cache, theme switching, sales calendar
- **Statistics**: sale count, best discount, lowest price, next scan countdown
- **Responsive**: adapts to mobile and desktop
- **Lightweight**: static HTML page, no database required
- **Windows version**: standalone PowerShell script included

## Requirements

### Linux (main version)

- **Linux** (Debian/Ubuntu recommended)
- **Apache2** with **PHP 8.x**
- **curl**, **jq**, **bc**
- A **public Steam profile** with a **public wishlist**

### Windows (standalone version)

- **Windows 10/11** with **PowerShell 5.1+**
- No other dependencies

## Quick Install (Linux as root user)

```bash
git clone https://github.com/W1p3out/steam-wishlist-sales-checker
cd steam-wishlist-sales-checker
chmod +x install.sh uninstall.sh
./install.sh
```

The installer will ask for:

| Parameter | Description | Example |
|---|---|---|
| **Steam ID** | Your 64-bit Steam identifier (17 digits) | `76561198040773990` |
| **Port** | Web server port | `2251` |
| **Scan hours** | Automatic scan hours (cron format) | `1,7,13,19` |

> 💡 **Find your Steam ID**: go to [steamid.io](https://steamid.io/) and enter your Steam profile.

> ⚠️ **Your profile and wishlist must be public** for the scan to work.

## Windows Usage (PowerShell)

```powershell
.\SteamWishlistSales.ps1 -SteamID 76561198040773990
.\SteamWishlistSales.ps1 -SteamID 76561198040773990 -Country us
.\SteamWishlistSales.ps1 76561198040773990 -ClearCache
.\SteamWishlistSales.ps1 76561198040773990 -ScrapeEndDates
.\SteamWishlistSales.ps1 76561198040773990 -ClearCache -ScrapeEndDates
```

The script generates an HTML file in `%TEMP%` and opens it automatically in the browser. Cache is stored in `%APPDATA%\SteamWishlistSales\`.

| Parameter | Description | Default |
|---|---|---|
| **SteamID** | Your 64-bit Steam ID | (asked interactively) |
| **Country** | Country code for prices | `fr` |
| **OutputPath** | HTML output path | `%TEMP%\steam-wishlist-sales.html` |
| **ClearCache** | Clear cache before scanning | disabled |
| **ScrapeEndDates** | Scrape promotion end dates | disabled |

## End-of-Sale Dates (optional)

End-of-sale date scraping is an optional feature that adds a live countdown on each game card.

### Linux Activation

Type `swsc:endofsales-on` in the search bar and press Enter. This creates a flag, triggers a scan with scraping and displays dates. Subsequent cron scans will also scrape as long as the flag exists. To disable: type `swsc:endofsales-off`.

### PowerShell Activation

```powershell
.\SteamWishlistSales.ps1 76561198040773990 -ScrapeEndDates
```

### How it works

Scraping retrieves end dates via two Steam patterns:
- **Pattern 1**: `InitDailyDealTimer` — precise Unix timestamp
- **Pattern 2**: text "prend fin le 6 avril" / "Offer ends 6 April" — FR + EN supported

⚠️ Scraping is slow (~1 req/s per game) and relies on Steam's public HTML. If Steam changes its markup, `swsc:endofsales-off` or removing `-ScrapeEndDates` cleanly disables everything without impacting the rest.

## Special Commands (Linux search bar)

| Command | Action |
|---|---|
| `swsc:endofsales-on` | Enable end-of-sale scraping + trigger a scan |
| `swsc:endofsales-off` | Disable scraping and remove data |

## Manual Installation (Linux)

### 1. Install dependencies

```bash
sudo apt update
sudo apt install curl jq bc apache2 php libapache2-mod-php sudo
```

### 2. Copy files

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

### 3. Configure Steam ID

```bash
sudo nano /opt/steam-wishlist-sales/steam-wishlist-sales.sh
# Edit: STEAM_ID="YOUR_STEAM_ID_HERE"
```

### 4. Configure Apache

Create `/etc/apache2/sites-available/steam-wishlist-sales.conf`:

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

Add the port in `/etc/apache2/ports.conf` (**not** in the vhost!):

```bash
echo "Listen 2251" >> /etc/apache2/ports.conf
sudo a2enmod headers
sudo a2ensite steam-wishlist-sales
sudo systemctl restart apache2
```

### 5. Permissions and cron

```bash
echo "www-data ALL=(ALL) NOPASSWD: /opt/steam-wishlist-sales/steam-wishlist-sales.sh" | sudo tee /etc/sudoers.d/steam-wishlist-sales
sudo chmod 440 /etc/sudoers.d/steam-wishlist-sales

# Add cron (4 scans/day)
(crontab -l 2>/dev/null; echo "5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1") | crontab -
```

### 6. First scan

```bash
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

## Architecture

```
steam-wishlist-sales/
├── install.sh                     # Automated installation
├── uninstall.sh                   # Uninstallation
├── SteamWishlistSales.ps1         # Windows version (standalone)
├── README.md / README_EN.md       # Documentation FR/EN
├── CHANGELOG.md                   # Version history
├── scripts/
│   └── steam-wishlist-sales.sh    # Main script (7 steps)
└── web/
    ├── run.php                    # Scan trigger + flag management
    └── update.php                 # Live scan tracking
```

### Generated files

```
/var/www/steam-wishlist-sales/
├── index.html                     # Generated HTML page
├── cache.json                     # Cache: names/images/genres/metacritic/desc/cats
├── previous_sales.json            # Price snapshot (badges)
├── sale_dates.json                # End-of-sale dates (optional)
└── endofsales.flag                # Scraping flag (optional)
```

### Scan duration

| Wishlist | First scan | Subsequent scans | With end-of-sales |
|---|---|---|---|
| ~500 games | ~2min | ~20s | +2min |
| ~1000 games | ~4min | ~30s | +3min |
| ~1500 games | ~5min | ~1min | +5min |

## Troubleshooting

### Scan finds no games
Check that your Steam profile and wishlist are public. Test: `curl -sL "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=YOUR_ID"`

### Metacritic/description not showing
These fields were added in v1.3. Clear the cache once: `-ClearCache` (PS) or button in ⚙️ (Linux).

### End-of-sale dates not showing
Check that scraping is enabled. Not all promos have end dates — seasonal sales don't use individual countdowns.

### UTF-8 error in PowerShell
The script must be encoded as UTF-8 with BOM. Save as "UTF-8 with BOM" if you edit it.

## Uninstallation

```bash
sudo ./uninstall.sh
```

## License

MIT — see [LICENSE](LICENSE)
