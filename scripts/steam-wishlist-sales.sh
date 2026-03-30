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
SCAN_HOURS="1,7,13,19"

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
    TOTAL=$(echo "$APPIDS" | wc -w)
    COUNT=0
    FOUND=0
    FIRST=true

    for APPID in $APPIDS; do
        COUNT=$((COUNT + 1))
        printf "\r  [%d/%d] App %s..." "$COUNT" "$TOTAL" "$APPID" >&2

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
    ok "Dates de fin récupérées : ${FOUND}/${TOTAL} jeux"
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
CHEAPEST_FMT=$(echo "scale=2; ${CHEAPEST:-0} / 100" | bc 2>/dev/null | sed 's/\./,/' || echo "0,00")
MAX_PRICE=$(jq '[.[].sale_price] | if length > 0 then max else 0 end' "$SALES_FILE" 2>/dev/null || echo "0")
MAX_PRICE_EUR=$(echo "scale=0; (${MAX_PRICE:-0} + 99) / 100" | bc 2>/dev/null || echo "0")
NOW=$(date '+%d/%m/%Y à %H:%M')

# Extraire la liste unique des genres pour les boutons filtres
ALL_GENRES=$(jq -r '[.[].genres[]?] | unique | .[]' "$SALES_FILE" 2>/dev/null | grep -v '^$' | sort)

GENRE_BUTTONS=""
while IFS= read -r genre; do
    if [ -n "$genre" ]; then
        GENRE_BUTTONS="${GENRE_BUTTONS}<button class=\"genre-btn\" data-genre=\"${genre}\">${genre}</button>"
    fi
done <<< "$ALL_GENRES"

# Extraire les catégories de jeu (filtrer les catégories pertinentes)
ALL_CATS=$(jq -r '[.[].cats[]?] | unique | .[]' "$SALES_FILE" 2>/dev/null | grep -v '^$' | grep -iE "single.player|multi.player|co.op|pvp|mmo|cross.platform|shared.split|lan|un joueur|multijoueur|coop|coopératif|joueur contre joueur|JcJ|écran partagé" | sort)

