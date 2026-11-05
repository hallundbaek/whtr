#!/usr/bin/env bash

GID=2618425
STEP=300
BACK=7200
AHEAD=3600
WEATHER_URL="https://www.dmi.dk/NinJo2DmiDk/ninjo2dmidk?cmd=llj&id=$GID&tz=Europe/Copenhagen"

now=$(( ($(date +%s) + 150) / STEP * STEP ))
start=$(( now - BACK ))
end=$(( now + AHEAD ))
REF=$(date -u -d @$now +"%Y-%m-%dT%H%%3A%M%%3A%SZ")

tmp_dir="/dev/shm/tmp-radar-$$"
mkdir -p "$tmp_dir"
WEATHER_FILE="$tmp_dir/weather.tsv"
SUN_FILE="$tmp_dir/sun.txt"
WEATHER_MARKER="$tmp_dir/weather-done"
REFETCH_MARKER="$tmp_dir/refetch-done"

cleanup() {
  stty echo icanon 2>/dev/null
  tput cnorm 2>/dev/null
  rm -rf "$tmp_dir"
  clear
}
trap cleanup EXIT
trap 'exit 0' INT TERM
trap 'winch=1' WINCH

frames=()
for (( i = start; i <= end; i += STEP )); do
  frames+=("$i")
done
n=${#frames[@]}
now_idx=$(( (now - start) / STEP ))
sel=$now_idx

fetch_frame() {
  local epoch=$1 ref="" TIME
  (( epoch > now )) && ref="$REF"
  TIME=$(date -u -d @$epoch +"%Y-%m-%dT%H%%3A%M%%3A%SZ")
  curl -s --max-time 20 "https://www.dmi.dk/ZoombareKort/map?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image%2Fpng&TRANSPARENT=true&TIME=$TIME&REFERENCE_TIME=$ref&LAYERS=nowcast_radar&WIDTH=512&HEIGHT=512&SRS=EPSG%3A3575&STYLES=&BBOX=85937.5%2C-3890625%2C250000%2C-3626562.5" \
    | magick png:- -negate -modulate 125,150,220 -transparent "#0e142a" png:- > "$tmp_dir/$epoch.png.tmp" \
    && mv "$tmp_dir/$epoch.png.tmp" "$tmp_dir/$epoch.png"
}

for epoch in "${frames[@]}"; do
  fetch_frame "$epoch" &
done

refetch_pid=""
refetch_loop() {
  local epoch tries
  for epoch in "${frames[@]}"; do
    [ -s "$tmp_dir/$epoch.png" ] && continue
    for tries in 1 2 3; do
      fetch_frame "$epoch"
      [ -s "$tmp_dir/$epoch.png" ] && break
      sleep 1
    done
  done
  touch "$REFETCH_MARKER"
}
start_refetch() {
  if [ -z "$refetch_pid" ] || ! kill -0 "$refetch_pid" 2>/dev/null; then
    refetch_loop &
    refetch_pid=$!
  fi
}

fetch_weather_files() {
  local json nowl
  json=$(curl -s --max-time 10 "$WEATHER_URL") || { touch "$WEATHER_MARKER"; return 1; }
  [ -n "$json" ] || { touch "$WEATHER_MARKER"; return 1; }
  nowl=$(TZ=Europe/Copenhagen date +%Y%m%d%H%M%S)
  printf '%s' "$json" | jq -r --arg t "$nowl" \
    '[.timeserie[] | select(.time >= $t)][0:12][] |
     [.time, (.temp|round), .symbol, .windDir, (.windSpeed|round), ((.precip1*10)|round)/10] | @tsv' \
    > "$WEATHER_FILE"
  printf '%s\n%s\n' \
    "$(printf '%s' "$json" | jq -r .sunrise)" \
    "$(printf '%s' "$json" | jq -r .sunset)" > "$SUN_FILE"
  touch "$WEATHER_MARKER"
}
fetch_weather_files &

sym_code() {
  case "$1" in
    100) printf '☀️';; 101) printf '🌤️';; 102) printf '⛅️';; 103) printf '☁️';; 104) printf '🌫️';;
    105) printf '🌦️';; 106) printf '🌧️';; 107) printf '🌧️';; 108) printf '🌨️';; 109) printf '🌨️';;
    110) printf '❄️';; 111) printf '❄️';; 112) printf '🌦️';; 113) printf '⛈️';; 114) printf '🌨️';;
    115) printf '🌨️';; 116) printf '❄️';; 117) printf '❄️';; 118) printf '🌦️';; 119) printf '🌧️';;
    120) printf '🌨️';; 121) printf '🌨️';; 122) printf '❄️';; 123) printf '🌨️';; 124) printf '🌨️';;
    125) printf '🌦️';; 126) printf '⛈️';; 127) printf '🌨️';; 128) printf '🌨️';; 129) printf '🌨️';;
    130) printf '🌨️';; 131) printf '❄️';; 132) printf '❄️';; 133|134|135|136) printf '⛈️';;
    137|138|139) printf '⛈️';; 140|141|142) printf '⛈️';; 143|144|145|146|147|148|149|150|151) printf '⛈️';;
    1) printf '☀️';; 2) printf '🌤️';; 3) printf '☁️';; 4) printf '🌫️';;
    5) printf '🌦️';; 6) printf '🌧️';; 7) printf '🌧️';; 8) printf '🌨️';; 9) printf '❄️';;
    10) printf '⛈️';; 11) printf '🌦️';; 12) printf '🌨️';; 13) printf '🌨️';; 60) printf '🌧️';;
    *) printf '❓';;
  esac
}

