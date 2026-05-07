#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Steam Wishlist Sales Checker — Patch v2.0.2 → v2.0.3
# Correction : rate limiting PHP réduit de 60s à 10s
# Le délai de 60s bloquait l'utilisation normale depuis l'interface web.
# 
# Autonome : ne nécessite aucun autre fichier, patche en place
# Usage : sudo ./update.sh
# ═══════════════════════════════════════════════════════════════════

set -e

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; CYAN="\033[0;36m"; NC="\033[0m"
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
err()  { echo -e "  ${RED}[ERR]${NC} $1"; }
step() { echo -e "  ${CYAN}[...]${NC} $1"; }

INSTALL_DIR="/opt/steam-wishlist-sales"
WEB_DIR="/var/www/steam-wishlist-sales"
SCRIPT="$INSTALL_DIR/steam-wishlist-sales.sh"

echo ""
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║   🎮  SWSC — Patch v2.0.2 → v2.0.3                    ║"
echo "  ╚════════════════════════════════════════════════════════╝"
echo ""

# ── Vérifications ──
if [ "$EUID" -ne 0 ]; then err "Ce script doit être exécuté en tant que root (sudo)"; exit 1; fi
if [ ! -f "$SCRIPT" ]; then err "Script non trouvé : $SCRIPT"; exit 1; fi

# ── Détection de version ──
CURRENT=$(grep -oP 'version">v\K[^<]+' "$SCRIPT" | head -1)
step "Version actuelle : v${CURRENT:-inconnue}"

if [ "$CURRENT" = "2.0.3" ]; then
    ok "Déjà en v2.0.3, rien à faire."
    exit 0
fi

# ── Sauvegarde ──
step "Sauvegarde..."
BACKUP_SUFFIX="v${CURRENT:-backup}.$(date +%Y%m%d%H%M%S).bak"
cp "$SCRIPT" "${SCRIPT}.${BACKUP_SUFFIX}"
ok "Bash : ${SCRIPT}.${BACKUP_SUFFIX}"

if [ -f "$WEB_DIR/run.php" ]; then
    cp "$WEB_DIR/run.php" "$WEB_DIR/run.php.${BACKUP_SUFFIX}"
    ok "PHP  : run.php.${BACKUP_SUFFIX}"
fi

# ═══════════════════════════════════════════════════════════════
# PATCH 1/2 : Rate limiting 60s → 10s dans run.php
#
# sed remplace le délai et le message d'erreur associé
# ═══════════════════════════════════════════════════════════════
step "Patch 1/2 : Rate limiting 60s → 10s..."

if [ -f "$WEB_DIR/run.php" ]; then
    sed -i 's/< 60)/< 10)/' "$WEB_DIR/run.php"
    sed -i 's/moins de 60 secondes/moins de 10 secondes/' "$WEB_DIR/run.php"
    sed -i 's/toutes les 60 secondes/toutes les 10 secondes/' "$WEB_DIR/run.php"
    ok "run.php : 60s → 10s"
else
    err "run.php non trouvé dans $WEB_DIR"
fi

# ═══════════════════════════════════════════════════════════════
# PATCH 2/2 : Numéro de version v2.0.2 → v2.0.3
#
# sed -i remplace les badges de version dans le HTML généré
# ═══════════════════════════════════════════════════════════════
step "Patch 2/2 : Version → v2.0.3..."

sed -i 's/>v2\.0\.2</>v2.0.3</g' "$SCRIPT"
sed -i 's/SWSC v2\.0\.2/SWSC v2.0.3/g' "$SCRIPT"

ok "Version → v2.0.3"

# ── Vérification ──
step "Vérification..."
NEW_VER=$(grep -oP 'version">v\K[^<]+' "$SCRIPT" | head -1)
RATE=$(grep -oP '< \K\d+(?=\))' "$WEB_DIR/run.php" 2>/dev/null | head -1)

if [ "$NEW_VER" = "2.0.3" ] && [ "$RATE" = "10" ]; then
    ok "Patch vérifié : v$CURRENT → v2.0.3, rate limit = ${RATE}s ✓"
else
    err "Échec ! Restauration..."
    cp "${SCRIPT}.${BACKUP_SUFFIX}" "$SCRIPT"
    [ -f "$WEB_DIR/run.php.${BACKUP_SUFFIX}" ] && cp "$WEB_DIR/run.php.${BACKUP_SUFFIX}" "$WEB_DIR/run.php"
    err "Fichiers restaurés. Mise à jour annulée."
    exit 1
fi

echo ""
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║   ✅  Patch v2.0.3 appliqué !                         ║"
echo "  ║                                                        ║"
echo "  ║   🐛 Rate limiting PHP : 60s → 10s                    ║"
echo "  ║                                                        ║"
echo "  ║   Relancez un scan pour regénérer le HTML :            ║"
echo "  ║   sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh║"
echo "  ╚════════════════════════════════════════════════════════╝"
echo ""
