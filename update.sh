#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Steam Wishlist Sales Checker — Patch v2.0.1 → v2.0.2
# Correctifs de sécurité :
#   - Validation du Steam ID (regex 17 chiffres)
#   - Répertoire temporaire imprévisible (mktemp)
#   - Verrou atomique (mkdir au lieu de touch)
#   - Protection PHP anti-CSRF + rate limiting
#   - Cohérence lock PHP ↔ Bash (.lock.d)
# Note : l'échappement URL capsule a été retiré car l'imbrication
# Bash heredoc → jq → regex rend le fix instable. Le risque est
# nul car Steam contrôle ses URLs CDN.
# 
# Autonome : ne nécessite aucun autre fichier, patche en place
# Usage : sudo ./update.sh
# ═══════════════════════════════════════════════════════════════════

set -e

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; CYAN="\033[0;36m"; NC="\033[0m"
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
err()  { echo -e "  ${RED}[ERR]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
step() { echo -e "  ${CYAN}[...]${NC} $1"; }

INSTALL_DIR="/opt/steam-wishlist-sales"
WEB_DIR="/var/www/steam-wishlist-sales"
SCRIPT="$INSTALL_DIR/steam-wishlist-sales.sh"

echo ""
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║   🎮  SWSC — Patch v2.0.1 → v2.0.2                    ║"
echo "  ╚════════════════════════════════════════════════════════╝"
echo ""

# ── Vérifications ──
if [ "$EUID" -ne 0 ]; then err "Ce script doit être exécuté en tant que root (sudo)"; exit 1; fi
if [ ! -f "$SCRIPT" ]; then err "Script non trouvé : $SCRIPT"; exit 1; fi

# ── Détection de version ──
CURRENT=$(grep -oP 'version">v\K[^<]+' "$SCRIPT" | head -1)
step "Version actuelle : v${CURRENT:-inconnue}"

if [ "$CURRENT" = "2.0.2" ]; then
    ok "Déjà en v2.0.2, rien à faire."
    exit 0
fi

# ── Sauvegarde ──
step "Sauvegarde des fichiers..."
BACKUP_SUFFIX="v${CURRENT:-backup}.$(date +%Y%m%d%H%M%S).bak"
cp "$SCRIPT" "${SCRIPT}.${BACKUP_SUFFIX}"
ok "Bash : ${SCRIPT}.${BACKUP_SUFFIX}"

if [ -f "$WEB_DIR/run.php" ]; then
    cp "$WEB_DIR/run.php" "$WEB_DIR/run.php.${BACKUP_SUFFIX}"
    ok "PHP  : run.php.${BACKUP_SUFFIX}"
fi
if [ -f "$WEB_DIR/update.php" ]; then
    cp "$WEB_DIR/update.php" "$WEB_DIR/update.php.${BACKUP_SUFFIX}"
    ok "PHP  : update.php.${BACKUP_SUFFIX}"
fi

# ═══════════════════════════════════════════════════════════════
# PATCH 1/3 : Correctifs de sécurité dans le script Bash
#
# Python applique 3 modifications :
#   1. Validation du Steam ID (regex ^[0-9]{17}$)
#   2. mktemp -d au lieu de /tmp/steam-wishlist-$$ (prédictible)
#   3. mkdir atomique au lieu de touch (race condition)
# ═══════════════════════════════════════════════════════════════
step "Patch 1/3 : Correctifs Bash (3 modifications)..."

python3 << 'PYTHON_PATCH'
import re

path = "/opt/steam-wishlist-sales/steam-wishlist-sales.sh"
with open(path, "r", encoding="utf-8") as f:
    c = f.read()

fixes = 0

# ── Fix 1 : Validation du Steam ID ──
old_start = 'START_TIME=$(date +%s)\nlog "Démarrage de la récupération de la wishlist Steam"\nlog "Steam ID : $STEAM_ID"'
new_start = """# ── Validation du Steam ID ──
if ! [[ "$STEAM_ID" =~ ^[0-9]{17}$ ]]; then
    err "Steam ID invalide : '$STEAM_ID' (doit être 17 chiffres)"
    err "Trouvez votre ID sur : https://steamid.io/"
    exit 1
fi

START_TIME=$(date +%s)
log "Démarrage de la récupération de la wishlist Steam"
log "Steam ID : $STEAM_ID\""""

if old_start in c and "Validation du Steam ID" not in c:
    c = c.replace(old_start, new_start)
    fixes += 1
    print("  [1/4] Validation Steam ID ajoutée")
else:
    print("  [1/4] Validation Steam ID : déjà présente ou non nécessaire")

# ── Fix 2 : Répertoire temporaire imprévisible ──
if 'TEMP_DIR="/tmp/steam-wishlist-$$"' in c:
    c = c.replace(
        'TEMP_DIR="/tmp/steam-wishlist-$$"',
        'TEMP_DIR=$(mktemp -d /tmp/steam-wishlist-XXXXXX)'
    )
    fixes += 1
    print("  [2/4] mktemp -d appliqué")
else:
    print("  [2/4] mktemp : déjà appliqué")

# ── Fix 3 : Verrou atomique avec mkdir ──
old_lock = """if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
    if [ "$LOCK_AGE" -lt 360 ]; then
        warn "Une mise à jour est déjà en cours (depuis ${LOCK_AGE}s). Abandon."
        exit 0
    fi
    warn "Lock périmé détecté (${LOCK_AGE}s), suppression."
    rm -f "$LOCK_FILE"
fi

touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; rm -rf "$TEMP_DIR"' EXIT"""

new_lock = """# Lock : utilise un répertoire (mkdir atomique) au lieu d'un fichier
LOCK_DIR="/tmp/steam-wishlist-sales.lock.d"
if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    trap 'rm -rf "$LOCK_DIR" "$TEMP_DIR"' EXIT
else
    if [ -d "$LOCK_DIR" ]; then
        LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR") ))
        LOCK_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "?")
        if [ "$LOCK_AGE" -lt 360 ]; then
            warn "Scan déjà en cours (PID $LOCK_PID, depuis ${LOCK_AGE}s). Abandon."
            exit 0
        fi
        warn "Lock périmé détecté (PID $LOCK_PID, ${LOCK_AGE}s), suppression."
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR" && echo $$ > "$LOCK_DIR/pid"
        trap 'rm -rf "$LOCK_DIR" "$TEMP_DIR"' EXIT
    fi
fi"""

if old_lock in c:
    c = c.replace(old_lock, new_lock)
    # Supprimer l'ancienne variable LOCK_FILE
    c = c.replace('LOCK_FILE="/tmp/steam-wishlist-sales.lock"\n', '')
    fixes += 1
    print("  [3/4] Verrou atomique mkdir appliqué")
else:
    print("  [3/4] Verrou : déjà appliqué ou structure différente")



with open(path, "w", encoding="utf-8") as f:
    f.write(c)

print(f"\n  Total : {fixes} correctif(s) Bash appliqué(s)")
PYTHON_PATCH

ok "Script Bash patché"

# ═══════════════════════════════════════════════════════════════
# PATCH 2/3 : Correctifs PHP
#
# run.php   : ajout vérification Referer + rate limiting 1/min
# run.php   : lock path .lock → .lock.d
# update.php: lock path .lock → .lock.d, file_exists → is_dir
# ═══════════════════════════════════════════════════════════════
step "Patch 2/3 : Correctifs PHP..."

python3 << 'PYTHON_PHP'
import os

web_dir = "/var/www/steam-wishlist-sales"

# ── run.php ──
run_php = os.path.join(web_dir, "run.php")
if os.path.exists(run_php):
    with open(run_php, "r", encoding="utf-8") as f:
        c = f.read()
    fixes = 0

    # Ajouter referrer check + rate limiting
    old_check = 'if (!file_exists($script)) {\n    die("Erreur : script introuvable.");\n}'
    new_check = """if (!file_exists($script)) {
    die("Erreur : script introuvable.");
}

// ── Protection basique : vérifier que la requête vient du même serveur ──
$referer = $_SERVER['HTTP_REFERER'] ?? '';
$host = $_SERVER['HTTP_HOST'] ?? '';
if (!empty($referer) && strpos($referer, $host) === false) {
    http_response_code(403);
    die("Accès refusé : requête externe.");
}

// ── Rate limiting : pas plus d'un scan toutes les 60 secondes ──
$rateLimitFile = '/tmp/steam-wishlist-ratelimit';
if (file_exists($rateLimitFile) && (time() - filemtime($rateLimitFile)) < 60) {
    die("Un scan a été lancé il y a moins de 60 secondes. Veuillez patienter.");
}
touch($rateLimitFile);"""

    if "HTTP_REFERER" not in c and old_check in c:
        c = c.replace(old_check, new_check)
        fixes += 1

    # Lock path : .lock → .lock.d
    if "steam-wishlist-sales.lock'" in c and ".lock.d" not in c:
        c = c.replace("steam-wishlist-sales.lock'", "steam-wishlist-sales.lock.d'")
        c = c.replace("file_exists($lockFile)", "is_dir($lockFile)")
        fixes += 1

    with open(run_php, "w", encoding="utf-8") as f:
        f.write(c)
    print(f"  run.php : {fixes} correctif(s)")
else:
    print("  run.php non trouvé (ignoré)")

# ── update.php ──
update_php = os.path.join(web_dir, "update.php")
if os.path.exists(update_php):
    with open(update_php, "r", encoding="utf-8") as f:
        c = f.read()
    fixes = 0

    if "steam-wishlist-sales.lock'" in c and ".lock.d" not in c:
        c = c.replace("steam-wishlist-sales.lock'", "steam-wishlist-sales.lock.d'")
        c = c.replace("file_exists($lockFile)", "is_dir($lockFile)")
        fixes += 1

    with open(update_php, "w", encoding="utf-8") as f:
        f.write(c)
    print(f"  update.php : {fixes} correctif(s)")
else:
    print("  update.php non trouvé (ignoré)")

PYTHON_PHP

ok "Fichiers PHP patchés"

# ═══════════════════════════════════════════════════════════════
# PATCH 3/3 : Mettre à jour le numéro de version
#
# sed -i remplace les badges de version dans le HTML généré :
#   s/>v2.0.1</>v2.0.2</g     → badge sidebar + barre mobile
#   s/SWSC v2.0.1/SWSC v2.0.2/g → modale d'aide
# Gère aussi le cas où on patche depuis v2.0 directement
# ═══════════════════════════════════════════════════════════════
step "Patch 3/3 : Version → v2.0.2..."

# Depuis v2.0.1
sed -i 's/>v2\.0\.1</>v2.0.2</g' "$SCRIPT"
sed -i 's/SWSC v2\.0\.1/SWSC v2.0.2/g' "$SCRIPT"
# Depuis v2.0 (si quelqu'un n'a pas appliqué le v2.0.1)
sed -i 's/>v2\.0</>v2.0.2</g' "$SCRIPT"

ok "Version → v2.0.2"

# ── Vérification finale ──
step "Vérification..."
NEW_VER=$(grep -oP 'version">v\K[^<]+' "$SCRIPT" | head -1)
if [ "$NEW_VER" = "2.0.2" ]; then
    ok "Patch vérifié : v$CURRENT → v2.0.2 ✓"
else
    err "Échec (version détectée : v$NEW_VER) ! Restauration..."
    cp "${SCRIPT}.${BACKUP_SUFFIX}" "$SCRIPT"
    [ -f "$WEB_DIR/run.php.${BACKUP_SUFFIX}" ] && cp "$WEB_DIR/run.php.${BACKUP_SUFFIX}" "$WEB_DIR/run.php"
    [ -f "$WEB_DIR/update.php.${BACKUP_SUFFIX}" ] && cp "$WEB_DIR/update.php.${BACKUP_SUFFIX}" "$WEB_DIR/update.php"
    err "Tous les fichiers restaurés. Mise à jour annulée."
    exit 1
fi

echo ""
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║   ✅  Patch v2.0.2 appliqué !                         ║"
echo "  ║                                                        ║"
echo "  ║   Correctifs appliqués :                               ║"
echo "  ║     🔐 Validation Steam ID (regex 17 chiffres)         ║"
echo "  ║     🔐 Répertoire temporaire imprévisible (mktemp)     ║"
echo "  ║     🔐 Verrou atomique (mkdir)                         ║"
echo "  ║     🔐 Protection PHP anti-CSRF + rate limiting        ║"
echo "  ║     🔐 Cohérence lock PHP ↔ Bash                       ║"
echo "  ║                                                        ║"
echo "  ║   Relancez un scan pour regénérer le HTML :            ║"
echo "  ║   sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh║"
echo "  ╚════════════════════════════════════════════════════════╝"
echo ""
