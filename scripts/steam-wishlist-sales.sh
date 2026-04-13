#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Steam Wishlist Sales - Générateur de page HTML statique
# ═══════════════════════════════════════════════════════════════
#
# Utilise l'API Steam :
#   1. IWishlistService/GetWishlist → récupère les app IDs
#   2. appdetails (par lots) → récupère les prix et promos
#   3. appdetails (individuel) → récupère noms/images/genres
#      (avec cache intelligent pour éviter les appels redondants)
#
# Dépendances : curl, jq, bc
#   sudo apt install curl jq bc
#
# Usage :
#   ./steam-wishlist-sales.sh
#
# Cron (toutes les 6h à partir de 19h05) :
#   5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1
#
# ═══════════════════════════════════════════════════════════════

# ── Configuration ──────────────────────────────────────────────
STEAM_ID="VOTRE_STEAM_ID"
OUTPUT_DIR="/var/www/steam-wishlist-sales"
OUTPUT_FILE="${OUTPUT_DIR}/index.html"
CACHE_FILE="${OUTPUT_DIR}/cache.json"
PREVIOUS_SALES_FILE="${OUTPUT_DIR}/previous_sales.json"
ENDOFSALES_FLAG="${OUTPUT_DIR}/endofsales.flag"
SALE_DATES_FILE="${OUTPUT_DIR}/sale_dates.json"
TEMP_DIR="/tmp/steam-wishlist-$$"
LOCK_FILE="/tmp/steam-wishlist-sales.lock"
BATCH_SIZE=30
DELAY_SECONDS=2
COUNTRY_CODE="fr"
SCAN_HOURS="19"

# ── Couleurs pour le log ──────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

# ── Vérification du lock ─────────────────────────────────────
if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
    if [ "$LOCK_AGE" -lt 360 ]; then
        warn "Une mise à jour est déjà en cours (depuis ${LOCK_AGE}s). Abandon."
        exit 0
    fi
    warn "Lock périmé détecté (${LOCK_AGE}s), suppression."
    rm -f "$LOCK_FILE"
fi

touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; rm -rf "$TEMP_DIR"' EXIT

# ── Vérification des dépendances ──────────────────────────────
for cmd in curl jq bc; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Dépendance manquante : $cmd"
        exit 1
    fi
done

# ── Préparation ───────────────────────────────────────────────
mkdir -p "$TEMP_DIR"
mkdir -p "$OUTPUT_DIR"

# Initialiser le cache s'il n'existe pas
if [ ! -f "$CACHE_FILE" ]; then
    echo '{}' > "$CACHE_FILE"
    chmod 644 "$CACHE_FILE"
    chown www-data:www-data "$CACHE_FILE" 2>/dev/null
fi

START_TIME=$(date +%s)
log "Démarrage de la récupération de la wishlist Steam"
log "Steam ID : $STEAM_ID"

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 1 : Récupérer la liste des app IDs via IWishlistService
# ═══════════════════════════════════════════════════════════════
log "Récupération de la wishlist..."

WISHLIST_FILE="$TEMP_DIR/wishlist.json"
HTTP_CODE=$(curl -sL -o "$WISHLIST_FILE" -w "%{http_code}" \
    --connect-timeout 15 \
    --max-time 60 \
    "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=${STEAM_ID}")

if [ "$HTTP_CODE" -ne 200 ]; then
    err "Impossible de récupérer la wishlist (HTTP $HTTP_CODE)"
    exit 1
fi

