#!/bin/bash

set -u

CF_EMAIL=""
CF_API_KEY=""
CF_API_TOKEN=""
CF_CONFIG="${HOME}/.mrcerber-cf.conf"

API="https://api.cloudflare.com/client/v4"

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[0;36m'; M='\033[1;35m'; N='\033[0m'

command -v jq >/dev/null 2>&1 || { echo -e "${R}[!] jq missing. Install: apt install jq -y${N}"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${R}[!] curl missing${N}"; exit 1; }

# Load saved credentials if config exists
if [[ -f "$CF_CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$CF_CONFIG"
fi

prompt_credentials() {
  echo -e "\n${Y}Cloudflare credentials required.${N}"
  echo -e "  ${G}1${N}) API Token  ${C}(recommended — DNS zone token)${N}"
  echo -e "  ${G}2${N}) Global API Key + Email"
  local choice
  read -rp "Auth method [1/2]: " choice
  case "$choice" in
    1)
      read -rsp "API Token: " CF_API_TOKEN; echo
      CF_EMAIL=""; CF_API_KEY=""
      ;;
    2)
      read -rp  "Email: "          CF_EMAIL
      read -rsp "Global API Key: " CF_API_KEY; echo
      CF_API_TOKEN=""
      ;;
    *)
      echo -e "${R}Invalid choice${N}"; exit 1 ;;
  esac

  local save
  read -rp "Save to ${CF_CONFIG} for future use? (y/n): " save
  if [[ "$save" =~ ^[yY]$ ]]; then
    {
      printf 'CF_API_TOKEN="%s"\n' "$CF_API_TOKEN"
      printf 'CF_EMAIL="%s"\n'     "$CF_EMAIL"
      printf 'CF_API_KEY="%s"\n'   "$CF_API_KEY"
    } > "$CF_CONFIG"
    chmod 600 "$CF_CONFIG"
    echo -e "${G}[+] Saved to ${CF_CONFIG}${N}"
  fi
}

# Prompt if no credentials are available
if [[ -z "$CF_API_TOKEN" && ( -z "$CF_API_KEY" || -z "$CF_EMAIL" ) ]]; then
  prompt_credentials
fi

if [ -n "$CF_API_TOKEN" ]; then
  AUTH=(-H "Authorization: Bearer $CF_API_TOKEN")
  AUTH_MODE="API Token"
elif [ -n "$CF_API_KEY" ]; then
  AUTH=(-H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_API_KEY")
  AUTH_MODE="Global API Key"
else
  echo -e "${R}[!] No credentials provided.${N}"
  exit 1
fi
CT=(-H "Content-Type: application/json")

cf() {
  local resp
  if ! resp=$(curl -sf --max-time 30 "${AUTH[@]}" "${CT[@]}" "$@"); then
    echo -e "${R}[!] API request failed (network error or timeout)${N}" >&2
    return 1
  fi
  if jq -e '.success == false' <<< "$resp" >/dev/null 2>&1; then
    echo -e "${R}[!] Cloudflare API error:${N}" >&2
    jq -r '.errors[].message' <<< "$resp" >&2
    return 1
  fi
  printf '%s' "$resp"
}

verify_auth() {
  local resp ok
  if [ -n "$CF_API_TOKEN" ]; then
    resp=$(cf -X GET "$API/user/tokens/verify")
  else
    resp=$(cf -X GET "$API/user")
  fi
  ok=$(echo "$resp" | jq -r '.success')
  if [ "$ok" != "true" ]; then
    echo -e "${R}[!] Auth failed:${N}"; echo "$resp" | jq '.errors'
    echo -e "${Y}Hint: delete ${CF_CONFIG} and re-run to reconfigure credentials.${N}"
    exit 1
  fi
}

load_zones() {
  ZONE_IDS=(); ZONE_NAMES=(); ZONE_STATUSES=()
  local page=1
  while :; do
    local resp ok
    resp=$(cf -X GET "$API/zones?per_page=50&page=$page")
    ok=$(echo "$resp" | jq -r '.success')
    if [ "$ok" != "true" ]; then
      echo -e "${R}[!] Failed to load zones:${N}"; echo "$resp" | jq '.errors'; return 1
    fi
    while IFS='|' read -r zid zname zstatus; do
      [ -n "$zid" ] && ZONE_IDS+=("$zid") && ZONE_NAMES+=("$zname") && ZONE_STATUSES+=("$zstatus")
    done < <(echo "$resp" | jq -r '.result[] | "\(.id)|\(.name)|\(.status)"')
    local total_pages
    total_pages=$(echo "$resp" | jq -r '.result_info.total_pages // 1')
    [ "$page" -ge "$total_pages" ] && break
    page=$((page + 1))
  done
}

load_a_records() {
  local zone_id="$1"
  REC_IDS=(); REC_NAMES=(); REC_CONTENTS=(); REC_PROXIED=(); REC_TTLS=()
  local page=1
  while :; do
    local resp ok
    resp=$(cf -X GET "$API/zones/$zone_id/dns_records?type=A&per_page=100&page=$page")
    ok=$(echo "$resp" | jq -r '.success')
    if [ "$ok" != "true" ]; then
      echo -e "${R}[!] Failed to load records:${N}"; echo "$resp" | jq '.errors'; return 1
    fi
    while IFS='|' read -r rid rname rcontent rproxy rttl; do
      [ -n "$rid" ] && REC_IDS+=("$rid") && REC_NAMES+=("$rname") && \
        REC_CONTENTS+=("$rcontent") && REC_PROXIED+=("$rproxy") && REC_TTLS+=("$rttl")
    done < <(echo "$resp" | jq -r '.result[] | "\(.id)|\(.name)|\(.content)|\(.proxied)|\(.ttl)"')
    local total_pages
    total_pages=$(echo "$resp" | jq -r '.result_info.total_pages // 1')
    [ "$page" -ge "$total_pages" ] && break
    page=$((page + 1))
  done
}

opt_list_all() {
  echo -e "\n${Y}=== All zones and A records ===${N}\n"
  load_zones || return
  if [ "${#ZONE_IDS[@]}" -eq 0 ]; then
    echo -e "${Y}No zones in account${N}"; return
  fi
  echo -e "${C}Total zones: ${#ZONE_IDS[@]}${N}\n"
  for i in "${!ZONE_IDS[@]}"; do
    echo -e "${B}[ ${ZONE_NAMES[$i]} ]${N}  ${C}status: ${ZONE_STATUSES[$i]}${N}"
    load_a_records "${ZONE_IDS[$i]}" || continue
    if [ "${#REC_IDS[@]}" -eq 0 ]; then
      echo -e "  ${Y}(no A records)${N}"
    else
      printf "  %-40s %-18s %-8s %s\n" "NAME" "CONTENT" "PROXY" "TTL"
      printf "  %-40s %-18s %-8s %s\n" "----" "-------" "-----" "---"
      for j in "${!REC_IDS[@]}"; do
        local proxy="DNS"
        [ "${REC_PROXIED[$j]}" = "true" ] && proxy="Proxied"
        local ttl_d="${REC_TTLS[$j]}"
        [ "$ttl_d" = "1" ] && ttl_d="Auto"
        printf "  %-40s %-18s %-8s %s\n" "${REC_NAMES[$j]}" "${REC_CONTENTS[$j]}" "$proxy" "$ttl_d"
      done
    fi
    echo
  done
}

choose_zone() {
  load_zones || return 1
  if [ "${#ZONE_IDS[@]}" -eq 0 ]; then
    echo -e "${Y}No zones in account${N}"; return 1
  fi
  echo -e "\n${C}Select domain:${N}"
  for i in "${!ZONE_IDS[@]}"; do
    printf "  ${G}%2d${N}) %s ${C}[%s]${N}\n" $((i+1)) "${ZONE_NAMES[$i]}" "${ZONE_STATUSES[$i]}"
  done
  echo
  read -rp "Number: " idx
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#ZONE_IDS[@]}" ]; then
    echo -e "${R}Invalid choice${N}"; return 1
  fi
  SEL_ZONE_ID="${ZONE_IDS[$((idx-1))]}"
  SEL_ZONE_NAME="${ZONE_NAMES[$((idx-1))]}"
  return 0
}

choose_record() {
  load_a_records "$SEL_ZONE_ID" || return 1
  if [ "${#REC_IDS[@]}" -eq 0 ]; then
    echo -e "${Y}No A records in $SEL_ZONE_NAME${N}"; return 1
  fi
  echo -e "\n${C}A records in $SEL_ZONE_NAME:${N}"
  for j in "${!REC_IDS[@]}"; do
    local proxy="DNS"
    [ "${REC_PROXIED[$j]}" = "true" ] && proxy="Proxied"
    printf "  ${G}%2d${N}) %-40s -> %-18s ${C}[%s]${N}\n" \
      $((j+1)) "${REC_NAMES[$j]}" "${REC_CONTENTS[$j]}" "$proxy"
  done
  echo
  read -rp "Number: " idx
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#REC_IDS[@]}" ]; then
    echo -e "${R}Invalid choice${N}"; return 1
  fi
  SEL_REC_ID="${REC_IDS[$((idx-1))]}"
  SEL_REC_NAME="${REC_NAMES[$((idx-1))]}"
  SEL_REC_CONTENT="${REC_CONTENTS[$((idx-1))]}"
  SEL_REC_PROXIED="${REC_PROXIED[$((idx-1))]}"
  SEL_REC_TTL="${REC_TTLS[$((idx-1))]}"
  return 0
}

valid_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS='.' parts
  read -ra parts <<< "$ip"
  for p in "${parts[@]}"; do
    [[ "$p" =~ ^[0-9]+$ ]] || return 1
    (( p <= 255 ))          || return 1
  done
  return 0
}

opt_add() {
  echo -e "\n${Y}=== Add A record ===${N}"
  choose_zone || return

  echo
  read -rp "Subdomain (e.g. panel, mail, or @ for root): " sub
  if [ -z "$sub" ]; then
    echo -e "${R}Empty name${N}"; return
  fi
  if [ "$sub" != "@" ] && [[ ! "$sub" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo -e "${R}Invalid subdomain — only letters, numbers, hyphens, dots allowed${N}"; return
  fi
  local fullname
  if [ "$sub" = "@" ] || [ "$sub" = "$SEL_ZONE_NAME" ]; then
    fullname="$SEL_ZONE_NAME"
  else
    fullname="${sub}.${SEL_ZONE_NAME}"
  fi

  read -rp "IP address: " ip
  if ! valid_ip "$ip"; then
    echo -e "${R}Invalid IP${N}"; return
  fi

  read -rp "Proxy through Cloudflare? (y/n) [n]: " px
  local proxied="false"
  [[ "$px" =~ ^[yY]$ ]] && proxied="true"

  read -rp "TTL in seconds (1=Auto) [1]: " ttl
  ttl="${ttl:-1}"

  echo -e "\n${C}Summary:${N}"
  echo "  $fullname -> $ip  (proxied=$proxied, ttl=$ttl) in $SEL_ZONE_NAME"
  read -rp "Confirm? (y/n): " ok
  [[ "$ok" =~ ^[yY]$ ]] || { echo "Cancelled"; return; }

  local payload resp
  payload=$(jq -n --arg n "$fullname" --arg c "$ip" \
    --argjson p "$proxied" --argjson t "$ttl" \
    '{type:"A",name:$n,content:$c,proxied:$p,ttl:$t}')

  resp=$(cf -X POST "$API/zones/$SEL_ZONE_ID/dns_records" --data "$payload")
  if [ "$(echo "$resp" | jq -r '.success')" = "true" ]; then
    echo -e "${G}[+] Created: $(echo "$resp" | jq -r '.result.name') -> $(echo "$resp" | jq -r '.result.content')${N}"
  else
    echo -e "${R}[!] Failed:${N}"; echo "$resp" | jq '.errors'
  fi
}

opt_edit() {
  echo -e "\n${Y}=== Edit A record ===${N}"
  choose_zone || return
  choose_record || return

  echo -e "\n${C}Editing:${N} $SEL_REC_NAME -> $SEL_REC_CONTENT (proxied=$SEL_REC_PROXIED, ttl=$SEL_REC_TTL)"
  echo "Leave empty to keep current value"

  read -rp "New full name [$SEL_REC_NAME]: " new_name
  read -rp "New IP [$SEL_REC_CONTENT]: " new_ip
  read -rp "Proxy (y/n/empty) [proxied=$SEL_REC_PROXIED]: " new_px
  read -rp "New TTL [$SEL_REC_TTL]: " new_ttl

  local fname="${new_name:-$SEL_REC_NAME}"
  local fip="${new_ip:-$SEL_REC_CONTENT}"
  local fproxy="$SEL_REC_PROXIED"
  case "$new_px" in
    y|Y) fproxy="true" ;;
    n|N) fproxy="false" ;;
  esac
  local fttl="${new_ttl:-$SEL_REC_TTL}"

  if [ -n "$new_ip" ] && ! valid_ip "$new_ip"; then
    echo -e "${R}Invalid IP${N}"; return
  fi

  echo -e "\n${C}Summary:${N}"
  echo "  $fname -> $fip  (proxied=$fproxy, ttl=$fttl)"
  read -rp "Confirm? (y/n): " ok
  [[ "$ok" =~ ^[yY]$ ]] || { echo "Cancelled"; return; }

  local payload resp
  payload=$(jq -n --arg n "$fname" --arg c "$fip" \
    --argjson p "$fproxy" --argjson t "$fttl" \
    '{type:"A",name:$n,content:$c,proxied:$p,ttl:$t}')

  resp=$(cf -X PATCH "$API/zones/$SEL_ZONE_ID/dns_records/$SEL_REC_ID" --data "$payload")
  if [ "$(echo "$resp" | jq -r '.success')" = "true" ]; then
    echo -e "${G}[+] Updated: $(echo "$resp" | jq -r '.result.name') -> $(echo "$resp" | jq -r '.result.content')${N}"
  else
    echo -e "${R}[!] Failed:${N}"; echo "$resp" | jq '.errors'
  fi
}

opt_delete() {
  echo -e "\n${Y}=== Delete A record ===${N}"
  choose_zone || return
  choose_record || return

  echo -e "\n${R}About to delete:${N} $SEL_REC_NAME -> $SEL_REC_CONTENT"
  read -rp "Type 'DELETE' to confirm: " confirm
  [ "$confirm" = "DELETE" ] || { echo "Cancelled"; return; }

  local resp
  resp=$(cf -X DELETE "$API/zones/$SEL_ZONE_ID/dns_records/$SEL_REC_ID")
  if [ "$(echo "$resp" | jq -r '.success')" = "true" ]; then
    echo -e "${G}[+] Deleted${N}"
  else
    echo -e "${R}[!] Failed:${N}"; echo "$resp" | jq '.errors'
  fi
}

verify_auth

while :; do
  echo -e "\n${M}========================================${N}"
  echo -e "       ${B}Cloudflare DNS Manager${N}"
  echo -e "       auth: ${C}$AUTH_MODE${N}"
  echo -e "${M}========================================${N}"
  echo -e "  ${G}1${N}) List all domains and A records"
  echo -e "  ${G}2${N}) Add A record to a domain"
  echo -e "  ${G}3${N}) Edit existing A record"
  echo -e "  ${G}4${N}) Delete A record"
  echo -e "  ${G}r${N}) Reconfigure credentials"
  echo -e "  ${G}0${N}) Exit"
  echo
  read -rp "Choice: " choice
  case "$choice" in
    1) opt_list_all ;;
    2) opt_add ;;
    3) opt_edit ;;
    4) opt_delete ;;
    r|R)
      rm -f "$CF_CONFIG"
      echo -e "${Y}Credentials cleared. Re-run the script to set new credentials.${N}"
      exit 0
      ;;
    0) echo "Bye"; exit 0 ;;
    *) echo -e "${R}Invalid choice${N}" ;;
  esac
done