relfmt() {
  local secs=$1 sign=$2 min
  min=$(( secs / 60 ))
  if (( min < 60 )); then printf '%s%d min' "$sign" "$min"; else printf '%s%d t' "$sign" $(( min / 60 )); fi
}

fmtsol() {
  local s=$1
  [ ${#s} -eq 4 ] || return 1
  printf '%s:%s' "${s:0:2}" "${s:2:2}"
}

load_weather() {
  if [ -s "$WEATHER_FILE" ] && [ -s "$SUN_FILE" ]; then
    mapfile -t weather_text < "$WEATHER_FILE"
    srise=$(sed -n 1p "$SUN_FILE")
    sset=$(sed -n 2p "$SUN_FILE")
    hdr_sol="sol $(fmtsol "$srise") / ned $(fmtsol "$sset")"
    weather_ready=1
  fi
}

dashes() {
  local n=$1 i out=""
  for (( i = 0; i < n; i++ )); do out+='─'; done
  printf '%s' "$out"
}

dispw() {
  local s=$1 i c w=0
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in
      '☀'|'🌤'|'⛅'|'☁'|'🌫'|'🌦'|'🌧'|'🌨'|'❄'|'⛈'|'❓') w=$(( w + 2 ));;
      $'\uFE0F') :;;
      *) w=$(( w + 1 ));;
    esac
  done
  printf '%s' "$w"
}