CAT_BUTTONS=""
while IFS= read -r cat; do
    if [ -n "$cat" ]; then
        CAT_BUTTONS="${CAT_BUTTONS}<button class=\"cat-btn\" data-cat=\"${cat}\">${cat}</button>"
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
  + "<span class=\"old\">\(.normal_price / 100 | tostring | gsub("\\."; ",") | if test(",") then . else . + ",00" end)\u20ac</span>"
  + "<span class=\"new\">\(.sale_price / 100 | tostring | gsub("\\."; ",") | if test(",") then . else . + ",00" end)\u20ac</span>"
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
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Steam Wishlist — Promotions</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Exo+2:wght@400;600;800&family=Outfit:wght@300;400;600&display=swap" rel="stylesheet">
<style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

    /* ════════════════════════════════════════════════════
       THÈME MODERN (défaut)
       ════════════════════════════════════════════════════ */
    body {
        background: #0a0e14;
        color: #c6d4df;
        font-family: 'Outfit', sans-serif;
        min-height: 100vh;
        position: relative;
        overflow-x: hidden;
    }
    body::before {
        content: '';
        position: fixed;
        top: 0; left: 0; right: 0; bottom: 0;
        background:
            radial-gradient(ellipse 80% 50% at 20% 10%, rgba(102, 192, 244, 0.04) 0%, transparent 60%),
            radial-gradient(ellipse 60% 40% at 80% 90%, rgba(164, 208, 7, 0.03) 0%, transparent 60%);
        pointer-events: none;
        z-index: 0;
    }
    .container { max-width: 1500px; margin: 0 auto; padding: 28px 24px; position: relative; z-index: 1; }

    .header { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; padding-bottom: 18px; border-bottom: 1px solid rgba(102, 192, 244, 0.1); }
    .header h1 { font-family: 'Exo 2', sans-serif; font-size: 1.8rem; font-weight: 800; color: #fff; letter-spacing: -0.02em; display: flex; align-items: center; gap: 12px; }
    .header h1 .icon { font-size: 1.5rem; filter: drop-shadow(0 0 8px rgba(102, 192, 244, 0.5)); }
    .header-right { display: flex; align-items: center; gap: 14px; font-size: 0.82rem; color: #5a6a78; flex-wrap: wrap; }
    .header-right .count { color: #66c0f4; font-weight: 600; font-size: 0.95rem; }

    .gear-wrap { position: relative; display: inline-block; }
    .gear-btn { display: flex; align-items: center; justify-content: center; width: 36px; height: 36px; background: rgba(102, 192, 244, 0.08); border: 1px solid rgba(102, 192, 244, 0.2); border-radius: 10px; color: #8f98a0; font-size: 1.1rem; cursor: pointer; transition: all 0.25s; }
    .gear-btn:hover { border-color: #66c0f4; color: #fff; transform: rotate(45deg); }
    .gear-dropdown { display: none; position: absolute; top: 42px; right: 0; background: #0c1018; border: 1px solid rgba(102, 192, 244, 0.2); border-radius: 10px; padding: 6px 0; min-width: 220px; box-shadow: 0 10px 35px rgba(0,0,0,0.5); z-index: 100; }
    .gear-wrap.open .gear-dropdown { display: block; }
    .gear-item { display: flex; align-items: center; gap: 10px; padding: 8px 16px; color: #8f98a0; font-size: 0.78rem; cursor: pointer; transition: all 0.15s; border: none; background: none; width: 100%; font-family: 'Outfit', sans-serif; text-decoration: none; text-align: left; }
    .gear-item:hover { background: rgba(255,255,255,0.04); color: #fff; }
    .gear-item .g-ico { width: 18px; text-align: center; }
    .gear-item.active-theme { color: #66c0f4; font-weight: 600; }
    .gear-item.active-theme::after { content: '\2713'; margin-left: auto; font-size: 0.7rem; }
    .gear-sep { height: 1px; background: rgba(102, 192, 244, 0.08); margin: 4px 12px; }
    .gear-danger { color: #e05a4f; }
    .gear-danger:hover { background: rgba(224, 90, 79, 0.08); }

    .stats { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 18px; padding: 14px 18px; background: rgba(255,255,255,0.02); border: 1px solid rgba(102, 192, 244, 0.08); border-radius: 10px; font-size: 0.82rem; }
    .stats span { color: #8f98a0; }
    .stats .val { color: #66c0f4; font-weight: 600; }
    .stats .val-green { color: #a4d007; font-weight: 600; }

    .controls { display: flex; gap: 12px; margin-bottom: 14px; flex-wrap: wrap; align-items: center; }
    .search-box { flex: 1; min-width: 200px; max-width: 380px; }
    .search-box input { width: 100%; padding: 9px 18px; border-radius: 24px; border: 1px solid rgba(102, 192, 244, 0.18); background: rgba(0,0,0,0.35); color: #c6d4df; font-size: 0.88rem; font-family: 'Outfit', sans-serif; outline: none; transition: border-color 0.25s, box-shadow 0.25s; }
    .search-box input:focus { border-color: #66c0f4; box-shadow: 0 0 12px rgba(102, 192, 244, 0.15); }
    .search-box input::placeholder { color: #3e4f5e; }

    .toolbar { display: flex; gap: 6px; flex-wrap: wrap; }
    .toolbar button { background: rgba(102, 192, 244, 0.06); border: 1px solid rgba(102, 192, 244, 0.14); color: #8f98a0; padding: 7px 18px; border-radius: 24px; font-size: 0.82rem; cursor: pointer; transition: all 0.2s; font-family: 'Outfit', sans-serif; }
    .toolbar button:hover { background: rgba(102, 192, 244, 0.14); color: #fff; }
    .toolbar button.active { background: linear-gradient(135deg, #66c0f4, #4a9fd4); color: #fff; border-color: transparent; font-weight: 600; box-shadow: 0 2px 12px rgba(102, 192, 244, 0.25); }

    .genre-filters { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 18px; }
    .genre-btn { background: rgba(164, 208, 7, 0.06); border: 1px solid rgba(164, 208, 7, 0.12); color: #6a7a58; padding: 5px 14px; border-radius: 20px; font-size: 0.75rem; cursor: pointer; transition: all 0.2s; font-family: 'Outfit', sans-serif; }
    .genre-btn:hover { background: rgba(164, 208, 7, 0.14); color: #a4d007; }
    .genre-btn.active { background: linear-gradient(135deg, #a4d007, #7aa800); color: #fff; border-color: transparent; font-weight: 600; }
    .new-only-btn.active { background: linear-gradient(135deg, #66c0f4, #4a9fd4); }
    .expiring-btn.active { background: linear-gradient(135deg, #e05a4f, #c0392b); }

    .cat-filters { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 14px; }
    .cat-btn { background: rgba(164, 208, 7, 0.06); border: 1px solid rgba(164, 208, 7, 0.14); color: #8f98a0; padding: 5px 14px; border-radius: 18px; font-size: 0.72rem; cursor: pointer; transition: all 0.2s; font-family: 'Outfit', sans-serif; }
    .cat-btn:hover { background: rgba(164, 208, 7, 0.14); color: #fff; }
    .cat-btn.active { background: linear-gradient(135deg, #a4d007, #7aa800); color: #fff; border-color: transparent; font-weight: 600; }

    .cat-filters { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 14px; }
    .cat-btn { background: rgba(164, 208, 7, 0.06); border: 1px solid rgba(164, 208, 7, 0.14); color: #8f98a0; padding: 5px 12px; border-radius: 16px; font-size: 0.72rem; cursor: pointer; transition: all 0.2s; font-family: 'Outfit', sans-serif; }
    .cat-btn:hover { background: rgba(164, 208, 7, 0.14); color: #fff; }
    .cat-btn.active { background: linear-gradient(135deg, #a4d007, #7aa800); color: #fff; border-color: transparent; font-weight: 600; }

    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 14px; }

    .card { background: linear-gradient(160deg, #141c27 0%, #0f1923 100%); border-radius: 10px; overflow: hidden; text-decoration: none; color: inherit; transition: transform 0.25s ease, box-shadow 0.25s ease; display: flex; flex-direction: column; border: 1px solid rgba(102, 192, 244, 0.05); opacity: 0; animation: fadeSlideUp 0.4s ease forwards; }
    .card:hover { transform: translateY(-5px) scale(1.01); box-shadow: 0 12px 35px rgba(0, 0, 0, 0.5), 0 0 20px rgba(102, 192, 244, 0.06); }

    .img-wrap { position: relative; aspect-ratio: 460 / 215; overflow: hidden; background: #080c12; }
    .img-wrap img { width: 100%; height: 100%; object-fit: cover; transition: transform 0.4s ease; }
    .card:hover .img-wrap img { transform: scale(1.07); }

    .badge { position: absolute; top: 0; right: 0; color: #fff; font-family: 'Exo 2', sans-serif; font-weight: 800; font-size: 0.92rem; padding: 5px 12px 5px 14px; border-radius: 0 0 0 10px; letter-spacing: -0.03em; text-shadow: 0 1px 3px rgba(0,0,0,0.3); }
    .badge-high { background: linear-gradient(135deg, #a4d007, #7aa800); }
    .badge-mid { background: linear-gradient(135deg, #f39c12, #d68910); }
    .badge-low { background: linear-gradient(135deg, #e05a4f, #c0392b); }

    .status-badge { position: absolute; top: 0; left: 0; color: #fff; font-family: 'Exo 2', sans-serif; font-weight: 700; font-size: 0.72rem; padding: 4px 10px 4px 8px; border-radius: 0 0 10px 0; text-shadow: 0 1px 2px rgba(0,0,0,0.4); z-index: 2; letter-spacing: 0.02em; }
    .new-badge { background: linear-gradient(135deg, #66c0f4, #4a9fd4); }
    .up-badge { background: linear-gradient(135deg, #e05a4f, #c0392b); }
    .down-badge { background: linear-gradient(135deg, #27ae60, #1e8449); }

    .info { padding: 12px 14px 14px; display: flex; flex-direction: column; gap: 5px; flex: 1; }
    .name { font-size: 0.92rem; font-weight: 600; color: #fff; line-height: 1.3; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
    .genres-row { display: flex; gap: 4px; flex-wrap: wrap; min-height: 18px; }
    .genre-tag { font-size: 0.62rem; color: #6a7a88; background: rgba(255,255,255,0.04); padding: 1px 7px; border-radius: 8px; white-space: nowrap; }
    .prices { display: flex; align-items: center; gap: 10px; margin-top: auto; }
    .old { font-size: 0.8rem; color: #6a7a88; text-decoration: line-through; }
    .new { font-family: 'Exo 2', sans-serif; font-size: 1.08rem; font-weight: 800; color: #a4d007; text-shadow: 0 0 10px rgba(164, 208, 7, 0.15); }

    .metacritic { display: inline-flex; align-items: center; justify-content: center; min-width: 28px; height: 22px; font-family: 'Exo 2', sans-serif; font-weight: 800; font-size: 0.68rem; border-radius: 4px; color: #fff; margin-left: auto; padding: 0 5px; }
    .mc-high { background: #66cc33; }
    .mc-mid { background: #ffcc33; color: #111; }
    .mc-low { background: #ff4444; }

    .price-filter { display: flex; align-items: center; gap: 8px; margin-left: 8px; padding-left: 8px; border-left: 1px solid rgba(102,192,244,0.12); }
    .price-filter label { font-size: 0.75rem; color: #8f98a0; font-family: 'Outfit', sans-serif; white-space: nowrap; }
    .price-filter input[type=range] { -webkit-appearance: none; appearance: none; width: 100px; height: 4px; background: rgba(102, 192, 244, 0.15); border-radius: 2px; outline: none; }
    .price-filter input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; appearance: none; width: 14px; height: 14px; border-radius: 50%; background: #66c0f4; cursor: pointer; border: 2px solid #0a0e14; }
    .price-filter input[type=range]::-moz-range-thumb { width: 14px; height: 14px; border-radius: 50%; background: #66c0f4; cursor: pointer; border: 2px solid #0a0e14; }
    .price-val { font-size: 0.78rem; color: #66c0f4; font-weight: 600; font-family: 'Exo 2', sans-serif; min-width: 40px; }

    .end-date { display: block; font-size: 0.68rem; color: #8f98a0; margin-top: 3px; font-family: 'Outfit', sans-serif; }
    .end-date-urgent { color: #e05a4f; font-weight: 600; }

    .empty { text-align: center; padding: 80px 20px; color: #3e4f5e; font-size: 1.1rem; }

    @keyframes fadeSlideUp { from { opacity: 0; transform: translateY(18px); } to { opacity: 1; transform: translateY(0); } }

    @media (max-width: 640px) {
        .container { padding: 14px 10px; }
        .header h1 { font-size: 1.3rem; }
        .grid { grid-template-columns: repeat(auto-fill, minmax(165px, 1fr)); gap: 8px; }
        .info { padding: 8px 10px 10px; }
        .name { font-size: 0.82rem; }
        .badge { font-size: 0.8rem; padding: 3px 9px 3px 11px; }
        .status-badge { font-size: 0.62rem; padding: 3px 7px 3px 5px; }
        .stats { gap: 12px; font-size: 0.75rem; }
    }

    /* ════════════════════════════════════════════════════
       THÈME CLASSIC STEAM (2004-2010)
       Vert olive, Tahoma, bordures biseautées
       ════════════════════════════════════════════════════ */
    body.classic {
        background: #3b4a36;
        color: #d2d2d2;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
    body.classic::before {
        background: linear-gradient(180deg, #4a5a42 0%, #3b4a36 40%, #2d3a28 100%);
    }

    body.classic .container { max-width: 1200px; padding: 12px 16px; }

    body.classic .header {
        background: linear-gradient(180deg, #5c7a49 0%, #4a6637 100%);
        border: 1px solid #6b8a56;
        border-bottom: 2px solid #2d3a28;
        border-radius: 0;
        padding: 8px 14px;
        margin-bottom: 10px;
    }
    body.classic .header h1 {
        font-family: Tahoma, Verdana, sans-serif;
        font-size: 1.15rem;
        font-weight: bold;
        color: #d2e8b0;
        letter-spacing: 0;
        text-shadow: 1px 1px 2px rgba(0,0,0,0.5);
    }
    body.classic .header h1 .icon { font-size: 1rem; filter: none; }
    body.classic .header-right { font-size: 0.72rem; color: #a0b890; }
    body.classic .header-right .count { color: #d2e8b0; font-size: 0.78rem; }

    body.classic .gear-btn { background: linear-gradient(180deg, #6b8a56 0%, #4a6637 100%); border: 1px solid #7a9a64; border-bottom: 1px solid #3a5228; border-radius: 3px; color: #d2e8b0; }
    body.classic .gear-btn:hover { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); color: #fff; transform: rotate(45deg); }
    body.classic .gear-dropdown { background: #1a2612; border: 1px solid #4a5a40; border-radius: 3px; }
    body.classic .gear-item { font-family: Tahoma, sans-serif; font-size: 0.72rem; color: #8a9a80; }
    body.classic .gear-item:hover { background: rgba(255,255,255,0.04); color: #d2e8b0; }
    body.classic .gear-item.active-theme { color: #a4d007; }
    body.classic .gear-sep { background: rgba(138,154,128,0.15); }
    body.classic .gear-danger { color: #b03a2e; }
    body.classic .gear-danger:hover { background: rgba(176,58,46,0.08); }

    body.classic .stats {
        background: linear-gradient(180deg, #4a5a42 0%, #3e4e38 100%);
        border: 1px solid #5a6a52;
        border-radius: 0;
        padding: 8px 12px;
        font-size: 0.72rem;
    }
    body.classic .stats span { color: #a0b890; }
    body.classic .stats .val { color: #d2e8b0; }
    body.classic .stats .val-green { color: #a4d007; }

    body.classic .search-box input {
        border-radius: 2px;
        border: 1px solid #5a6a52;
        background: #2d3a28;
        color: #d2d2d2;
        font-family: Tahoma, sans-serif;
        font-size: 0.78rem;
        padding: 5px 10px;
    }
    body.classic .search-box input:focus { border-color: #7a9a64; box-shadow: none; }
    body.classic .search-box input::placeholder { color: #6a7a62; }

    body.classic .toolbar button {
        background: linear-gradient(180deg, #5c7a49 0%, #4a6637 100%);
        border: 1px solid #6b8a56;
        border-bottom: 1px solid #3a5228;
        color: #a0b890;
        border-radius: 2px;
        padding: 4px 12px;
        font-family: Tahoma, sans-serif;
        font-size: 0.72rem;
    }
    body.classic .toolbar button:hover { color: #d2e8b0; }
    body.classic .toolbar button.active {
        background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%);
        color: #fff;
        border-color: #8aaa74;
        box-shadow: inset 0 1px 0 rgba(255,255,255,0.1);
    }

    body.classic .genre-btn {
        background: linear-gradient(180deg, #4a5a42 0%, #3e4e38 100%);
        border: 1px solid #5a6a52;
        color: #8a9a80;
        border-radius: 2px;
        padding: 3px 10px;
        font-family: Tahoma, sans-serif;
        font-size: 0.68rem;
    }
    body.classic .genre-btn:hover { color: #d2e8b0; }
    body.classic .genre-btn.active {
        background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%);
        color: #fff;
        border-color: #8aaa74;
    }
    body.classic .new-only-btn.active { background: linear-gradient(180deg, #4a8ab5 0%, #3a6a95 100%); border-color: #5a9ac5; }
    body.classic .expiring-btn.active { background: linear-gradient(180deg, #b03a2e 0%, #8a2a1e 100%); border-color: #c04a3e; }

    body.classic .cat-filters { gap: 4px; margin-bottom: 10px; }
    body.classic .cat-btn { background: linear-gradient(180deg, #3a4a30 0%, #2a3a20 100%); border: 1px solid #4a5a40; color: #8a9a80; border-radius: 3px; font-family: Tahoma, sans-serif; font-size: 0.68rem; padding: 3px 10px; }
    body.classic .cat-btn:hover { color: #d2e8b0; }
    body.classic .cat-btn.active { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); color: #fff; border-color: #8aaa74; }

    body.classic .cat-filters { margin-bottom: 10px; }
    body.classic .cat-btn { background: linear-gradient(180deg, #4a5a3e 0%, #3a4a2e 100%); border: 1px solid #5a6a4e; border-bottom: 1px solid #2a3a1e; color: #8a9a80; border-radius: 3px; padding: 3px 10px; font-family: Tahoma, sans-serif; font-size: 0.68rem; }
    body.classic .cat-btn:hover { color: #d2e8b0; }
    body.classic .cat-btn.active { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); color: #fff; border-color: #8aaa74; }

    body.classic .grid { gap: 8px; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); }

    body.classic .card {
        background: linear-gradient(180deg, #4a5a42 0%, #3e4e38 100%);
        border: 1px solid #5a6a52;
        border-radius: 0;
        animation: none;
        opacity: 1;
    }
    body.classic .card:hover {
        transform: none;
        box-shadow: 0 0 0 1px #8aaa74;
        border-color: #8aaa74;
    }
    body.classic .card:hover .img-wrap img { transform: none; }

    body.classic .img-wrap { background: #2d3a28; }

    body.classic .badge {
        border-radius: 0;
        font-family: Tahoma, sans-serif;
        font-size: 0.82rem;
        font-weight: bold;
        padding: 2px 8px;
    }
    body.classic .badge-high { background: #4a7a20; }
    body.classic .badge-mid { background: #b8860b; }
    body.classic .badge-low { background: #b03a2e; }

    body.classic .status-badge { border-radius: 0; font-family: Tahoma, sans-serif; font-size: 0.68rem; font-weight: bold; padding: 2px 6px; }
    body.classic .new-badge { background: #4a8ab5; }
    body.classic .up-badge { background: #b03a2e; }
    body.classic .down-badge { background: #1e8449; }

    body.classic .info { padding: 8px 10px 10px; gap: 4px; }
    body.classic .name { font-size: 0.8rem; font-weight: bold; font-family: Tahoma, sans-serif; color: #d2e8b0; }
    body.classic .genre-tag { font-size: 0.58rem; color: #8a9a80; background: rgba(0,0,0,0.2); border-radius: 2px; padding: 1px 5px; }
    body.classic .old { font-size: 0.72rem; color: #8a9a80; }
    body.classic .new { font-family: Tahoma, sans-serif; font-size: 0.88rem; font-weight: bold; color: #a4d007; text-shadow: none; }

    body.classic .metacritic { border-radius: 2px; font-family: Tahoma, sans-serif; font-size: 0.62rem; }

    body.classic .price-filter { border-left-color: rgba(138,154,128,0.2); }
    body.classic .price-filter label { font-family: Tahoma, sans-serif; font-size: 0.68rem; color: #8a9a80; }
    body.classic .price-filter input[type=range] { background: rgba(138,154,128,0.2); }
    body.classic .price-filter input[type=range]::-webkit-slider-thumb { background: #7a9a64; border-color: #1e2a16; }
    body.classic .price-filter input[type=range]::-moz-range-thumb { background: #7a9a64; border-color: #1e2a16; }
    body.classic .price-val { color: #a4d007; font-family: Tahoma, sans-serif; }

    body.classic .end-date { font-family: Tahoma, sans-serif; font-size: 0.64rem; color: #8a9a80; }
    body.classic .end-date-urgent { color: #c0392b; }

    /* ════════════════════════════════════════════════════
       THÈME LIGHT
       ════════════════════════════════════════════════════ */
    body.light { background: #f0f2f5; color: #37474f; }
    body.light::before { background: radial-gradient(ellipse 60% 40% at 20% 10%, rgba(26,115,232,0.03) 0%, transparent 70%); }
    body.light .container { max-width: 1300px; }
    body.light .header { border-bottom-color: rgba(0,0,0,0.06); }
    body.light .header h1 { color: #212121; }
    body.light .header-right .count { color: #1a73e8; }
    body.light .header-right span { color: #78909c; }

    body.light .gear-btn { background: #fff; border: 1px solid rgba(0,0,0,0.1); color: #78909c; border-radius: 10px; }
    body.light .gear-btn:hover { border-color: rgba(0,0,0,0.2); color: #37474f; }
    body.light .gear-dropdown { background: #fff; border: 1px solid rgba(0,0,0,0.12); box-shadow: 0 8px 30px rgba(0,0,0,0.12); border-radius: 10px; }
    body.light .gear-item { color: #78909c; }
    body.light .gear-item:hover { background: rgba(0,0,0,0.03); color: #37474f; }
    body.light .gear-item.active-theme { color: #1a73e8; }
    body.light .gear-sep { background: rgba(0,0,0,0.06); }
    body.light .gear-danger { color: #c62828; }
    body.light .gear-danger:hover { background: rgba(198,40,40,0.04); }

    body.light .stats { background: #fff; border: 1px solid rgba(0,0,0,0.06); border-radius: 10px; box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
    body.light .stats span { color: #78909c; }
    body.light .stats .val { color: #1a73e8; }
    body.light .stats .val-green { color: #2e7d32; }

    body.light .search-box input { background: #fff; border: 1px solid rgba(0,0,0,0.1); color: #37474f; border-radius: 24px; }
    body.light .search-box input:focus { border-color: #1a73e8; box-shadow: 0 0 8px rgba(26,115,232,0.12); }
    body.light .search-box input::placeholder { color: #b0bec5; }

    body.light .toolbar button { background: #fff; border: 1px solid rgba(0,0,0,0.1); color: #78909c; }
    body.light .toolbar button:hover { border-color: rgba(0,0,0,0.2); color: #37474f; }
    body.light .toolbar button.active { background: #1a73e8; color: #fff; border-color: transparent; }

    body.light .genre-btn { background: #fff; border: 1px solid rgba(0,0,0,0.08); color: #78909c; }
    body.light .genre-btn:hover { background: rgba(46,125,50,0.06); color: #2e7d32; }
    body.light .genre-btn.active { background: #2e7d32; color: #fff; border-color: transparent; }
    body.light .new-only-btn.active { background: #1a73e8; }
    body.light .expiring-btn.active { background: #c62828; }

    body.light .cat-btn { background: #fff; border: 1px solid rgba(0,0,0,0.08); color: #78909c; }
    body.light .cat-btn:hover { background: rgba(46,125,50,0.06); color: #2e7d32; }
    body.light .cat-btn.active { background: #2e7d32; color: #fff; border-color: transparent; }

    body.light .price-filter { border-left-color: rgba(0,0,0,0.08); }
    body.light .price-filter label { color: #78909c; }
    body.light .price-filter input[type=range] { background: rgba(26,115,232,0.1); }
    body.light .price-filter input[type=range]::-webkit-slider-thumb { background: #1a73e8; border-color: #f0f2f5; }
    body.light .price-filter input[type=range]::-moz-range-thumb { background: #1a73e8; border-color: #f0f2f5; }
    body.light .price-val { color: #1a73e8; }

    body.light .card { background: #fff; border: 1px solid rgba(0,0,0,0.06); border-radius: 10px; box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
    body.light .card:hover { border-color: rgba(0,0,0,0.12); box-shadow: 0 6px 20px rgba(0,0,0,0.08); }
    body.light .img-wrap { background: #e8eaed; }
    body.light .name { color: #212121; }
    body.light .genre-tag { background: rgba(0,0,0,0.04); color: #78909c; }
    body.light .old { color: #b0bec5; }
    body.light .new { color: #2e7d32; text-shadow: none; }

    body.light .badge-high { background: #2e7d32; color: #fff; }
    body.light .badge-mid { background: #ef6c00; color: #fff; }
    body.light .badge-low { background: #c62828; }
    body.light .new-badge { background: #1a73e8; }
    body.light .up-badge { background: #c62828; }
    body.light .down-badge { background: #2e7d32; }
    body.light .status-badge { text-shadow: none; }

    body.light .metacritic.mc-high { background: #2e7d32; }
    body.light .metacritic.mc-mid { background: #f9a825; color: #333; }
    body.light .metacritic.mc-low { background: #c62828; }

    body.light .end-date { color: #78909c; }
    body.light .end-date-urgent { color: #c62828; }

    body.light .empty { color: #b0bec5; }
</style>
</head>
<body>
<div class="container">

<div class="header">
    <h1><span class="icon">🎮</span> Steam Wishlist — Promos</h1>
    <div class="header-right">
HTMLHEAD

# ── Partie dynamique (variables Bash interpolées) ──
cat >> "$OUTPUT_FILE" << HTMLMETA
        <span class="count" id="count">${SALE_COUNT} jeu$([ "$SALE_COUNT" -gt 1 ] && echo "x") en promo</span>
        <span>Mis à jour le ${NOW} (${ELAPSED}s)</span>
        <div class="gear-wrap" id="gearWrap">
            <button class="gear-btn" onclick="this.parentElement.classList.toggle('open')">&#9881;</button>
            <div class="gear-dropdown">
                <a class="gear-item" href="run.php"><span class="g-ico">&#8635;</span> Actualiser le scan</a>
                <button class="gear-item gear-danger" onclick="clearCache()"><span class="g-ico">&#128465;</span> Vider le cache</button>
                <div class="gear-sep"></div>
                <button class="gear-item" id="thModern" onclick="setTheme('modern')"><span class="g-ico">&#10024;</span> Thème Modern</button>
                <button class="gear-item" id="thClassic" onclick="setTheme('classic')"><span class="g-ico">&#128421;</span> Thème Classic Steam</button>
                <button class="gear-item" id="thLight" onclick="setTheme('light')"><span class="g-ico">&#9728;</span> Thème Light</button>
                <div class="gear-sep"></div>
                <a class="gear-item" href="https://steamdb.info/sales/history/" target="_blank" rel="noopener"><span class="g-ico">&#128197;</span> Calendrier des Soldes</a>
            </div>
        </div>
    </div>
</div>

<div class="stats">
    <span>Wishlist : <span class="val">${TOTAL} jeux</span></span>
    <span>En promo : <span class="val-green">${SALE_COUNT}</span></span>
    <span>Meilleure remise : <span class="val-green">-${BEST_DISCOUNT}%</span></span>
    <span>Prix le plus bas : <span class="val-green">${CHEAPEST_FMT}€</span></span>
    <span>Prochain scan auto : <span class="val" id="nextScan"></span></span>
</div>

<div class="controls">
    <div class="search-box">
        <input type="text" id="search" placeholder="Rechercher un jeu..." />
    </div>
    <div class="toolbar">
        <button class="active" data-sort="alpha">A→Z</button>
        <button data-sort="alpha_desc">Z→A</button>
        <button data-sort="price_asc">Prix ↑</button>
        <button data-sort="price_desc">Prix ↓</button>
        <button data-sort="discount">% Promo</button>
        <button data-sort="metacritic">Metacritic</button>
        <div class="price-filter">
            <label>En dessous de</label>
            <input type="range" id="priceMax" min="0" max="${MAX_PRICE_EUR}" value="${MAX_PRICE_EUR}" step="1">
            <span class="price-val" id="priceLabel">${MAX_PRICE_EUR}€</span>
        </div>
    </div>
</div>

<div class="genre-filters" id="genreFilters">
    <button class="genre-btn active" data-genre="all">Tous</button>
    <button class="genre-btn new-only-btn" id="newOnlyBtn" onclick="toggleNewOnly()">🆕 Nouveautés</button>
    <button class="genre-btn expiring-btn" id="expiringBtn" onclick="toggleExpiring()" style="display:none">⏳ Expire bientôt</button>
    ${GENRE_BUTTONS}
</div>

<div class="cat-filters" id="catFilters">
    <button class="cat-btn active" data-cat="all">Tous</button>
    ${CAT_BUTTONS}
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

// ── Tri ──
document.querySelectorAll('.toolbar button').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.toolbar button').forEach(b => b.classList.remove('active'));
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

document.querySelectorAll('.genre-btn:not(.new-only-btn):not(.expiring-btn)').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.genre-btn:not(.new-only-btn):not(.expiring-btn)').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeGenre = btn.dataset.genre;
        applyFilters();
    });
});

document.querySelectorAll('.cat-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeCat = btn.dataset.cat;
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
    const schedules = SCAN_SCHEDULE || [1, 7, 13, 19];
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
    const el = document.getElementById('nextScan');
    function update() {
        const diff = Math.max(0, Math.floor((next - new Date()) / 1000));
        const h = Math.floor(diff / 3600);
        const m = Math.floor((diff % 3600) / 60);
        const hh = String(next.getHours()).padStart(2, '0');
        const mm = String(next.getMinutes()).padStart(2, '0');
        el.textContent = hh + ':' + mm + ' (dans ' + h + 'h' + String(m).padStart(2,'0') + ')';
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
</body>
</html>
HTMLSCRIPT

chmod 644 "$OUTPUT_FILE"
chown www-data:www-data "$OUTPUT_FILE"

ELAPSED=$(( $(date +%s) - START_TIME ))
ok "Page générée : $OUTPUT_FILE"
ok "Durée totale : ${ELAPSED}s"
log "Terminé !"