APP_IDS=($(jq -r '.response.items[].appid' "$WISHLIST_FILE" 2>/dev/null))
TOTAL=${#APP_IDS[@]}

if [ "$TOTAL" -eq 0 ]; then
    err "Wishlist vide ou inaccessible."
    exit 1
fi

ok "Wishlist récupérée : $TOTAL jeux"

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 2 : Récupérer les prix par lots via appdetails
# ═══════════════════════════════════════════════════════════════
log "Récupération des prix par lots de $BATCH_SIZE..."

PRICES_FILE="$TEMP_DIR/all_prices.json"
echo '{}' > "$PRICES_FILE"

BATCH_NUM=0
TOTAL_BATCHES=$(( (TOTAL + BATCH_SIZE - 1) / BATCH_SIZE ))

for (( i=0; i<TOTAL; i+=BATCH_SIZE )); do
    BATCH_NUM=$((BATCH_NUM + 1))

    BATCH_IDS=""
    for (( j=i; j<i+BATCH_SIZE && j<TOTAL; j++ )); do
        if [ -n "$BATCH_IDS" ]; then
            BATCH_IDS="${BATCH_IDS},"
        fi
        BATCH_IDS="${BATCH_IDS}${APP_IDS[$j]}"
    done

    BATCH_COUNT=$(( j - i ))
    log "Lot $BATCH_NUM/$TOTAL_BATCHES ($BATCH_COUNT jeux)..."

    BATCH_FILE="$TEMP_DIR/batch_${BATCH_NUM}.json"
    HTTP_CODE=$(curl -sL -o "$BATCH_FILE" -w "%{http_code}" \
        --connect-timeout 15 \
        --max-time 30 \
        "https://store.steampowered.com/api/appdetails?appids=${BATCH_IDS}&cc=${COUNTRY_CODE}&filters=price_overview")

    if [ "$HTTP_CODE" -eq 200 ]; then
            if jq -e 'type == "object"' "$BATCH_FILE" &>/dev/null; then
                jq -s '.[0] * .[1]' "$PRICES_FILE" "$BATCH_FILE" > "$TEMP_DIR/merged.json"
                mv "$TEMP_DIR/merged.json" "$PRICES_FILE"
            else
                warn "Lot $BATCH_NUM : réponse non-objet, ignoré."
            fi
    else
        warn "Lot $BATCH_NUM : HTTP $HTTP_CODE, ignoré."
    fi

    if [ $BATCH_NUM -lt $TOTAL_BATCHES ]; then
        sleep "$DELAY_SECONDS"
    fi
done

ok "Prix récupérés pour tous les lots."

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 3 : Filtrer les jeux en promotion
# ═══════════════════════════════════════════════════════════════
log "Filtrage des jeux en promotion..."

SALES_FILE="$TEMP_DIR/sales.json"

jq '
  [
    to_entries[]
    | select(.value | type == "object")
    | select(.value.success == true)
    | select(.value.data | type == "object")
    | select(.value.data.price_overview != null)
    | select(.value.data.price_overview | type == "object")
    | select(.value.data.price_overview.discount_percent > 0)
    | {
        appid: .key,
        name: ("App " + .key),
        capsule: ("https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/" + .key + "/header.jpg"),
        normal_price: .value.data.price_overview.initial,
        sale_price: .value.data.price_overview.final,
        discount_pct: .value.data.price_overview.discount_percent,
        genres: []
      }
  ]
  | sort_by(.name | ascii_downcase)
' "$PRICES_FILE" > "$SALES_FILE" 2>/dev/null || echo '[]' > "$SALES_FILE"

SALE_COUNT=$(jq 'length' "$SALES_FILE" 2>/dev/null || echo "0")
SALE_COUNT=${SALE_COUNT:-0}
ok "Jeux en promotion : $SALE_COUNT"

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 4 : Récupérer noms/images/genres (avec CACHE intelligent)
# ═══════════════════════════════════════════════════════════════
if [ "$SALE_COUNT" -gt 0 ]; then
    SALE_IDS=($(jq -r '.[].appid' "$SALES_FILE"))
    NAMES_FILE="$TEMP_DIR/names.json"

    # Copier le cache existant comme base de travail
    cp "$CACHE_FILE" "$NAMES_FILE"

    # Identifier les IDs absents du cache
    MISSING_IDS=()
    CACHED_COUNT=0
    for APPID in "${SALE_IDS[@]}"; do
        HAS_CACHE=$(jq -r --arg id "$APPID" 'if .[$id] and .[$id].name and (.[$id].name | length > 0) then "yes" else "no" end' "$NAMES_FILE" 2>/dev/null)
        if [ "$HAS_CACHE" = "yes" ]; then
            CACHED_COUNT=$((CACHED_COUNT + 1))
        else
            MISSING_IDS+=("$APPID")
        fi
    done

    MISSING_COUNT=${#MISSING_IDS[@]}
    ok "Cache : $CACHED_COUNT jeux en cache, $MISSING_COUNT à récupérer"

    # Ne récupérer que les jeux manquants
    if [ "$MISSING_COUNT" -gt 0 ]; then
        log "Récupération des noms/genres de $MISSING_COUNT nouveaux jeux..."

        DONE=0
        for APPID in "${MISSING_IDS[@]}"; do
            DONE=$((DONE + 1))
            DETAIL_FILE="$TEMP_DIR/name_${APPID}.json"

            HTTP_CODE=$(curl -sL --compressed -o "$DETAIL_FILE" -w "%{http_code}" \
                --connect-timeout 10 \
                --max-time 15 \
                "https://store.steampowered.com/api/appdetails?appids=${APPID}&cc=${COUNTRY_CODE}")

            if [ "$HTTP_CODE" -eq 200 ] && jq -e 'type == "object"' "$DETAIL_FILE" &>/dev/null; then
                # Extraire nom, image et genres en une seule passe jq
                ENTRY_JSON=$(jq --arg id "$APPID" '
                    .[$id] |
                    if .success == true and .data then
                        {
                            name: (.data.name // ""),
                            img: (.data.header_image // ""),
                            genres: ([.data.genres[]?.description] | join(",")),
                            cats: ([.data.categories[]?.description] | join(",")),
                            metacritic: (.data.metacritic.score // null),
                            desc: (.data.short_description // "")
                        }
                    else null end
                ' "$DETAIL_FILE" 2>/dev/null)

                if [ "$ENTRY_JSON" != "null" ] && [ -n "$ENTRY_JSON" ]; then
                    # Insérer dans le fichier names
                    jq --arg id "$APPID" --argjson entry "$ENTRY_JSON" \
                       '. + {($id): $entry}' \
                       "$NAMES_FILE" > "$TEMP_DIR/names_merged.json"
                    mv "$TEMP_DIR/names_merged.json" "$NAMES_FILE"
                fi
            fi

            if [ $((DONE % 20)) -eq 0 ]; then
                log "  $DONE/$MISSING_COUNT noms récupérés..."
            fi

            sleep 1
        done

        ok "Nouveaux noms récupérés : $DONE/$MISSING_COUNT"
    else
        ok "Tous les jeux sont en cache ! Aucun appel API nécessaire."
    fi

    # Sauvegarder le cache mis à jour
    cp "$NAMES_FILE" "$CACHE_FILE"
    chmod 644 "$CACHE_FILE"
    chown www-data:www-data "$CACHE_FILE" 2>/dev/null

    # Enrichir les données de vente avec noms + genres du cache
    ENRICHED_FILE="$TEMP_DIR/sales_enriched.json"
    jq --slurpfile names "$NAMES_FILE" '
      [
        .[] | . as $game |
        ($names[0][$game.appid] // null) as $detail |
        . + {
          name: (if $detail and $detail.name and ($detail.name | length > 0) then $detail.name else $game.name end),
          capsule: (if $detail and $detail.img and ($detail.img | length > 0) then $detail.img else $game.capsule end),
          genres: (if $detail and $detail.genres and ($detail.genres | length > 0) then ($detail.genres | split(",")) else [] end),
          cats: (if $detail and $detail.cats and ($detail.cats | length > 0) then ($detail.cats | split(",")) else [] end),
          metacritic: (if $detail then ($detail.metacritic // null) else null end),
          desc: (if $detail then ($detail.desc // "") else "" end)
        }
      ]
      | sort_by(.name | ascii_downcase)
    ' "$SALES_FILE" > "$ENRICHED_FILE" 2>/dev/null
    mv "$ENRICHED_FILE" "$SALES_FILE"
fi

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 5 : Comparer avec le scan précédent (badges New / Prix)
# ═══════════════════════════════════════════════════════════════
if [ -f "$PREVIOUS_SALES_FILE" ]; then
    log "Comparaison avec le scan précédent..."
    # Ajouter un champ "badge" à chaque jeu
    BADGED_FILE="$TEMP_DIR/sales_badged.json"
    jq --slurpfile prev "$PREVIOUS_SALES_FILE" '
      ($prev[0] // {}) as $old |
      [
        .[] |
        .appid as $id |
        if ($old[$id] == null) then
          . + { badge: "new" }
        elif (.sale_price > $old[$id]) then
          . + { badge: "price_up" }
        elif (.sale_price < $old[$id]) then
          . + { badge: "price_down" }
        else
          . + { badge: "" }
        end
      ]
    ' "$SALES_FILE" > "$BADGED_FILE" 2>/dev/null
    if [ -s "$BADGED_FILE" ]; then
        mv "$BADGED_FILE" "$SALES_FILE"
        NEW_COUNT=$(jq '[.[] | select(.badge == "new")] | length' "$SALES_FILE" 2>/dev/null || echo "0")
        UP_COUNT=$(jq '[.[] | select(.badge == "price_up")] | length' "$SALES_FILE" 2>/dev/null || echo "0")
        DOWN_COUNT=$(jq '[.[] | select(.badge == "price_down")] | length' "$SALES_FILE" 2>/dev/null || echo "0")
        ok "Badges : $NEW_COUNT nouveau(x), $UP_COUNT prix en hausse, $DOWN_COUNT prix en baisse"
    fi
else
    log "Premier scan : pas de données précédentes pour comparaison."
    # Ajouter un badge vide à tous les jeux
    jq '[ .[] | . + { badge: "" } ]' "$SALES_FILE" > "$TEMP_DIR/sales_nb.json" 2>/dev/null
    if [ -s "$TEMP_DIR/sales_nb.json" ]; then
        mv "$TEMP_DIR/sales_nb.json" "$SALES_FILE"
    fi
fi

# Sauvegarder les prix actuels pour le prochain scan
jq '[ .[] | { key: .appid, value: .sale_price } ] | from_entries' "$SALES_FILE" > "$PREVIOUS_SALES_FILE" 2>/dev/null
chmod 644 "$PREVIOUS_SALES_FILE"
chown www-data:www-data "$PREVIOUS_SALES_FILE" 2>/dev/null

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 6 : Scraper les dates de fin de promo (si activé)
# ═══════════════════════════════════════════════════════════════
if [ -f "$ENDOFSALES_FLAG" ] && [ "$SALE_COUNT" -gt 0 ]; then
    log "Récupération des dates de fin de promotion..."
    DATES_TMP=$(mktemp)
    echo "{" > "$DATES_TMP"

    APPIDS=$(jq -r '.[].appid' "$SALES_FILE")
    EOS_TOTAL=$(echo "$APPIDS" | wc -w)
    COUNT=0
    FOUND=0
    FIRST=true

    for APPID in $APPIDS; do
        COUNT=$((COUNT + 1))
        printf "\r  [%d/%d] App %s..." "$COUNT" "$EOS_TOTAL" "$APPID" >&2

        PAGE=$(curl -sL --max-time 15 \
            -H "Cookie: birthtime=0; wants_mature_content=1" \
            "https://store.steampowered.com/app/${APPID}/" 2>/dev/null)

        END_TS=$(echo "$PAGE" | grep -oP 'InitDailyDealTimer\s*\(\s*\$DiscountCountdown\s*,\s*\K\d{10}' | head -1)

        # Pattern 2 : texte "prend fin le DD mois" (FR) ou "Offer ends DD month" (EN)
        if [ -z "$END_TS" ]; then
            DATE_TEXT=$(echo "$PAGE" | grep -oP '(prend fin le |Offer ends )\K[^<]+' | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$DATE_TEXT" ]; then
                # Convertir les mois français en anglais pour date -d
                EN_DATE=$(echo "$DATE_TEXT" | sed \
                    -e 's/janvier/January/i' -e 's/février/February/i' -e 's/mars/March/i' \
                    -e 's/avril/April/i' -e 's/mai/May/i' -e 's/juin/June/i' \
                    -e 's/juillet/July/i' -e 's/août/August/i' -e 's/septembre/September/i' \
                    -e 's/octobre/October/i' -e 's/novembre/November/i' -e 's/décembre/December/i')
                # Ajouter l'année courante si absente
                if ! echo "$EN_DATE" | grep -qP '\d{4}'; then
                    EN_DATE="$EN_DATE $(date +%Y)"
                fi
                END_TS=$(date -d "$EN_DATE 18:00" +%s 2>/dev/null)
            fi
        fi

        if [ -n "$END_TS" ] && [ "$END_TS" -gt 0 ] 2>/dev/null; then
            if [ "$FIRST" = true ]; then FIRST=false; else echo "," >> "$DATES_TMP"; fi
            echo "\"$APPID\": $END_TS" >> "$DATES_TMP"
            FOUND=$((FOUND + 1))
        fi

        sleep 1
    done

    echo "" >> "$DATES_TMP"
    echo "}" >> "$DATES_TMP"

    mv "$DATES_TMP" "$SALE_DATES_FILE"
    chmod 644 "$SALE_DATES_FILE"
    chown www-data:www-data "$SALE_DATES_FILE" 2>/dev/null
    echo ""
    ok "Dates de fin récupérées : ${FOUND}/${EOS_TOTAL} jeux"
else
    if [ ! -f "$ENDOFSALES_FLAG" ]; then
        rm -f "$SALE_DATES_FILE" 2>/dev/null
    fi
fi

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 7 : Générer la page HTML finale
# ═══════════════════════════════════════════════════════════════
ELAPSED=$(( $(date +%s) - START_TIME ))
BEST_DISCOUNT=$(jq '[.[].discount_pct] | if length > 0 then max else 0 end' "$SALES_FILE" 2>/dev/null || echo "0")
CHEAPEST=$(jq '[.[].sale_price] | if length > 0 then min else 0 end' "$SALES_FILE" 2>/dev/null || echo "0")
CHEAPEST_FMT=$(echo "scale=2; ${CHEAPEST:-0} / 100" | bc 2>/dev/null | sed 's/^\./0./;s/\./,/' || echo "0,00")
MAX_PRICE=$(jq '[.[].sale_price] | if length > 0 then max else 0 end' "$SALES_FILE" 2>/dev/null || echo "0")
MAX_PRICE_EUR=$(echo "scale=0; (${MAX_PRICE:-0} + 99) / 100" | bc 2>/dev/null || echo "0")
NOW=$(date '+%d/%m/%Y à %H:%M')

# Extraire la liste unique des genres pour les boutons filtres
ALL_GENRES=$(jq -r '[.[].genres[]?] | unique | .[]' "$SALES_FILE" 2>/dev/null | grep -v '^$' | sort)

GENRE_BUTTONS=""
while IFS= read -r genre; do
    if [ -n "$genre" ]; then
        GCOUNT=$(jq -r --arg g "$genre" '[.[] | select(.genres[]? == $g)] | length' "$SALES_FILE" 2>/dev/null)
        GENRE_BUTTONS="${GENRE_BUTTONS}<button class=\"sidebar-btn\" data-genre=\"${genre}\"><span>${genre}</span><span class=\"count\">${GCOUNT}</span></button>"
    fi
done <<< "$ALL_GENRES"

# Extraire les catégories de jeu (filtrer les catégories pertinentes)
ALL_CATS=$(jq -r '[.[].cats[]?] | unique | .[]' "$SALES_FILE" 2>/dev/null | grep -v '^$' | grep -iE "single.player|multi.player|co.op|pvp|mmo|cross.platform|shared.split|lan|un joueur|multijoueur|coop|coopératif|joueur contre joueur|JcJ|écran partagé" | sort)

CAT_BUTTONS=""
while IFS= read -r cat; do
    if [ -n "$cat" ]; then
        CCOUNT=$(jq -r --arg c "$cat" '[.[] | select(.cats[]? == $c)] | length' "$SALES_FILE" 2>/dev/null)
        CAT_BUTTONS="${CAT_BUTTONS}<button class=\"sidebar-btn\" data-cat=\"${cat}\"><span>${cat}</span><span class=\"count\">${CCOUNT}</span></button>"
    fi
done <<< "$ALL_CATS"

# Générer les cartes HTML avec data-genres
CARDS_HTML=$(jq -r '
  .[] |
  (if .badge == "new" then "<span class=\"status-badge new-badge\">NEW</span>"
   elif .badge == "price_up" then "<span class=\"status-badge up-badge\">Prix &#128316;</span>"
   elif .badge == "price_down" then "<span class=\"status-badge down-badge\">Prix &#128317;</span>"
   else "" end) as $status_html |
  (if .metacritic then "<span class=\"metacritic " + (if .metacritic >= 75 then "mc-high" elif .metacritic >= 50 then "mc-mid" else "mc-low" end) + "\">" + (.metacritic | tostring) + "</span>" else "" end) as $mc_html |
  (.normal_price / 100 | tostring | split(".") | if length == 2 then .[0] + "," + (.[1] + "00")[:2] else .[0] + ",00" end) as $old_price |
  (.sale_price / 100 | tostring | split(".") | if length == 2 then .[0] + "," + (.[1] + "00")[:2] else .[0] + ",00" end) as $new_price |
  "<a class=\"card\" data-name=\"\(.name | gsub("\""; "&quot;"))\" data-sale=\"\(.sale_price)\" data-disc=\"\(.discount_pct)\" data-genres=\"\([.genres[]?] | join(","))\" data-cats=\"\([.cats[]?] | join(","))\" data-badge=\"\(.badge // "")\" data-mc=\"\(.metacritic // 0)\" title=\"\(.desc | gsub("\""; "&quot;") | gsub("<[^>]*>"; ""))\" href=\"https://store.steampowered.com/app/\(.appid)\" target=\"_blank\" rel=\"noopener\">"
  + "<div class=\"img-wrap\">"
  + "<img src=\"\(.capsule)\" alt=\"\(.name | gsub("\""; "&quot;"))\" loading=\"lazy\" />"
  + "<span class=\"badge " + (if .discount_pct >= 70 then "badge-high" elif .discount_pct >= 30 then "badge-mid" else "badge-low" end) + "\">-\(.discount_pct)%</span>"
  + $status_html
  + "</div>"
  + "<div class=\"info\">"
  + "<div class=\"name\">\(.name | gsub("<"; "&lt;") | gsub(">"; "&gt;"))</div>"
  + "<div class=\"genres-row\">\([.genres[]?] | map("<span class=\"genre-tag\">" + (. | gsub("<"; "&lt;") | gsub(">"; "&gt;")) + "</span>") | join(""))</div>"
  + "<div class=\"prices\">"
  + "<span class=\"old\">\($old_price)\u20ac</span>"
  + "<span class=\"new\">\($new_price)\u20ac</span>"
  + $mc_html
  + "</div>"
  + "</div></a>"
' "$SALES_FILE")

log "Génération de la page HTML..."

# ── Début du HTML : CSS complet (thème moderne + thème classic) ──
cat > "$OUTPUT_FILE" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>&#x1F3AE;</text></svg>">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Steam Wishlist Sales Checker</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Exo+2:wght@400;600;700;800&family=Outfit:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    :root {
        --bg-deep: #070a0f; --bg-card: #111822; --bg-sidebar: #0a0f17;
        --border: rgba(102,192,244,0.08); --border-hover: rgba(102,192,244,0.2);
        --accent: #66c0f4; --accent-glow: rgba(102,192,244,0.12);
        --green: #a4d007; --orange: #f39c12; --red: #e05a4f;
        --text: #c6d4df; --text-dim: #5a6a78; --text-muted: #3e4f5e;
        --font-h: 'Exo 2', sans-serif; --font-b: 'Outfit', sans-serif;
    }
    body { background: var(--bg-deep); color: var(--text); font-family: var(--font-b); min-height: 100vh; display: flex; overflow-x: hidden; }
    ::-webkit-scrollbar { width: 5px; } ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb { background: rgba(102,192,244,0.12); border-radius: 3px; }
    .sidebar { position: fixed; top: 0; left: 0; bottom: 0; width: 260px; background: var(--bg-sidebar); border-right: 1px solid var(--border); display: flex; flex-direction: column; z-index: 10; overflow-y: auto; transition: background 0.3s, transform 0.3s ease; }
    .sidebar.open { transform: translateX(0); }
    .sidebar-logo { padding: 16px 14px; border-bottom: 1px solid var(--border); display: flex; align-items: center; gap: 8px; }
    .sidebar-logo .icon { font-size: 1.3rem; }
    .sidebar-logo h1 { font-family: var(--font-h); font-size: 0.88rem; font-weight: 700; color: #fff; letter-spacing: 0.02em; text-transform: uppercase; }
    .sidebar-logo .version { font-size: 0.58rem; color: var(--accent); background: var(--accent-glow); padding: 2px 6px; border-radius: 8px; font-weight: 600; }
    .sidebar-section { padding: 10px 8px 4px; }
    .sidebar-section-title { font-size: 0.62rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--text-muted); margin-bottom: 5px; padding-left: 6px; }
    .sidebar-btn { display: flex; align-items: center; gap: 8px; width: 100%; padding: 5px 8px; border: none; background: transparent; color: var(--text-dim); font-size: 0.88rem; font-family: var(--font-b); cursor: pointer; border-radius: 6px; transition: all 0.2s; margin-bottom: 1px; text-align: left; }
    .sidebar-btn:hover { background: rgba(255,255,255,0.03); color: var(--text); }
    .sidebar-btn.active { background: linear-gradient(135deg, rgba(102,192,244,0.12), rgba(102,192,244,0.06)); color: var(--accent); font-weight: 600; }
    .sidebar-btn .count { margin-left: auto; font-size: 0.62rem; color: var(--text-muted); background: rgba(255,255,255,0.04); padding: 1px 5px; border-radius: 8px; }
    .sidebar-divider { height: 1px; background: var(--border); margin: 4px 8px; }
    .sidebar-meta { margin-top: auto; padding: 10px 12px; border-top: 1px solid var(--border); font-size: 0.68rem; color: var(--text-muted); line-height: 1.5; }
    .sidebar-meta strong { color: var(--accent); }
    .new-only-btn.active { background: linear-gradient(135deg, rgba(102,192,244,0.14), rgba(102,192,244,0.06)); color: var(--accent); font-weight: 600; }
    .expiring-btn.active { background: linear-gradient(135deg, rgba(224,90,79,0.14), rgba(224,90,79,0.06)); color: var(--red); font-weight: 600; }
    .cat-active { background: linear-gradient(135deg, rgba(164,208,7,0.12), rgba(164,208,7,0.06)); color: var(--green); font-weight: 600; }
    .main { margin-left: 260px; flex: 1; padding: 18px 22px; position: relative; z-index: 1; }
    .topbar { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
    .search-box { flex: 1; max-width: 400px; position: relative; }
    .search-box input { width: 100%; padding: 8px 14px 8px 36px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; color: var(--text); font-family: var(--font-b); font-size: 0.9rem; outline: none; transition: border-color 0.2s; }
    .search-box input:focus { border-color: var(--accent); }
    .search-box input::placeholder { color: var(--text-muted); }
    .search-box::before { content: '\01F50D'; position: absolute; left: 11px; top: 50%; transform: translateY(-50%); font-size: 0.74rem; opacity: 0.3; }
    .topbar-right { display: flex; align-items: center; gap: 8px; margin-left: auto; }
    .count-topbar { font-size: 0.95rem; font-weight: 600; color: var(--green); font-family: var(--font-h); }
    .gear-wrap { position: relative; }
    .gear-btn { display: flex; align-items: center; justify-content: center; width: 36px; height: 36px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; color: var(--text-dim); font-size: 1.15rem; cursor: pointer; transition: all 0.25s; }
    .gear-btn:hover { border-color: var(--border-hover); color: var(--text); transform: rotate(45deg); }
    .gear-dropdown { display: none; position: absolute; top: 42px; right: 0; background: #0c1018; border: 1px solid var(--border-hover); border-radius: 8px; padding: 6px 0; min-width: 260px; box-shadow: 0 10px 35px rgba(0,0,0,0.5); z-index: 100; }
    .gear-wrap.open .gear-dropdown { display: block; }
    .gear-item { display: flex; align-items: center; gap: 10px; padding: 8px 14px; color: var(--text-dim); font-size: 0.84rem; cursor: pointer; transition: all 0.15s; border: none; background: none; width: 100%; font-family: var(--font-b); text-decoration: none; text-align: left; }
    .gear-item:hover { background: rgba(255,255,255,0.04); color: var(--text); }
    .gear-item .g-ico { width: 18px; text-align: center; }
    .gear-item.active-theme { color: var(--accent); font-weight: 600; }
    .gear-item.active-theme::after { content: '\2713'; margin-left: auto; font-size: 0.7rem; }
    .gear-sep { height: 1px; background: var(--border); margin: 4px 12px; }
    .gear-danger { color: var(--red); }
    .gear-danger:hover { background: rgba(224,90,79,0.06); }
    .stats-row { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 10px; margin-bottom: 16px; }
    .stat-card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px; transition: border-color 0.2s; }
    .stat-card:hover { border-color: var(--border-hover); }
    .stat-label { font-size: 0.64rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--text-muted); margin-bottom: 2px; }
    .stat-value { font-family: var(--font-h); font-size: 1.35rem; font-weight: 700; color: #fff; white-space: nowrap; }
    .stat-value.accent { color: var(--accent); }
    .stat-value.green { color: var(--green); }
    .toolbar-row { display: flex; align-items: center; gap: 6px; margin-bottom: 14px; flex-wrap: wrap; }
    .toolbar-row .label { font-size: 0.8rem; color: var(--text-muted); font-weight: 600; letter-spacing: 0.05em; text-transform: uppercase; margin-right: 2px; }
    .sort-btn { padding: 5px 12px; background: transparent; border: 1px solid var(--border); color: var(--text-dim); border-radius: 14px; font-size: 0.8rem; font-family: var(--font-b); cursor: pointer; transition: all 0.2s; }
    .sort-btn:hover { border-color: var(--border-hover); color: var(--text); }
    .sort-btn.active { background: var(--accent); color: #fff; border-color: transparent; font-weight: 600; }
    .price-slider { display: flex; align-items: center; gap: 8px; margin-left: 10px; padding-left: 10px; border-left: 1px solid var(--border); flex: 1; max-width: 320px; }
    .price-slider label { font-size: 0.74rem; color: var(--text-muted); white-space: nowrap; }
    .price-slider input[type=range] { -webkit-appearance: none; appearance: none; flex: 1; min-width: 120px; height: 4px; background: rgba(102,192,244,0.12); border-radius: 2px; outline: none; }
    .price-slider input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 14px; height: 14px; border-radius: 50%; background: var(--accent); cursor: pointer; border: 2px solid var(--bg-deep); }
    .price-slider input[type=range]::-moz-range-thumb { width: 14px; height: 14px; border-radius: 50%; background: var(--accent); cursor: pointer; border: 2px solid var(--bg-deep); }
    .price-val { font-size: 0.88rem; color: var(--accent); font-weight: 600; font-family: var(--font-h); min-width: 40px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; }
    .card { background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; text-decoration: none; color: inherit; display: flex; flex-direction: column; transition: all 0.3s; opacity: 0; animation: fadeUp 0.4s ease forwards; }
    .card:hover { border-color: var(--border-hover); transform: translateY(-3px); box-shadow: 0 8px 28px rgba(0,0,0,0.35); }
    @keyframes fadeUp { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: translateY(0); } }
    .img-wrap { position: relative; aspect-ratio: 460/215; overflow: hidden; background: #080c12; }
    .img-wrap img { width: 100%; height: 100%; object-fit: cover; transition: transform 0.4s; }
    .card:hover .img-wrap img { transform: scale(1.06); }
    .badge { position: absolute; top: 0; right: 0; color: #fff; font-family: var(--font-h); font-weight: 800; font-size: 0.95rem; padding: 5px 12px 5px 14px; border-radius: 0 0 0 8px; text-shadow: 0 1px 3px rgba(0,0,0,0.3); }
    .badge-high { background: linear-gradient(135deg, #a4d007, #7aa800); }
    .badge-mid { background: linear-gradient(135deg, #f39c12, #d68910); }
    .badge-low { background: linear-gradient(135deg, #e05a4f, #c0392b); }
    .status-badge { position: absolute; top: 0; left: 0; color: #fff; font-family: var(--font-h); font-weight: 700; font-size: 0.76rem; padding: 4px 10px 4px 8px; border-radius: 0 0 8px 0; text-shadow: 0 1px 2px rgba(0,0,0,0.4); z-index: 2; }
    .new-badge { background: linear-gradient(135deg, #66c0f4, #4a9fd4); }
    .up-badge { background: linear-gradient(135deg, #e05a4f, #c0392b); }
    .down-badge { background: linear-gradient(135deg, #27ae60, #1e8449); }
    .info { padding: 10px 12px 12px; display: flex; flex-direction: column; gap: 4px; flex: 1; }
    .name { font-size: 0.96rem; font-weight: 600; color: #fff; line-height: 1.25; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
    .genres-row { display: flex; gap: 4px; flex-wrap: wrap; }
    .genre-tag { font-size: 0.6rem; padding: 2px 6px; border-radius: 3px; background: rgba(255,255,255,0.04); color: var(--text-dim); font-weight: 600; text-transform: uppercase; letter-spacing: 0.03em; }
    .prices { display: flex; align-items: center; gap: 8px; margin-top: auto; }
    .old { font-size: 0.8rem; color: var(--text-muted); text-decoration: line-through; }
    .new { font-family: var(--font-h); font-size: 1.15rem; font-weight: 800; color: var(--green); }
    .metacritic { display: inline-flex; align-items: center; justify-content: center; min-width: 24px; height: 18px; font-family: var(--font-h); font-weight: 700; font-size: 0.72rem; border-radius: 4px; color: #fff; padding: 0 4px; margin-left: auto; }
    .mc-high { background: #66cc33; } .mc-mid { background: #ffcc33; color: #111; } .mc-low { background: #ff4444; }
    .end-date { display: block; font-size: 0.74rem; color: #8f98a0; margin-top: 2px; }
    .end-date-urgent { color: var(--red); font-weight: 600; }



    .mob-gear { position: relative; margin-left: auto; }
    .sidebar-close { display: none; position: absolute; top: 12px; right: 12px; background: none; border: none; color: var(--text-dim); font-size: 1.3rem; cursor: pointer; z-index: 2; padding: 4px 8px; }
    .sidebar-close:hover { color: var(--text); }
    .mobile-bar { display: none; }
    .empty { text-align: center; padding: 60px 20px; color: var(--text-muted); font-size: 1.1rem; }
    body.classic { --bg-deep: #1e2a16; --bg-card: #2a3a20; --bg-sidebar: #1a2612; --border: rgba(138,154,128,0.15); --border-hover: rgba(138,154,128,0.35); --accent: #8aaa74; --accent-glow: rgba(138,154,128,0.12); --green: #a4d007; --orange: #b8860b; --red: #b03a2e; --text: #d2e8b0; --text-dim: #8a9a80; --text-muted: #5a6a50; --font-h: Tahoma, sans-serif; --font-b: Tahoma, sans-serif; }
    body.classic .card { border-radius: 2px; } body.classic .card:hover { transform: none; box-shadow: 0 2px 8px rgba(0,0,0,0.4); }
    body.classic .card:hover .img-wrap img { transform: none; }
    body.classic .badge, body.classic .status-badge, body.classic .metacritic { border-radius: 2px; }
    body.classic .sort-btn { border-radius: 2px; background: linear-gradient(180deg, #3a4a30 0%, #2a3a20 100%); border-color: #4a5a40; }
    body.classic .sort-btn.active { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); }
    body.classic .sidebar-btn { border-radius: 2px; font-size: 0.82rem; }
    body.classic .stat-card, body.classic .search-box input, body.classic .gear-btn, body.classic .gear-dropdown { border-radius: 2px; }
    body.classic .gear-btn { background: linear-gradient(180deg, #6b8a56 0%, #4a6637 100%); border: 1px solid #7a9a64; }
    body.classic .gear-dropdown { background: #1a2612; border-color: #4a5a40; }
    body.classic .gear-item { color: #8a9a80; } body.classic .gear-item.active-theme { color: #a4d007; }
    body.classic .gear-sep { background: rgba(138,154,128,0.15); } body.classic .gear-danger { color: #b03a2e; }
    body.classic .badge-high { background: #a4d007; } body.classic .badge-mid { background: #b8860b; } body.classic .badge-low { background: #b03a2e; }
    body.classic .new { text-shadow: none; } body.classic .name { color: #d2e8b0; font-size: 0.88rem; }
    body.classic .end-date { font-size: 0.7rem; color: #8a9a80; } body.classic .end-date-urgent { color: #c0392b; }
    body.classic .sidebar-logo .version { border-radius: 2px; }
    body.classic .price-slider input[type=range] { background: rgba(138,154,128,0.2); }
    body.classic .price-slider input[type=range]::-webkit-slider-thumb { background: #7a9a64; border-color: #1e2a16; }
    body.light { --bg-deep: #f0f2f5; --bg-card: #ffffff; --bg-sidebar: #f8f9fb; --border: rgba(0,0,0,0.07); --border-hover: rgba(0,0,0,0.16); --accent: #1a73e8; --accent-glow: rgba(26,115,232,0.08); --green: #2e7d32; --orange: #ef6c00; --red: #c62828; --text: #37474f; --text-dim: #78909c; --text-muted: #b0bec5; }
    body.light .stat-card, body.light .card { box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
    body.light .card:hover { box-shadow: 0 6px 20px rgba(0,0,0,0.08); }
    body.light .sidebar { box-shadow: 1px 0 4px rgba(0,0,0,0.03); }
    body.light .gear-dropdown { background: #fff; box-shadow: 0 8px 28px rgba(0,0,0,0.1); }
    body.light .gear-item { color: #78909c; } body.light .gear-item:hover { background: rgba(0,0,0,0.03); color: #37474f; }
    body.light .gear-item.active-theme { color: #1a73e8; } body.light .gear-sep { background: rgba(0,0,0,0.06); }
    body.light .gear-danger { color: #c62828; }
    body.light .name { color: #212121; } body.light .old { color: #b0bec5; } body.light .new { color: #2e7d32; text-shadow: none; }
    body.light .badge-high { background: #2e7d32; color: #fff; } body.light .badge-mid { background: #ef6c00; color: #fff; } body.light .badge-low { background: #c62828; }
    body.light .new-badge { background: #1a73e8; } body.light .status-badge { text-shadow: none; }
    body.light .metacritic.mc-high { background: #2e7d32; } body.light .metacritic.mc-mid { background: #f9a825; color: #333; }
    body.light .sort-btn.active { background: #1a73e8; color: #fff; }
    body.light .search-box input::placeholder { color: #b0bec5; } body.light .img-wrap { background: #e8eaed; }
    body.light .genre-tag { background: rgba(0,0,0,0.04); }
    body.light .end-date { color: #78909c; } body.light .end-date-urgent { color: #c62828; }
    body.light .stat-value { color: #212121; } body.light .stat-value.accent { color: #1a73e8; } body.light .stat-value.green { color: #2e7d32; }
    body.light .price-slider input[type=range] { background: rgba(26,115,232,0.1); }
    body.light .price-slider input[type=range]::-webkit-slider-thumb { background: #1a73e8; border-color: #f0f2f5; }
    body.light .price-val { color: #1a73e8; } body.light .empty { color: #b0bec5; }
    body.light .sidebar-logo h1 { color: #1a73e8; }
    body.light .sidebar-btn.active { background: linear-gradient(135deg, rgba(26,115,232,0.08), rgba(26,115,232,0.03)); color: #1a73e8; }
    body.light .new-only-btn.active { color: #1a73e8; } body.light .expiring-btn.active { color: #c62828; }
    body.light .cat-active { color: #2e7d32; }
    @media (max-width: 1100px) { .stats-row { grid-template-columns: repeat(3, 1fr); } }
    @media (max-width: 900px) {
        .sidebar { transform: translateX(-100%); }
    
    .mob-gear { position: relative; margin-left: auto; }
    .sidebar-close { display: block; }
        .sidebar.open .sidebar-close { display: block; }
        .main { margin-left: 0; padding: 14px 10px; }
        .mobile-bar { display: flex; align-items: center; gap: 10px; padding: 8px 0; margin-bottom: 10px; }
        .mobile-bar .mob-title { font-family: var(--font-h); font-size: 0.8rem; font-weight: 700; color: #fff; text-transform: uppercase; }
        .mobile-bar .mob-version { font-size: 0.5rem; color: var(--accent); background: var(--accent-glow); padding: 2px 5px; border-radius: 6px; font-weight: 600; }
        .mobile-bar .mob-burger { background: var(--bg-card); border: 1px solid var(--border); border-radius: 8px; width: 36px; height: 36px; display: flex; align-items: center; justify-content: center; font-size: 1.1rem; color: var(--text-dim); cursor: pointer; margin-left: auto; }
        .cart-bar { left: 0; }
    }
    @media (max-width: 640px) { .grid { grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 8px; } .stats-row { grid-template-columns: repeat(2, 1fr); } .price-slider { display: none; } }

    .card-select { position: absolute; top: 8px; left: 8px; width: 22px; height: 22px; border-radius: 4px; border: 2px solid rgba(255,255,255,0.3); background: rgba(0,0,0,0.4); cursor: pointer; z-index: 3; opacity: 0; transition: opacity 0.2s; display: flex; align-items: center; justify-content: center; color: #fff; font-size: 0.8rem; }
    .card:hover .card-select, .card-select.checked { opacity: 1; }
    .card-select.checked { background: var(--accent); border-color: var(--accent); }
    .card.selected { border-color: var(--accent); box-shadow: 0 0 0 2px var(--accent), 0 8px 28px rgba(0,0,0,0.35); }
    .cart-bar { position: fixed; bottom: 0; left: 260px; right: 0; background: var(--bg-card); border-top: 2px solid var(--accent); padding: 12px 24px; display: none; align-items: center; gap: 16px; z-index: 50; box-shadow: 0 -4px 20px rgba(0,0,0,0.4); }
    .cart-bar.visible { display: flex; }
    .cart-info { display: flex; gap: 20px; align-items: center; flex: 1; }
    .cart-stat { font-size: 0.82rem; color: var(--text-dim); }
    .cart-stat strong { color: #fff; font-family: var(--font-h); }
    .cart-stat .savings { color: var(--green); font-weight: 700; }
    .cart-actions { display: flex; gap: 8px; }
    .cart-btn { padding: 8px 18px; border-radius: 6px; border: none; font-family: var(--font-b); font-size: 0.82rem; font-weight: 600; cursor: pointer; transition: all 0.2s; }
    .cart-btn-steam { background: var(--green); color: #111; }
    .cart-btn-steam:hover { filter: brightness(1.15); }
    .cart-btn-clear { background: transparent; border: 1px solid var(--border); color: var(--text-dim); }
    .cart-btn-clear:hover { border-color: var(--border-hover); color: var(--text); }
    @media (max-width: 900px) { .cart-bar { left: 0; } }

    .help-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.6); z-index: 200; align-items: center; justify-content: center; }
    .help-overlay.visible { display: flex; }
    .help-box { background: var(--bg-card); border: 1px solid var(--border-hover); border-radius: 10px; padding: 24px 28px; max-width: 520px; width: 90%; max-height: 80vh; overflow-y: auto; box-shadow: 0 16px 50px rgba(0,0,0,0.5); }
    .help-box h2 { font-family: var(--font-h); font-size: 1.2rem; color: var(--accent); margin-bottom: 14px; }
    .help-box h3 { font-size: 0.88rem; color: var(--green); margin: 12px 0 6px; }
    .help-box p { font-size: 0.8rem; color: var(--text); line-height: 1.6; margin-bottom: 8px; }
    .help-box code { background: rgba(102,192,244,0.1); padding: 1px 6px; border-radius: 3px; font-family: Consolas, monospace; font-size: 0.76rem; color: var(--accent); }
    .help-close { float: right; background: none; border: none; color: var(--text-dim); font-size: 1.3rem; cursor: pointer; }
    .help-close:hover { color: var(--text); }

    .sidebar-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); z-index: 9; }
    .sidebar-overlay.visible { display: block; }
</style>
</head>
<body>

<div class="sidebar-overlay" id="sidebarOverlay" onclick="toggleSidebar()"></div>
<aside class="sidebar" id="sidebar">
    <button class="sidebar-close" onclick="toggleSidebar()">&#10005;</button>
    <div class="sidebar-logo"><span class="icon">&#127918;</span><h1>Steam Wishlist Sales Checker</h1><span class="version">v2.0</span></div>

    <div class="sidebar-section">
        <div class="sidebar-section-title">Filtres rapides</div>
        <button class="sidebar-btn active" data-genre="all"><span>&#128203; Tout</span></button>
        <button class="sidebar-btn new-only-btn" id="newOnlyBtn" onclick="toggleNewOnly()"><span>&#127381; Nouveaut&#233;s</span></button>
        <button class="sidebar-btn expiring-btn" id="expiringBtn" onclick="toggleExpiring()" style="display:none"><span>&#9203; Expire bient&#244;t</span></button>
    </div>

    <div class="sidebar-divider"></div>

    <div class="sidebar-section" id="genreSection">
        <div class="sidebar-section-title">Genres</div>
HTMLHEAD

# ── Partie dynamique (variables Bash interpolées) ──
cat >> "$OUTPUT_FILE" << HTMLMETA
        ${GENRE_BUTTONS}
    </div>

    <div class="sidebar-divider"></div>

    <div class="sidebar-section" id="catSection">
        <div class="sidebar-section-title">Mode de jeu</div>
        <button class="sidebar-btn active" data-cat="all"><span>&#128203; Tous</span></button>
        ${CAT_BUTTONS}
    </div>

    <div class="sidebar-meta">G&#233;n&#233;r&#233; le ${NOW} (${ELAPSED}s)</div>
</aside>

<div class="main">
    <div class="mobile-bar"><span class="mob-title">&#127918; Steam Wishlist Sales Checker</span><span class="mob-version">v2.0</span><button class="mob-burger" onclick="toggleSidebar()">&#9776;</button></div>
    <div class="topbar">
        <div class="search-box"><input type="text" id="search" placeholder="Rechercher un jeu..." /></div>
        <div class="topbar-right">
            <span class="count-topbar" id="count">${SALE_COUNT} jeu$([ "$SALE_COUNT" -gt 1 ] && echo "x") en promo</span>
            <div class="gear-wrap" id="gearWrap">
                <button class="gear-btn" onclick="this.parentElement.classList.toggle('open')">&#9881;</button>
                <div class="gear-dropdown">
                    <a class="gear-item" href="run.php"><span class="g-ico">&#8635;</span> Actualiser le scan</a>
                    <button class="gear-item gear-danger" onclick="clearCache()"><span class="g-ico">&#128465;</span> Vider le cache</button>
                    <div class="gear-sep"></div>
                    <button class="gear-item" id="thModern" onclick="setTheme('modern')"><span class="g-ico">&#10024;</span> Th&#232;me Modern</button>
                    <button class="gear-item" id="thClassic" onclick="setTheme('classic')"><span class="g-ico">&#128421;</span> Th&#232;me Classic Steam</button>
                    <button class="gear-item" id="thLight" onclick="setTheme('light')"><span class="g-ico">&#9728;</span> Th&#232;me Light</button>
                    <div class="gear-sep"></div>
                    <a class="gear-item" href="https://steamdb.info/sales/history/" target="_blank" rel="noopener"><span class="g-ico">&#128197;</span> Calendrier des Soldes</a>
                <div class="gear-sep"></div>
                <button class="gear-item" onclick="showHelp()"><span class="g-ico">&#10067;</span> Aide</button>
                <a class="gear-item" href="https://github.com/W1p3out/steam-wishlist-sales-checker" target="_blank" rel="noopener"><span class="g-ico">&#128187;</span> GitHub</a>
                </div>
            </div>
        </div>
        </div>

    <div class="stats-row">
        <div class="stat-card"><div class="stat-label">Wishlist</div><div class="stat-value">${TOTAL}</div></div>
        <div class="stat-card"><div class="stat-label">En promo</div><div class="stat-value accent">${SALE_COUNT}</div></div>
        <div class="stat-card"><div class="stat-label">Meilleure remise</div><div class="stat-value green">-${BEST_DISCOUNT}%</div></div>
        <div class="stat-card"><div class="stat-label">Prix le plus bas</div><div class="stat-value green">${CHEAPEST_FMT}&#8364;</div></div>
        <div class="stat-card"><div class="stat-label">Dur&#233;e du scan</div><div class="stat-value">${ELAPSED}s</div></div>
        <div class="stat-card"><div class="stat-label">Prochain scan</div><div class="stat-value accent" id="nextScanCard">--:--</div></div>
    </div>

    <div class="toolbar-row">
        <span class="label">Trier :</span>
        <button class="sort-btn active" data-sort="alpha">A&#8594;Z</button>
        <button class="sort-btn" data-sort="alpha_desc">Z&#8594;A</button>
        <button class="sort-btn" data-sort="price_asc">Prix &#8593;</button>
        <button class="sort-btn" data-sort="price_desc">Prix &#8595;</button>
        <button class="sort-btn" data-sort="discount">% Promo</button>
        <button class="sort-btn" data-sort="metacritic">Metacritic</button>
        <div class="price-slider">
            <label>En dessous de</label>
            <input type="range" id="priceMax" min="0" max="${MAX_PRICE_EUR}" value="${MAX_PRICE_EUR}" step="1">
            <span class="price-val" id="priceLabel">${MAX_PRICE_EUR}&#8364;</span>
        </div>
    </div>
HTMLMETA

# ── Grille de cartes ──
echo '<div class="grid" id="grid">' >> "$OUTPUT_FILE"
if [ "$SALE_COUNT" -gt 0 ]; then
    echo "$CARDS_HTML" >> "$OUTPUT_FILE"
else
    echo '<div class="empty">Aucun jeu en promotion dans votre wishlist pour le moment.</div>' >> "$OUTPUT_FILE"
fi
echo '</div>' >> "$OUTPUT_FILE"

# ── JavaScript : injection des heures de scan (interpolé) ──
SCAN_HOURS_JS=$(echo "$SCAN_HOURS" | tr ',' '\n' | sed 's/^//' | tr '\n' ',' | sed 's/,$//')
echo "<script>var SCAN_SCHEDULE = [${SCAN_HOURS_JS}];</script>" >> "$OUTPUT_FILE"

# ── JavaScript (non interpolé) ──
cat >> "$OUTPUT_FILE" << 'HTMLSCRIPT'

<script>
// ── Animations d'entrée ──
document.querySelectorAll('.card').forEach((c, i) => {
    c.style.animationDelay = Math.min(i * 30, 800) + 'ms';
});

// ── Panier (sélection de jeux) ──
document.querySelectorAll('.card').forEach(c => {
    var cb = document.createElement('div');
    cb.className = 'card-select';
    cb.innerHTML = '&#10003;';
    c.querySelector('.img-wrap').appendChild(cb);
    cb.addEventListener('click', function(e) {
        e.preventDefault(); e.stopPropagation();
        c.classList.toggle('selected');
        cb.classList.toggle('checked');
        updateCart();
    });
});
function updateCart() {
    var sel = document.querySelectorAll('.card.selected');
    var bar = document.getElementById('cartBar');
    if (sel.length === 0) { bar.classList.remove('visible'); document.querySelector('.main').style.paddingBottom = ''; return; }
    bar.classList.add('visible');
    document.querySelector('.main').style.paddingBottom = '80px';
    var total = 0, original = 0;
    sel.forEach(function(c) { total += parseInt(c.dataset.sale) || 0; original += parseInt(c.dataset.originalPrice || c.querySelector('.old').textContent.replace(/[^0-9,]/g,'').replace(',','.') * 100) || 0; });
    // Parse original from .old text
    original = 0; total = 0;
    sel.forEach(function(c) {
        total += parseInt(c.dataset.sale) || 0;
        var oldEl = c.querySelector('.old');
        if (oldEl) { original += Math.round(parseFloat(oldEl.textContent.replace(/[^\d,]/g,'').replace(',','.')) * 100); }
    });
    var savings = original - total;
    document.getElementById('cartCount').textContent = sel.length;
    document.getElementById('cartTotal').textContent = (total / 100).toFixed(2).replace('.',',') + '\u20ac';
    document.getElementById('cartSavings').textContent = (savings / 100).toFixed(2).replace('.',',') + '\u20ac';
}

function openCartInSteam() {
    var sel = document.querySelectorAll('.card.selected');
    var ids = [], names = [];
    sel.forEach(function(c) {
        var m = c.href.match(/\/app\/(\d+)/);
        if (m) { ids.push(m[1]); names.push(c.querySelector('.name').textContent); }
    });
    if (ids.length === 0) return;
    var html = '<html><head><title>Steam - Panier SWSC</title><style>body{background:#1b2838;color:#c7d5e0;font-family:Arial,sans-serif;padding:30px}h1{color:#66c0f4;margin-bottom:20px}a{display:block;color:#a4d007;font-size:1.1rem;margin:8px 0;text-decoration:none}a:hover{color:#fff}</style></head><body>';
    html += '<h1>\ud83d\uded2 ' + ids.length + ' jeu(x) s\u00e9lectionn\u00e9(s)</h1>';
    html += '<p style="color:#8f98a0;margin-bottom:20px">Cliquez sur chaque jeu pour l\'ajouter \u00e0 votre panier Steam :</p>';
    for (var i = 0; i < ids.length; i++) {
        html += '<a href="https://store.steampowered.com/app/' + ids[i] + '/" target="_blank">\u27a1 ' + names[i] + '</a>';
    }
    html += '</body></html>';
    var w = window.open('', '_blank');
    if (w) { w.document.write(html); w.document.close(); }
}
function toggleSidebar() {
    var sb = document.getElementById('sidebar');
    var ov = document.getElementById('sidebarOverlay');
    sb.classList.toggle('open');
    ov.classList.toggle('visible');
}
// Close sidebar when clicking a filter on mobile
document.querySelectorAll('.sidebar-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
        if (window.innerWidth <= 900) {
            document.getElementById('sidebar').classList.remove('open');
            document.getElementById('sidebarOverlay').classList.remove('visible');
        }
    });
});
function showHelp() {
    document.getElementById('helpOverlay').classList.add('visible');
    document.getElementById('gearWrap').classList.remove('open');
}
function clearCart() {
    document.querySelector('.main').style.paddingBottom = '';
    document.querySelectorAll('.card.selected').forEach(function(c) {
        c.classList.remove('selected');
        c.querySelector('.card-select').classList.remove('checked');
    });
    updateCart();
}

// ── Tri ──
document.querySelectorAll('.sort-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sort-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const grid = document.getElementById('grid');
        const cards = Array.from(grid.querySelectorAll('.card'));
        const mode = btn.dataset.sort;
        cards.sort((a, b) => {
            switch(mode) {
                case 'alpha': return a.dataset.name.localeCompare(b.dataset.name, 'fr', {sensitivity:'base'});
                case 'alpha_desc': return b.dataset.name.localeCompare(a.dataset.name, 'fr', {sensitivity:'base'});
                case 'price_asc': return Number(a.dataset.sale) - Number(b.dataset.sale);
                case 'price_desc': return Number(b.dataset.sale) - Number(a.dataset.sale);
                case 'discount': return Number(b.dataset.disc) - Number(a.dataset.disc);
                case 'metacritic': return Number(b.dataset.mc || 0) - Number(a.dataset.mc || 0);
            }
        });
        cards.forEach((c, i) => {
            c.style.animation = 'none'; c.offsetHeight; c.style.animation = '';
            c.style.animationDelay = Math.min(i * 20, 500) + 'ms';
            grid.appendChild(c);
        });
    });
});

// ── Filtres combinés (recherche + genre) ──
let activeGenre = 'all';
let activeCat = 'all';

function applyFilters() {
    const q = document.getElementById('search').value.toLowerCase();
    const pMax = parseInt(document.getElementById('priceMax').value) * 100;
    document.getElementById('priceLabel').textContent = document.getElementById('priceMax').value + '\u20ac';
    var now72 = Date.now() + 259200000;
    let visible = 0;
    document.querySelectorAll('.card').forEach(c => {
        const name = c.querySelector('.name').textContent.toLowerCase();
        const genres = (c.dataset.genres || '').toLowerCase();
        const cats = (c.dataset.cats || '').toLowerCase();
        const badge = c.dataset.badge || '';
        const price = parseInt(c.dataset.sale) || 0;
        const endTs = parseInt(c.dataset.endts || '0') * 1000;
        const matchSearch = name.includes(q);
        const matchGenre = activeGenre === 'all' || genres.split(',').some(g => g.trim().toLowerCase() === activeGenre.toLowerCase());
        const matchCat = activeCat === 'all' || cats.split(',').some(ct => ct.trim().toLowerCase() === activeCat.toLowerCase());
        const matchNew = !showNewOnly || badge === 'new';
        const matchExpiring = !showExpiring || (endTs > 0 && endTs <= now72 && endTs > Date.now());
        const matchPrice = price <= pMax;
        const show = matchSearch && matchGenre && matchCat && matchNew && matchExpiring && matchPrice;
        c.style.display = show ? '' : 'none';
        if (show) visible++;
    });
    document.getElementById('count').textContent = visible + ' jeu' + (visible > 1 ? 'x' : '') + ' en promo';
}

document.getElementById('priceMax').addEventListener('input', applyFilters);

document.getElementById('search').addEventListener('input', function() {
    var v = this.value.trim();
    if (v === 'swsc:endofsales-on') {
        this.value = '';
        document.cookie = 'swsc_endofsales=on;path=/;max-age=31536000';
        fetch('run.php?endofsales=on').then(function() { window.location.href = 'run.php'; });
        return;
    }
    if (v === 'swsc:endofsales-off') {
        this.value = '';
        document.cookie = 'swsc_endofsales=;path=/;max-age=0';
        fetch('run.php?endofsales=off').then(function() { location.reload(); });
        return;
    }
    applyFilters();
});

document.querySelectorAll('.sidebar-btn[data-genre]').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sidebar-btn[data-genre]').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeGenre = btn.dataset.genre;
        applyFilters();
    });
});

document.querySelectorAll('.sidebar-btn[data-cat]').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.sidebar-btn[data-cat]').forEach(b => { b.classList.remove('active'); b.classList.remove('cat-active'); });
        btn.classList.add('active');
        activeCat = btn.dataset.cat;
        btn.classList.add('cat-active');
        applyFilters();
    });
});

// ── Vider le cache ──
function clearCache() {
    if (confirm('⚠️ Vider le cache ?\n\nLe prochain scan sera plus long car toutes les informations des jeux devront être récupérées à nouveau depuis Steam.\n\nContinuer ?')) {
        fetch('run.php?clear-cache=1').then(function() {
            var item = document.querySelector('.gear-danger');
            var old = item.innerHTML;
            item.innerHTML = '<span class="g-ico">✅</span> Cache vidé !';
            setTimeout(function() { item.innerHTML = old; }, 3000);
        });
    }
}

// ── Filtre Nouveautés ──
let showNewOnly = false;
let showExpiring = false;
function toggleNewOnly() {
    showNewOnly = !showNewOnly;
    const btn = document.getElementById('newOnlyBtn');
    if (showNewOnly) { btn.classList.add('active'); } else { btn.classList.remove('active'); }
    applyFilters();
}
function toggleExpiring() {
    showExpiring = !showExpiring;
    const btn = document.getElementById('expiringBtn');
    if (showExpiring) { btn.classList.add('active'); } else { btn.classList.remove('active'); }
    applyFilters();
}

// ── Switch de thème via roue crantée ──

// ── Inject icons ──
var GENRE_ICONS = {'Action':'&#9876;&#65039;','Adventure':'&#128506;&#65039;','Casual':'&#129513;','Early Access':'&#129514;','Free To Play':'&#127873;','Free to Play':'&#127873;','Indie':'&#128377;&#65039;','Massively Multiplayer':'&#127760;','Racing':'&#127950;&#65039;','RPG':'&#127922;','Simulation':'&#127959;&#65039;','Sports':'&#9917;','Strategy':'&#9823;&#65039;','Animation &amp; Modeling':'&#127902;&#65039;','Audio Production':'&#128266;','Design &amp; Illustration':'&#127912;','Education':'&#128218;','Game Development':'&#127916;','Photo Editing':'&#128248;','Utilities':'&#128295;&#65039;','Video Production':'&#127909;','Web Publishing':'&#127760;'};
var CAT_ICONS = {'Single-player':'&#128100;','Single player':'&#128100;','Un joueur':'&#128100;','Multi-player':'&#128101;','Multi player':'&#128101;','Multijoueur':'&#128101;','Co-op':'&#129309;','Online Co-op':'&#129309;','Online Co-Op':'&#129309;','Coop':'&#129309;','LAN Co-op':'&#128268;','LAN Co-Op':'&#128268;','PvP':'&#9889;','Online PvP':'&#9889;','LAN PvP':'&#9876;&#65039;','MMO':'&#127760;','Cross-Platform Multiplayer':'&#128421;&#65039;','Multi cross-platform':'&#128421;&#65039;','Shared/Split Screen':'&#128250;','Shared/Split Screen Co-op':'&#128250;','Shared/Split Screen PvP':'&#128250;'};
document.querySelectorAll('.sidebar-btn[data-genre]').forEach(function(b) {
    var g = b.dataset.genre; if (g !== 'all' && GENRE_ICONS[g]) {
        var sp = b.querySelector('span'); if (sp) sp.innerHTML = GENRE_ICONS[g] + ' ' + sp.textContent;
    }
});
document.querySelectorAll('.sidebar-btn[data-cat]').forEach(function(b) {
    var ct = b.dataset.cat; if (ct !== 'all' && CAT_ICONS[ct]) {
        var sp = b.querySelector('span'); if (sp) sp.innerHTML = CAT_ICONS[ct] + ' ' + sp.textContent;
    }
});

function setTheme(theme) {
    document.body.className = (theme === 'classic') ? 'classic' : (theme === 'light') ? 'light' : '';
    document.cookie = 'theme=' + theme + ';path=/;max-age=31536000';
    document.querySelectorAll('.gear-item[id^="th"]').forEach(function(el) { el.classList.remove('active-theme'); });
    var id = theme === 'classic' ? 'thClassic' : theme === 'light' ? 'thLight' : 'thModern';
    document.getElementById(id).classList.add('active-theme');
}

// Restaurer le thème sauvegardé
(function() {
    const m = document.cookie.match(/theme=(\w+)/);
    if (m) {
        if (m[1] === 'classic') { document.body.classList.add('classic'); }
        else if (m[1] === 'light') { document.body.classList.add('light'); }
    }
    var active = (m && m[1] === 'classic') ? 'thClassic' : (m && m[1] === 'light') ? 'thLight' : 'thModern';
    document.querySelectorAll('.gear-item[id^="th"]').forEach(function(el) { el.classList.remove('active-theme'); });
    document.getElementById(active).classList.add('active-theme');
})();

// Fermer le gear menu quand on clique ailleurs
document.addEventListener('click', function(e) {
    var gw = document.getElementById('gearWrap');
    if (gw && !gw.contains(e.target)) gw.classList.remove('open');
});

// ── Prochain scan auto ──
(function() {
    const schedules = (typeof SCAN_SCHEDULE !== 'undefined' && SCAN_SCHEDULE.length > 0) ? SCAN_SCHEDULE : [19];
    const now = new Date();
    let next = null;
    for (const h of schedules) {
        const candidate = new Date(now);
        candidate.setHours(h, 5, 0, 0);
        if (candidate > now) { next = candidate; break; }
    }
    if (!next) {
        next = new Date(now);
        next.setDate(next.getDate() + 1);
        next.setHours(schedules[0], 5, 0, 0);
    }
    function update() {
        const diff = Math.max(0, Math.floor((next - new Date()) / 1000));
        const h = Math.floor(diff / 3600);
        const m = Math.floor((diff % 3600) / 60);
        const hh = String(next.getHours()).padStart(2, '0');
        const mm = String(next.getMinutes()).padStart(2, '0');
        var sc = document.getElementById('nextScanCard');
        if (sc) sc.textContent = hh + ':' + mm + ' (' + h + 'h' + String(m).padStart(2,'0') + ')';
    }
    update();
    setInterval(update, 60000);
})();

// ── Dates de fin de promo (si activé) ──
if (document.cookie.includes('swsc_endofsales=on')) {
    fetch('sale_dates.json').then(function(r) { return r.json(); }).then(function(dates) {
        var countdownEls = [];
        var hasAny = false;
        document.querySelectorAll('.card').forEach(function(card) {
            var m = card.href.match(/\/app\/(\d+)/);
            if (m && dates[m[1]]) {
                card.dataset.endts = dates[m[1]];
                var el = document.createElement('span');
                el.className = 'end-date';
                el.dataset.endTs = dates[m[1]];
                card.querySelector('.info').appendChild(el);
                countdownEls.push(el);
                hasAny = true;
            }
        });
        if (hasAny) { document.getElementById('expiringBtn').style.display = ''; }
        function updateCountdowns() {
            var now = Date.now();
            countdownEls.forEach(function(el) {
                var endMs = parseInt(el.dataset.endTs) * 1000;
                var diff = endMs - now;
                if (diff <= 0) {
                    el.textContent = '\u23f3 Termin\u00e9e !';
                    el.className = 'end-date end-date-urgent';
                    return;
                }
                var d = Math.floor(diff / 86400000);
                var h = Math.floor((diff % 86400000) / 3600000);
                var m = Math.floor((diff % 3600000) / 60000);
                var s = Math.floor((diff % 60000) / 1000);
                var txt = '\u23f3 ';
                if (d > 0) txt += d + 'j ' + h + 'h ' + m + 'min';
                else if (h > 0) txt += h + 'h ' + ('0'+m).slice(-2) + 'min ' + ('0'+s).slice(-2) + 's';
                else txt += m + 'min ' + ('0'+s).slice(-2) + 's';
                el.textContent = txt;
                el.className = (diff <= 259200000) ? 'end-date end-date-urgent' : 'end-date';
            });
        }
        updateCountdowns();
        setInterval(updateCountdowns, 1000);
    }).catch(function() {});
}
</script>

</div>
<div class="help-overlay" id="helpOverlay" onclick="if(event.target===this)this.classList.remove('visible')">
    <div class="help-box">
        <button class="help-close" onclick="document.getElementById('helpOverlay').classList.remove('visible')">&times;</button>
        <h2>&#10067; Aide &#8212; Steam Wishlist Sales Checker</h2>
        <h3>&#128270; Recherche</h3>
        <p>Tapez un nom de jeu pour filtrer en temps r&#233;el.</p>
        <h3>&#9881; Roue crant&#233;e</h3>
        <p>Actualiser le scan, vider le cache, changer de th&#232;me (Modern / Classic Steam / Light), acc&#233;der au calendrier des soldes Steam.</p>
        <h3>&#128203; Filtres</h3>
        <p>Cliquez sur un genre ou mode de jeu dans la barre lat&#233;rale pour filtrer. Tous les filtres sont cumulatifs avec la recherche et le slider prix.</p>
        <h3>&#127381; Nouveaut&#233;s</h3>
        <p>Affiche uniquement les jeux apparus en promo depuis le dernier scan.</p>
        <h3>&#9203; Expire bient&#244;t</h3>
        <p>Visible si le scraping des dates est activ&#233;. Affiche les promos expirant sous 72h.</p>
        <h3>&#9203; Dates de fin de promo</h3>
        <p>Tapez <code>swsc:endofsales-on</code> dans la recherche pour activer le scraping des dates de fin. <code>swsc:endofsales-off</code> pour d&#233;sactiver. Non activ&#233; par d&#233;faut car Steam peut casser cette possibilit&#233; &#224; tout moment. Le scraping ajoute ~1s par jeu.</p>
        <h3>&#128722; Panier</h3>
        <p>Cliquez sur le &#10003; en haut &#224; gauche d'une carte pour s&#233;lectionner un jeu. Une barre appara&#238;t en bas avec le total, l'&#233;conomie et un bouton pour ouvrir les pages Steam. D&#233;sactivez votre bloqueur de pubs pour ouvrir plusieurs onglets.</p>
        <h3>&#127918; Version</h3>
        <p>SWSC v2.0 &#8212; Code g&#233;n&#233;r&#233; avec Claude (Anthropic)</p>
    </div>
</div>
<div class="cart-bar" id="cartBar">
    <div class="cart-info">
        <span class="cart-stat">&#128722; <strong id="cartCount">0</strong> jeu(x)</span>
        <span class="cart-stat">Total : <strong id="cartTotal">0,00&#8364;</strong></span>
        <span class="cart-stat">&#201;conomie : <span class="savings" id="cartSavings">0,00&#8364;</span></span>
    </div>
    <div class="cart-actions">
        <button class="cart-btn cart-btn-steam" onclick="openCartInSteam()" title="D&#233;sactivez votre bloqueur de pubs si les pages ne s'ouvrent pas">&#127918; Ouvrir sur Steam (Web)</button>
        <button class="cart-btn cart-btn-clear" onclick="clearCart()">&#10005; Vider</button>
    </div>
</div>
</body>
</html>
HTMLSCRIPT

chmod 644 "$OUTPUT_FILE"
chown www-data:www-data "$OUTPUT_FILE"

ELAPSED=$(( $(date +%s) - START_TIME ))
ok "Page générée : $OUTPUT_FILE"
ok "Durée totale : ${ELAPSED}s"
log "Terminé !"
