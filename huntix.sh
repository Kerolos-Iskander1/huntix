#!/bin/bash

# ------------------------------------------------------------------
# COLOR DEFINITIONS & CONSTANTS
# ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

VERSION="2.0"

# Graceful Ctrl+C
trap 'echo -e "\n${RED}[!] Interrupted by user — exiting.${RESET}"; exit 130' INT

VALID_TOOLS=(gau wayback cdx katana gospider dirsearch urlscan)
VALID_TOOLS_STR=$(IFS=,; echo "${VALID_TOOLS[*]}")

declare -A TOOL_BIN=(
    [gau]="gau"
    [wayback]="waybackurls"
    [cdx]="curl"
    [katana]="katana"
    [gospider]="gospider"
    [dirsearch]="dirsearch"
    [urlscan]="curl"
)
declare -A TOOL_AVAILABLE

CONFIG_FILE="$HOME/.config/huntix/config.yaml"

# ------------------------------------------------------------------
# BANNER & HELP
# ------------------------------------------------------------------
show_banner() {
    echo -e "${CYAN}"
    echo "  ██╗  ██╗ ██╗   ██╗ ███╗   ██╗ ████████╗ ██╗ ██╗  ██╗"
    echo "  ██║  ██║ ██║   ██║ ████╗  ██║ ╚══██╔══╝ ██║ ╚██╗██╔╝"
    echo "  ███████║ ██║   ██║ ██╔██╗ ██║    ██║    ██║  ╚███╔╝ "
    echo "  ██╔══██║ ██║   ██║ ██║╚██╗██║    ██║    ██║  ██╔██╗ "
    echo "  ██║  ██║ ╚██████╔╝ ██║ ╚████║    ██║    ██║ ██╔╝ ██╗"
    echo "  ╚═╝  ╚═╝  ╚═════╝  ╚═╝  ╚═══╝    ╚═╝    ╚═╝ ╚═╝  ╚═╝"
    echo -e "                           ${YELLOW}v${VERSION} - Automated URL Recon${RESET}\n"
}

show_help() {
    show_banner
    echo -e "${YELLOW}DESCRIPTION:${RESET}"
    echo "  HuntiX collects URLs, endpoints, and parameters for one domain or a list"
    echo "  of domains by combining passive archives (gau, waybackurls, Wayback CDX,"
    echo "  urlscan.io) with active crawling and content discovery (katana, gospider,"
    echo "  dirsearch). Every source's results are merged and de-duplicated into one"
    echo "  clean master file."
    echo ""
    echo -e "${YELLOW}INCLUDED TOOLS:${RESET}"
    printf "  %-11s %-14s %s\n" "gau"       "(gau)"         "passive - multiple archive sources"
    printf "  %-11s %-14s %s\n" "wayback"   "(waybackurls)" "passive - archive.org"
    printf "  %-11s %-14s %s\n" "cdx"       "(curl)"        "passive - Wayback CDX API"
    printf "  %-11s %-14s %s\n" "katana"    "(katana)"      "active  - JS-aware crawler"
    printf "  %-11s %-14s %s\n" "gospider"  "(gospider)"    "active  - fast crawler"
    printf "  %-11s %-14s %s\n" "dirsearch" "(dirsearch)"   "active  - directory/file brute-force"
    printf "  %-11s %-14s %s\n" "urlscan"   "(curl+jq)"     "passive - needs API key for full results"
    echo ""
    echo -e "${YELLOW}OPTIONS:${RESET}"
    echo "  -t, --tool <name>    Run only one tool ($VALID_TOOLS_STR)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo -e "${YELLOW}USAGE:${RESET}"
    echo "  $0 target.com                 Run every tool against one domain"
    echo "  $0 domains.txt                Run every tool against each domain in the file"
    echo "  $0 target.com -t gospider     Run only gospider"
    echo ""
    echo -e "${YELLOW}DOMAINS FILE FORMAT:${RESET}"
    echo "  One domain per line, no http/https and no path (e.g. \"example.com\")."
    echo "  Blank lines and lines starting with # are ignored. Scheme/path/whitespace"
    echo "  on each line is stripped automatically if present."
    echo ""
    echo -e "${YELLOW}CONFIGURATION (optional):${RESET}"
    echo "  Settings live in $CONFIG_FILE"
    echo "  Currently supported keys:"
    echo '    urlscan_api_key: "YOUR_KEY_HERE"   # full urlscan.io results instead of public mode'
    echo "  More keys may be added here over time as the tool grows."
    echo ""
    exit 0
}

