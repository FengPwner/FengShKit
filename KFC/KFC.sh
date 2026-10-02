#!/usr/bin/env bash
set -euo pipefail

trap 'tput cnorm; tput clear; exit 0' INT TERM

tput civis
tput clear

cols=$(tput cols)
lines=$(tput lines)

check_and_open() {
  local dow
  dow=$(date +%u)
  if [[ "$dow" != "4" ]]; then
    return
  fi

  local tz=""
  if [[ -f /etc/timezone ]]; then
    tz=$(cat /etc/timezone 2>/dev/null || true)
  fi
  if [[ -z "$tz" ]] && command -v timedatectl &>/dev/null; then
    tz=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
  fi
  if [[ -z "$tz" ]]; then
    tz=$(date +%Z 2>/dev/null || true)
  fi

  local is_cn=false
  if [[ -n "$tz" ]]; then
    case "$tz" in
      Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi|PRC|China*)
        is_cn=true
        ;;
    esac
  fi

  if [[ "$is_cn" == false ]]; then
    local offset
    offset=$(date +%z 2>/dev/null || echo "")
    case "$offset" in
      +0800|+08:00)
        is_cn=true
        ;;
    esac
  fi

  if [[ "$is_cn" == true ]]; then
    if command -v xdg-open &>/dev/null; then
      xdg-open "https://global.kfc.com" &
    elif command -v open &>/dev/null; then
      open "https://global.kfc.com" &
    elif command -v start &>/dev/null; then
      start "" "https://global.kfc.com" &
    fi
  fi
}

check_and_open &

words=("KFC" "肯德基")
declare -A cell_row
declare -A cell_word

col_step=8
row_step=2

col_count=$(( (cols + col_step - 1) / col_step ))
row_count=$(( (lines + row_step - 1) / row_step ))

for (( r = 0; r < row_count; r++ )); do
  for (( c = 0; c < col_count; c++ )); do
    cell_row[$r,$c]=$r
    if (( RANDOM % 2 == 0 )); then
      cell_word[$r,$c]="KFC"
    else
      cell_word[$r,$c]="肯德基"
    fi
  done
done

while true; do
  tput cup 0 0

  for (( r = 0; r < row_count; r++ )); do
    for (( c = 0; c < col_count; c++ )); do
      printf "%-*s" "$col_step" ""
    done
    printf "\n"
  done

  tput cup 0 0

  for (( r = 0; r < row_count; r++ )); do
    for (( c = 0; c < col_count; c++ )); do
      local_row=${cell_row[$r,$c]}
      if (( local_row >= 0 && local_row < lines )); then
        tput cup "$local_row" $(( c * col_step ))
        printf "%-*s" "$col_step" "${cell_word[$r,$c]}"
      fi
    done
  done

  for (( r = 0; r < row_count; r++ )); do
    for (( c = 0; c < col_count; c++ )); do
      local_row=${cell_row[$r,$c]}
      local_row=$(( local_row + 1 ))
      if (( local_row >= lines )); then
        local_row=0
        if (( RANDOM % 3 == 0 )); then
          if (( RANDOM % 2 == 0 )); then
            cell_word[$r,$c]="KFC"
          else
            cell_word[$r,$c]="肯德基"
          fi
        fi
      fi
      cell_row[$r,$c]=$local_row
    done
  done

  sleep 0.12
done
