#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Steam Wishlist Sales Checker — Patch v2.0 → v2.0.1
# Corrige le bouton "Ouvrir sur Steam (Web)" (page intermédiaire
# remplacée par ouverture directe de chaque jeu)
# 
# Usage : sudo ./update.sh
# ═══════════════════════════════════════════════════════════════════

set -e

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; CYAN="\033[0;36m"; NC="\033[0m"
ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
err()  { echo -e "  ${RED}[ERR]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC} $1"; }
step() { echo -e "  ${CYAN}[...]${NC} $1"; }

INSTALL_DIR="/opt/steam-wishlist-sales"
SCRIPT="$INSTALL_DIR/steam-wishlist-sales.sh"

echo ""
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║   🎮  SWSC — Patch v2.0 → v2.0.1                      ║"
echo "  ╚════════════════════════════════════════════════════════╝"
echo ""

# ── Vérifications ──
if [ "$EUID" -ne 0 ]; then err "Ce script doit être exécuté en tant que root (sudo)"; exit 1; fi
if [ ! -f "$SCRIPT" ]; then err "Script non trouvé : $SCRIPT"; exit 1; fi

# ── Détection de version ──
CURRENT=$(grep -oP 'version">v\K[^<]+' "$SCRIPT" | head -1)
step "Version actuelle : v${CURRENT:-inconnue}"

if [ "$CURRENT" = "2.0.1" ]; then
    ok "Déjà en v2.0.1, rien à faire."
    exit 0
fi

# ── Sauvegarde ──
step "Sauvegarde..."
cp "$SCRIPT" "${SCRIPT}.v${CURRENT:-backup}.bak"
ok "Sauvegarde : ${SCRIPT}.v${CURRENT:-backup}.bak"

# ═══════════════════════════════════════════════════════════════
# PATCH 1 : Remplacer la page intermédiaire par <a>.click()
#
# On utilise un script Python pour remplacer le bloc de la
# fonction openCartInSteam car sed gère mal le multiligne
# avec des caractères spéciaux (guillemets, backslashes...)
# ═══════════════════════════════════════════════════════════════
step "Application du patch (ouverture directe Steam)..."

python3 << 'PYTHON_PATCH'
import re

with open("/opt/steam-wishlist-sales/steam-wishlist-sales.sh", "r", encoding="utf-8") as f:
    c = f.read()

# Pattern : trouver la fonction openCartInSteam complète
# Elle commence par "function openCartInSteam()" et se termine avant "function toggleSidebar()"
old_pattern = re.compile(
    r'function openCartInSteam\(\) \{.*?\n\}',
    re.DOTALL
)

new_function = r"""function openCartInSteam() {
    var sel = document.querySelectorAll('.card.selected');
    var ids = [];
    sel.forEach(function(c) {
        var m = c.href.match(/\/app\/(\d+)/);
        if (m) ids.push(m[1]);
    });
    if (ids.length === 0) return;
    for (var i = 0; i < ids.length; i++) {
        (function(id, delay) {
            setTimeout(function() {
                var a = document.createElement('a');
                a.href = 'https://store.steampowered.com/app/' + id + '/';
                a.target = '_blank';
                a.rel = 'noopener';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
            }, delay);
        })(ids[i], i * 400);
    }
}"""

result, count = old_pattern.subn(lambda m: new_function, c)

if count == 0:
    print("SKIP: fonction openCartInSteam non trouvée (déjà patchée ?)")
else:
    print(f"PATCHED: {count} remplacement(s)")

with open("/opt/steam-wishlist-sales/steam-wishlist-sales.sh", "w", encoding="utf-8") as f:
    f.write(result)
PYTHON_PATCH

ok "Fonction openCartInSteam patchée"

# ═══════════════════════════════════════════════════════════════
# PATCH 2 : Mettre à jour le numéro de version dans le HTML
#
# sed -i remplace en place :
#   s/>v2.0</>v2.0.1</g  → badge sidebar + mobile bar
#   s/SWSC v2.0/SWSC v2.0.1/g → modale d'aide
# ═══════════════════════════════════════════════════════════════
step "Mise à jour du numéro de version..."

sed -i 's/>v2\.0</>v2.0.1</g' "$SCRIPT"
sed -i 's/SWSC v2\.0/SWSC v2.0.1/g' "$SCRIPT"

ok "Version → v2.0.1"

# ── Vérification ──
step "Vérification..."
NEW_VER=$(grep -oP 'version">v\K[^<]+' "$SCRIPT" | head -1)
if [ "$NEW_VER" = "2.0.1" ]; then
    ok "Patch appliqué avec succès ✓"
else
    err "Échec ! Restauration..."
    cp "${SCRIPT}.v${CURRENT:-backup}.bak" "$SCRIPT"
    err "Ancien script restauré."
    exit 1
fi

echo ""
echo "  ╔════════════════════════════════════════════════════════╗"
echo "  ║   ✅  Patch v2.0.1 appliqué !                         ║"
echo "  ║                                                        ║"
echo "  ║   Relancez un scan pour regénérer le HTML :            ║"
echo "  ║   sudo $SCRIPT   ║"
echo "  ╚════════════════════════════════════════════════════════╝"
echo ""