# ------------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------------
normalize_domain() {
    # Strips CR, leading/trailing whitespace, http(s)://, and any path/query,
    # so every tool downstream receives a clean bare domain.
    local d="$1"
    d="${d//$'\r'/}"
    echo "$d" | sed -E 's~^[[:space:]]+~~; s~^https?://~~; s~[/?].*$~~; s~[[:space:]]+$~~'
}

cleanup_empty() {
    local file="$1"
    if [[ -f "$file" && ! -s "$file" ]]; then
        rm -f "$file"
    fi
}

check_dependencies() {
    echo -e "${YELLOW}[*] Checking dependencies...${RESET}"
    local missing_any=false
    for tool in "${VALID_TOOLS[@]}"; do
        if [[ -n "$SPECIFIC_TOOL" && "$tool" != "$SPECIFIC_TOOL" ]]; then
            continue
        fi
        local bin="${TOOL_BIN[$tool]}"
        if command -v "$bin" >/dev/null 2>&1; then
            TOOL_AVAILABLE[$tool]=true
        else
            TOOL_AVAILABLE[$tool]=false
            missing_any=true
            echo -e "    ${RED}✗${RESET} $tool ${YELLOW}(missing '$bin' — will be skipped)${RESET}"
        fi
    done

    if [[ -n "$SPECIFIC_TOOL" && "${TOOL_AVAILABLE[$SPECIFIC_TOOL]}" == "false" ]]; then
        echo -e "${RED}[✗] '$SPECIFIC_TOOL' requires '${TOOL_BIN[$SPECIFIC_TOOL]}', which isn't installed or isn't in PATH.${RESET}\n"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo -e "    ${RED}✗${RESET} jq ${YELLOW}(missing — urlscan results can't be parsed)${RESET}"
        missing_any=true
    fi
    if ! command -v anew >/dev/null 2>&1; then
        echo -e "${RED}[✗] 'anew' is required to merge/de-duplicate results and is not installed.${RESET}\n"
        exit 1
    fi

    [[ "$missing_any" = false ]] && echo -e "    ${GREEN}✓ all required tools found${RESET}"
    echo ""
}

# ------------------------------------------------------------------
# ARGUMENT PARSING
# ------------------------------------------------------------------
TARGET=""
SPECIFIC_TOOL=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -t|--tool) SPECIFIC_TOOL="$2"; shift ;;
        *) TARGET="$1" ;;
    esac
    shift
done

if [[ -z "$TARGET" ]]; then
    show_help
fi

if [[ -n "$SPECIFIC_TOOL" ]]; then
    valid=false
    for vt in "${VALID_TOOLS[@]}"; do
        [[ "$SPECIFIC_TOOL" == "$vt" ]] && valid=true && break
    done
    if [[ "$valid" = false ]]; then
        echo -e "${RED}[✗] Unknown tool: '${SPECIFIC_TOOL}'${RESET}"
        echo -e "${YELLOW}    Valid tools: ${VALID_TOOLS_STR}${RESET}\n"
        exit 1
    fi
fi

show_banner
SCRIPT_START=$(date +%s)

# ------------------------------------------------------------------
# CONFIG FILE (general — currently only reads urlscan_api_key)
# ------------------------------------------------------------------
URLSCAN_API_KEY=""
if [[ -f "$CONFIG_FILE" ]]; then
    URLSCAN_API_KEY=$(grep -i 'urlscan_api_key:' "$CONFIG_FILE" \
        | sed -E "s/.*urlscan_api_key:[[:space:]]*//; s/[\"']//g; s/[[:space:]]+$//" \
        | tr -d '\r')
fi

check_dependencies