render_weather() {
  local cellw=16 inner=14 cols grid_cols rows hcount i r c
  cols=$(tput cols)
  grid_cols=$(( (cols - 4) / cellw )); (( grid_cols < 1 )) && grid_cols=1
  hcount=${#weather_text[@]}
  (( hcount == 0 )) && return 1
  rows=$(( (hcount + grid_cols - 1) / grid_cols ))
  for (( r = 0; r < rows; r++ )); do
    local t1="" c1="" c2="" c3="" b1=""
    for (( c = 0; c < grid_cols; c++ )); do
      i=$(( r * grid_cols + c ))
      (( i < hcount )) || break
      local t temp sym wdir wspd precip emoji hh mm s1 s2 s3 pad
      read -r t temp sym wdir wspd precip <<< "${weather_text[i]}"
      emoji=$(sym_code "$sym")
      hh=${t:8:2}; mm=${t:10:2}
      s1=$(printf '    %s:%s' "$hh" "$mm")
      s2=$(printf ' %s° %s %s %s' "$temp" "$emoji" "$wdir" "$wspd")
      pad=$(( inner - $(dispw "$s2") )); (( pad < 0 )) && pad=0
      if [ "$precip" != "0" ]; then
        s3=$(LC_ALL=C awk -v p="$precip" 'BEGIN { printf "    %.1fmm", p }')
      else
        s3=""
      fi
      t1+="┌$(dashes "$inner")┐"
      c1+="│$(printf '%-*s' "$inner" "$s1")│"
      c2+="│$(printf '%s%*s' "$s2" "$pad" "")│"
      c3+="│$(printf '%-*s' "$inner" "$s3")│"
      b1+="└$(dashes "$inner")┘"
    done
    printf '%s\n' "$t1"
    printf '%s\n' "$c1"
    printf '%s\n' "$c2"
    printf '%s\n' "$c3"
    printf '%s\n' "$b1"
  done
  return 0
}

tl() {
  local ind=$(( (cols - $(dispw "$1")) / 2 ))
  (( ind < 0 )) && ind=0
  tput cup "$text_row" 0
  tput el
  printf '%*s%s\n' "$ind" "" "$1"
  text_row=$(( text_row + 1 ))
}

draw_bar() {
  local w c i ci nowcol selcol
  w=$(( cols - 2 )); (( w > n )) && w=$n; (( w < 1 )) && w=1
  local -a bar
  for (( c = 0; c < w; c++ )); do bar[c]='─'; done
  for (( i = 0; i < n; i++ )); do
    ci=$(( i * w / n ))
    [ -s "$tmp_dir/${frames[i]}.png" ] || bar[ci]='·'
  done
  nowcol=$(( now_idx * w / n ))
  selcol=$(( sel * w / n ))
  bar[nowcol]='│'
  bar[selcol]='●'
  tl "$(printf '%s' "${bar[@]}")"
  local sl sc se n1 n2
  sl=$(date -d @$start +%H:%M); sc=$(date -d @$now +%H:%M); se=$(date -d @$end +%H:%M)
  n1=$(( nowcol - ${#sl} - ${#sc} / 2 )); (( n1 < 1 )) && n1=1
  n2=$(( w - nowcol - ${#sc} / 2 - ${#se} )); (( n2 < 1 )) && n2=1
  tl "$(printf '%s%*s%s%*s%s' "$sl" "$n1" "" "$sc" "$n2" "" "$se")"
}

compute_layout() {
  local gc
  rows=$(tput lines); cols=$(tput cols)
  if [ "$weather_ready" = 1 ]; then
    gc=$(( (cols - 4) / 16 )); (( gc < 1 )) && gc=1
    grid_rows=$(( (${#weather_text[@]} + gc - 1) / gc )); (( grid_rows < 1 )) && grid_rows=1
    text_lines=$(( 4 + grid_rows * 5 ))
  else
    text_lines=5
  fi
  img_rows=$(( rows - text_lines - 2 ))
  (( img_rows < 2 )) && img_rows=2
  text_start=$(( img_rows + 1 ))
}

place_image() {
  local epoch=${frames[sel]} icat_w=$(( cols - 2 ))
  (( icat_w < 2 )) && icat_w=2
  if [ -s "$tmp_dir/$epoch.png" ]; then
    kitten icat --image-id 1 --scale-up --place "${icat_w}x${img_rows}@1x1" "$tmp_dir/$epoch.png" 2>/dev/null
    tput civis 2>/dev/null
    return 0
  fi
  return 1
}

place_image_or_placeholder() {
  if place_image; then
    last_sel_placed=$sel
    return 0
  fi
  local msg="(frame utilgængelig $(date -d @${frames[sel]} +%H:%M))"
  local ind=$(( (cols - ${#msg}) / 2 )); (( ind < 0 )) && ind=0
  tput cup 1 0
  tput el
  printf '%*s%s\n' "$ind" "" "$msg"
  return 1
}

draw_header() {
  local epoch=${frames[sel]} rel hdr
  if (( epoch == now )); then rel='nu'
  elif (( epoch < now )); then rel=$(relfmt $((now - epoch)) '-')
  else rel=$(relfmt $((epoch - now)) '+'); fi
  hdr="$(date -d @$epoch +'%d. %b %H:%M')  $rel"
  [ -n "$hdr_sol" ] && hdr+="   $hdr_sol"
  tl "$hdr"
}

draw_text_full() {
  text_row=$text_start
  draw_header
  draw_bar
  if [ "$weather_ready" = 1 ]; then
    local wout line
    wout=$(render_weather)
    if [ -n "$wout" ]; then
      while IFS= read -r line; do tl "$line"; done <<< "$wout"
    else
      tl 'vejr utilgængelig'
    fi
  elif [ -f "$WEATHER_MARKER" ]; then
    tl 'vejr utilgængelig'
  else
    tl 'Loader vejr…'
  fi
  tl 'k/j scrub · q quit · w vejr'
}

draw() {
  compute_layout
  local need=0
  [ "$sel" != "$last_sel" ] && need=1
  [ "$img_rows" != "$last_img_rows" ] && need=1
  if [ "$need" = 1 ]; then
    [ "$img_rows" != "$last_img_rows" ] && clear
    place_image_or_placeholder
    last_sel=$sel; last_img_rows=$img_rows
  elif [ -s "$tmp_dir/${frames[sel]}.png" ] && [ "$last_sel_placed" != "$sel" ]; then
    place_image
    last_sel_placed=$sel
  fi
  draw_text_full
  tput civis 2>/dev/null
}

update_scrub() {
  compute_layout
  if [ "$img_rows" != "$last_img_rows" ]; then
    draw
    return
  fi
  if [ "$sel" != "$last_sel" ]; then
    place_image_or_placeholder
    last_sel=$sel; last_img_rows=$img_rows
  fi
  text_row=$text_start
  draw_header
  draw_bar
  tput civis 2>/dev/null
}

scrub() {
  local dir=$1 k ni
  for (( k = 1; k <= n; k++ )); do
    ni=$(( sel + dir * k ))
    (( ni < 0 )) && ni=$(( ni + n ))
    (( ni >= n )) && ni=$(( ni - n ))
    if [ -s "$tmp_dir/${frames[ni]}.png" ]; then
      sel=$ni
      return
    fi
    start_refetch
  done
}

weather_ready=0
weather_text=()
srise=""; sset=""; hdr_sol=""
last_sel=-1
last_img_rows=0
last_sel_placed=-1
cols=0; rows=0; img_rows=0; text_row=0; text_start=0
winch=0

stty -icanon -echo min 0 time 1

clear
printf '  Loader radar…\n'
for (( tries = 0; tries < 150; tries++ )); do
  [ -s "$tmp_dir/${frames[sel]}.png" ] && break
  sleep 0.2
done
[ -s "$tmp_dir/${frames[sel]}.png" ] || start_refetch

tput civis 2>/dev/null

draw

while true; do
  if [ "$winch" = 1 ]; then
    winch=0
    clear
    last_img_rows=-1
    last_sel=-1
    draw
  fi
  if [ -f "$REFETCH_MARKER" ]; then
    rm -f "$REFETCH_MARKER"
    wait "$refetch_pid" 2>/dev/null
    refetch_pid=""
    draw
  fi
  if [ -f "$WEATHER_MARKER" ] && [ "$weather_ready" = 0 ]; then
    load_weather
    draw
  fi
  KEY=""
  read -r -n 1 -t 0.2 KEY
  case "$KEY" in
    k) scrub +1; update_scrub;;
    j) scrub -1; update_scrub;;
    w) weather_ready=0; hdr_sol=""; rm -f "$WEATHER_MARKER"
       fetch_weather_files &
       draw;;
    q) exit 0;;
  esac
done