# ------------------------------------------------------------------
# ENVIRONMENT SETUP
# ------------------------------------------------------------------
DOMAINS_LIST=()

if [[ -f "$TARGET" ]]; then
    TARGET_NAME=$(basename "$TARGET" | cut -f 1 -d '.')
    mapfile -t RAW_DOMAINS < <(grep -v '^\s*$' "$TARGET" | grep -v '^\s*#')
    for raw in "${RAW_DOMAINS[@]}"; do
        clean=$(normalize_domain "$raw")
        [[ -n "$clean" ]] && DOMAINS_LIST+=("$clean")
    done
    TOTAL_DOMAINS=${#DOMAINS_LIST[@]}
    if [[ "$TOTAL_DOMAINS" -eq 0 ]]; then
        echo -e "${RED}[✗] No valid domains found in $TARGET${RESET}\n"
        exit 1
    fi
else
    CLEAN_TARGET=$(normalize_domain "$TARGET")
    TARGET_NAME="$CLEAN_TARGET"
    DOMAINS_LIST=("$CLEAN_TARGET")
    TOTAL_DOMAINS=1
fi

RUN_TS=$(date +%Y%m%d_%H%M%S)

if [[ -n "$SPECIFIC_TOOL" ]]; then
    SINGLE_MODE=true
    FINAL_FILE="${SPECIFIC_TOOL}_urls.txt"
    > "$FINAL_FILE"
    DEBUG_LOG="huntix_debug_${RUN_TS}.log"
else
    SINGLE_MODE=false
    OUT_DIR="recon_results_${TARGET_NAME}"
    mkdir -p "$OUT_DIR"
    FINAL_FILE="${OUT_DIR}/all_urls_clean.txt"
    touch "$FINAL_FILE"
    DEBUG_LOG="${OUT_DIR}/debug.log"
fi
> "$DEBUG_LOG"

echo -e "${GREEN}[+] Target Loaded:${RESET} $TARGET"
echo -e "${GREEN}[+] Total Domains to Process:${RESET} $TOTAL_DOMAINS"
if [[ "$SINGLE_MODE" = true ]]; then
    echo -e "${GREEN}[+] Mode:${RESET} Single Tool (${CYAN}${SPECIFIC_TOOL}${RESET})"
    echo -e "${GREEN}[+] Output File:${RESET} $FINAL_FILE"
else
    echo -e "${GREEN}[+] Mode:${RESET} Full Reconnaissance"
    echo -e "${GREEN}[+] Output Directory:${RESET} $OUT_DIR/"
fi
echo -e "${GREEN}[+] Debug Log:${RESET} $DEBUG_LOG\n"

DIRSEARCH_EXTS="conf,config,bak,backup,swp,old,db,sql,asp,aspx,aspx~,asp~,py,py~,rb,rb~,php,php~,cache,cgi,csv,html,inc,jar,js,json,jsp,jsp~,lock,log,rar,sql.gz,sql.zip,sql.tar.gz,sql~,swp~,tar,tar.bz2,tar.gz,txt,wadl,zip,.log,.xml,.js.,.json"

# ------------------------------------------------------------------
# URLSCAN FUNCTION
# ------------------------------------------------------------------
fetch_urlscan() {
    local target_domain="$1"
    local search_after=""
    local has_more=true
    local temp_file=$(mktemp)

    while [[ "$has_more" = true ]]; do
        if [[ -z "$search_after" ]]; then
            API_URL="https://urlscan.io/api/v1/search/?q=domain:${target_domain}&size=10000"
        else
            API_URL="https://urlscan.io/api/v1/search/?q=domain:${target_domain}&size=10000&search_after=${search_after}"
        fi

        if [[ -n "$URLSCAN_API_KEY" ]]; then
            RESPONSE=$(curl -s -H "API-Key: $URLSCAN_API_KEY" "$API_URL" 2>>"$DEBUG_LOG")
        else
            RESPONSE=$(curl -s "$API_URL" 2>>"$DEBUG_LOG")
        fi

        URLS=$(echo "$RESPONSE" | jq -r '.results[].page.url' 2>>"$DEBUG_LOG")

        if [[ -z "$URLS" || "$URLS" == "null" ]]; then
            has_more=false
            break
        fi

        echo "$URLS" | grep -iE "^https?://([a-zA-Z0-9-]+\.)*${target_domain}(:[0-9]+)?(/.*)?$" >> "$temp_file"

        LAST_SORT=$(echo "$RESPONSE" | jq -r '.results[-1].sort | join(",")' 2>>"$DEBUG_LOG")

        if [[ -n "$LAST_SORT" && "$LAST_SORT" != "null" ]]; then
            search_after="$LAST_SORT"
            sleep 1
        else
            has_more=false
        fi
    done

    if [[ -s "$temp_file" ]]; then
        local count=$(wc -l < "$temp_file")
        cat "$temp_file" | anew "$FINAL_FILE" > /dev/null
        if [[ "$SINGLE_MODE" = false ]]; then
            cat "$temp_file" > "${OUT_DIR}/urlscan_${target_domain}.txt"
        fi
        echo -e "    ${GREEN}└─ Found $count URLs from urlscan${RESET}"
    else
        echo -e "    ${YELLOW}└─ Found 0 URLs from urlscan${RESET}"
    fi
    rm -f "$temp_file"
}

# ------------------------------------------------------------------
# CORE EXECUTION FUNCTION PER DOMAIN
# ------------------------------------------------------------------
run_tools_for_domain() {
    local curr_domain="$1"
    local index="$2"
    local temp_out=$(mktemp)

    if [[ -z "$URLSCAN_API_KEY" && ( -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "urlscan" ) && "$index" -eq 1 ]]; then
        echo -e "${YELLOW}[!] Warning: No Urlscan API Key found in $CONFIG_FILE${RESET}"
        echo -e "${YELLOW}[!] Running urlscan in public mode (limited results). Add API key for better results.${RESET}\n"
    fi

    # 1. Katana Crawler
    if [[ ( -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "katana" ) && "${TOOL_AVAILABLE[katana]}" == "true" ]]; then
        echo -e "${BLUE}[$index/$TOTAL_DOMAINS] Running Katana Crawler on: ${CYAN}$curr_domain${RESET}"

        local katana_target="$curr_domain"
        if [[ ! "$katana_target" =~ ^https?:// ]]; then
            katana_target="https://$curr_domain"
        fi

        # NOTE: -ct is "crawl-duration" (max seconds to crawl), NOT thread count.
        # -c is the real concurrency flag. Cap duration generously so large sites
        # aren't cut off after a few seconds.
        echo "---- $curr_domain :: katana ----" >> "$DEBUG_LOG"
        katana -u "$katana_target" -c 20 -ct 60 -silent -no-color -o "$temp_out" >> "$DEBUG_LOG" 2>&1
        if [[ -s "$temp_out" ]]; then
            local count=$(wc -l < "$temp_out")
            cat "$temp_out" | anew "$FINAL_FILE" > /dev/null
            [[ "$SINGLE_MODE" = false ]] && cp "$temp_out" "${OUT_DIR}/katana_${curr_domain}.txt"
            echo -e "    ${GREEN}└─ Found $count URLs${RESET}"
        else
            echo -e "    ${YELLOW}└─ Found 0 URLs${RESET}"
        fi
    fi

    # 2. GoSpider Crawler
    if [[ ( -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "gospider" ) && "${TOOL_AVAILABLE[gospider]}" == "true" ]]; then
        echo -e "${BLUE}[$index/$TOTAL_DOMAINS] Running GoSpider Crawler on: ${CYAN}$curr_domain${RESET}"

        local target_url="$curr_domain"
        if [[ ! "$target_url" =~ ^https?:// ]]; then
            target_url="https://$curr_domain"
        fi

        echo "---- $curr_domain :: gospider ----" >> "$DEBUG_LOG"
        # 1. تشغيل الأداة مباشرة وحفظ مخرجاتها الخام بدون فلترة فورية
        gospider -s "$target_url" -c 10 -d 2 -t 10 > "$temp_out" 2>>"$DEBUG_LOG"

        if [[ -s "$temp_out" ]]; then
            local count=$(wc -l < "$temp_out")

            # 2. استخراج الروابط النظيفة فقط للملف النهائي (FINAL_FILE)
            awk '{print $NF}' "$temp_out" | grep -iE "^https?://" | anew "$FINAL_FILE" > /dev/null

            # 3. حفظ المخرجات الخام كما هي للأداة (مع [robots] و [href] الخ)
            if [[ "$SINGLE_MODE" = true ]]; then
                cat "$temp_out" >> "$FINAL_FILE"
            else
                cp "$temp_out" "${OUT_DIR}/gospider_${curr_domain}.txt"
            fi

            echo -e "    ${GREEN}└─ Found $count entries${RESET}"
        else
            echo -e "    ${YELLOW}└─ Found 0 URLs${RESET}"
        fi
    fi

    # 3. Dirsearch Discovery
    if [[ ( -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "dirsearch" ) && "${TOOL_AVAILABLE[dirsearch]}" == "true" ]]; then
        echo -e "${BLUE}[$index/$TOTAL_DOMAINS] Running Dirsearch Discovery on: ${CYAN}$curr_domain${RESET}"

        local dirsearch_target="$curr_domain"
        if [[ ! "$dirsearch_target" =~ ^https?:// ]]; then
            dirsearch_target="https://$curr_domain"
        fi

        echo "---- $curr_domain :: dirsearch ----" >> "$DEBUG_LOG"
        dirsearch -u "$dirsearch_target" --full-url -t 30 -e "$DIRSEARCH_EXTS" -i 200,301,302 --format=plain -o "$temp_out" >> "$DEBUG_LOG" 2>&1
        if [[ -s "$temp_out" ]]; then
            local count_raw=$(grep -Eo 'https?://[^ ]+' "$temp_out" | wc -l)
            grep -Eo 'https?://[^ ]+' "$temp_out" | anew "$FINAL_FILE" > /dev/null
            [[ "$SINGLE_MODE" = false ]] && cp "$temp_out" "${OUT_DIR}/dirsearch_${curr_domain}.txt"
            echo -e "    ${GREEN}└─ Found $count_raw URLs${RESET}"
        else
            echo -e "    ${YELLOW}└─ Found 0 URLs${RESET}"
        fi
    fi

    # 4. Wayback CDX API
    if [[ -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "cdx" ]]; then
        echo -e "${BLUE}[$index/$TOTAL_DOMAINS] Fetching Wayback CDX for: ${CYAN}$curr_domain${RESET}"
        echo "---- $curr_domain :: cdx ----" >> "$DEBUG_LOG"
        curl -s "https://web.archive.org/cdx/search/cdx?url=*.${curr_domain}/*&fl=original&collapse=urlkey" > "$temp_out" 2>>"$DEBUG_LOG"
        if [[ -s "$temp_out" ]]; then
            local count=$(wc -l < "$temp_out")
            cat "$temp_out" | anew "$FINAL_FILE" > /dev/null
            [[ "$SINGLE_MODE" = false ]] && cp "$temp_out" "${OUT_DIR}/cdx_${curr_domain}.txt"
            echo -e "    ${GREEN}└─ Found $count URLs${RESET}"
        else
            echo -e "    ${YELLOW}└─ Found 0 URLs${RESET}"
        fi
    fi

    # 5. Urlscan API
    if [[ -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "urlscan" ]]; then
        echo -e "${BLUE}[$index/$TOTAL_DOMAINS] Running Urlscan API for: ${CYAN}$curr_domain${RESET}"
        fetch_urlscan "$curr_domain"
    fi

    # 6. Waybackurls
    if [[ ( -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "wayback" ) && "${TOOL_AVAILABLE[wayback]}" == "true" ]]; then
        echo -e "${BLUE}[$index/$TOTAL_DOMAINS] Running Waybackurls on: ${CYAN}$curr_domain${RESET}"
        echo "---- $curr_domain :: wayback ----" >> "$DEBUG_LOG"
        echo "$curr_domain" | waybackurls > "$temp_out" 2>>"$DEBUG_LOG"
        if [[ -s "$temp_out" ]]; then
            local count=$(wc -l < "$temp_out")
            cat "$temp_out" | anew "$FINAL_FILE" > /dev/null
            [[ "$SINGLE_MODE" = false ]] && cp "$temp_out" "${OUT_DIR}/wayback_${curr_domain}.txt"
            echo -e "    ${GREEN}└─ Found $count URLs${RESET}"
        else
            echo -e "    ${YELLOW}└─ Found 0 URLs${RESET}"
        fi
    fi

    # 7. GAU
    if [[ ( -z "$SPECIFIC_TOOL" || "$SPECIFIC_TOOL" == "gau" ) && "${TOOL_AVAILABLE[gau]}" == "true" ]]; then
        echo -e "${BLUE}[$index/$TOTAL_DOMAINS] Running GAU on: ${CYAN}$curr_domain${RESET}"
        echo "---- $curr_domain :: gau ----" >> "$DEBUG_LOG"
        echo "$curr_domain" | gau > "$temp_out" 2>>"$DEBUG_LOG"
        if [[ -s "$temp_out" ]]; then
            local count=$(wc -l < "$temp_out")
            cat "$temp_out" | anew "$FINAL_FILE" > /dev/null
            [[ "$SINGLE_MODE" = false ]] && cp "$temp_out" "${OUT_DIR}/gau_${curr_domain}.txt"
            echo -e "    ${GREEN}└─ Found $count URLs${RESET}"
        else
            echo -e "    ${YELLOW}└─ Found 0 URLs${RESET}"
        fi
    fi

    rm -f "$temp_out"
    echo ""
}

# ------------------------------------------------------------------
# EXECUTION LOOP
# ------------------------------------------------------------------
for i in "${!DOMAINS_LIST[@]}"; do
    idx=$((i + 1))
    d="${DOMAINS_LIST[$i]}"
    run_tools_for_domain "$d" "$idx"
done

cleanup_empty "$FINAL_FILE"

# ------------------------------------------------------------------
# SUMMARY & COMPLETION
# ------------------------------------------------------------------
SCRIPT_END=$(date +%s)
ELAPSED=$((SCRIPT_END - SCRIPT_START))
ELAPSED_FMT=$(printf '%02d:%02d:%02d' $((ELAPSED/3600)) $(((ELAPSED%3600)/60)) $((ELAPSED%60)))

echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}[+] Reconnaissance Process Completed Successfully!${RESET}"
echo -e "${GREEN}====================================================${RESET}"

if [[ "$SINGLE_MODE" = true ]]; then
    printf "${YELLOW}%-22s${RESET} ${CYAN}%s${RESET}\n" "[★] Output File:" "$FINAL_FILE"
else
    printf "%-22s ${CYAN}%s${RESET}\n" "Directory Created:" "${OUT_DIR}/"
    printf "${YELLOW}%-22s${RESET} ${CYAN}%s${RESET}\n" "[★] Clean Master File:" "$FINAL_FILE"

    echo ""
    echo -e "${YELLOW}[i] Results by tool:${RESET}"
    for tool in "${VALID_TOOLS[@]}"; do
        pattern="${OUT_DIR}/${tool}_"*.txt
        if compgen -G "${OUT_DIR}/${tool}_"*.txt > /dev/null 2>&1; then
            total=$(cat "${OUT_DIR}/${tool}_"*.txt 2>/dev/null | wc -l)
            printf "    %-12s %s\n" "$tool" "$total"
        fi
    done
fi

echo ""
if [[ -f "$FINAL_FILE" ]]; then
    printf "${YELLOW}%-22s${RESET} ${GREEN}%s${RESET}\n" "[★] Total Unique URLs:" "$(wc -l < "$FINAL_FILE")"
else
    printf "${YELLOW}%-22s${RESET} ${GREEN}%s${RESET}\n" "[★] Total Unique URLs:" "0"
fi
printf "${YELLOW}%-22s${RESET} ${GREEN}%s${RESET}\n" "[★] Elapsed Time:" "$ELAPSED_FMT"
printf "${YELLOW}%-22s${RESET} ${CYAN}%s${RESET}\n\n" "[★] Debug Log:" "$DEBUG_LOG"
