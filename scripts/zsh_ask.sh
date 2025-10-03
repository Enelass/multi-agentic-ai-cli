#!/usr/bin/env zsh

# Ask: query Codex, Gemini (default), Gemini (flash), and Claude
# UI rules:
# - Print header as: === CLI [ (Model) ]
# - Then output (trimmed of leading/trailing blank lines)
# - Then exactly one blank line between sections

# =======================
# Customization (headers)
# =======================
# Override these in your environment or edit below.
# Comment out the lines to disable a CLI
# Labels shown for each CLI/Model in headers and spinner line.
: ${ASK_NAME_CODEX:="Codex GPT-5"}
: ${ASK_NAME_GEMINI:="Gemini Mistral Large"}
: ${ASK_NAME_FLASH:="Gemini Flash"}
: ${ASK_NAME_COPILOT:="Copilot GPT-5"}
: ${ASK_NAME_CLAUDE:="Claude 4"}

# Whether to include model name in headers (1=yes, 0=no)
: ${ASK_HEADER_FORMAT:="cli"}  # one of: cli, cli_model

# Optional model label overrides (defaults read from your envs)
: ${ASK_MODEL_CODEX:="${OPENAI_MODEL:-}"}
: ${ASK_MODEL_GEMINI:="${GEMINI_MODEL:-Gemini Pro 2.5}"}
: ${ASK_MODEL_FLASH:="gemini-2.0-flash-001"}
: ${ASK_MODEL_COPILOT:="${COPILOT_MODEL:-Claude 4}"}
: ${ASK_MODEL_CLAUDE:="${ANTHROPIC_MODEL:-unknown}"}

# CLI descriptions (shown when ASK_HEADER_FORMAT=cli or cli_model)
: ${ASK_DESC_CODEX:="OpenAI Codex CLI"}
: ${ASK_DESC_GEMINI:="Google Gemini CLI"}
: ${ASK_DESC_FLASH:="Google Gemini CLI"}
: ${ASK_DESC_COPILOT:="GitHub Copilot CLI"}
: ${ASK_DESC_CLAUDE:="Claude Code"}

# Helper: build header string from name + model, honoring ASK_INCLUDE_MODEL
__ask_build_header() {
  local name="$1" desc="$2" model="$3"
  case "${ASK_HEADER_FORMAT}" in
    cli)
      printf "=== %s (%s) ===" "$name" "$desc"
      ;;
    cli_model)
      printf "=== %s (%s, %s) ===" "$name" "$desc" "$model"
      ;;
    *)
      printf "=== %s (%s) ===" "$name" "$desc"
      ;;
  esac
}

# Helper to trim leading/trailing blank lines and print a single trailing blank line
__ask_print_block() {
  local file="$1"
  if [[ -s "$file" ]]; then
    awk 'NR==FNR{lines[NR]=$0; next} END{start=1; while (start<=NR && lines[start] ~ /^[[:space:]]*$/) start++; end=NR; while (end>=start && lines[end] ~ /^[[:space:]]*$/) end--; for (i=start;i<=end;i++) print lines[i];}' "$file" "$file"
  else
    echo "(no response)"
  fi
  printf "\n"
}

# Count non-empty lines after trimming + one trailing blank line that we print
__ask_count_lines() {
  local file="$1"
  if [[ -s "$file" ]]; then
    awk 'NR==FNR{lines[NR]=$0; next} END{start=1; while (start<=NR && lines[start] ~ /^[[:space:]]*$/) start++; end=NR; while (end>=start && lines[end] ~ /^[[:space:]]*$/) end--; if (end>=start) print (end-start+1)+1; else print 1; }' "$file" "$file"
  else
    echo 1
  fi
}

# Trim leading/trailing blank lines into a new file (no trailing extra newline)
__ask_trim_to_file() {
  local in="$1" out="$2"
  if [[ -s "$in" ]]; then
    awk 'NR==FNR{lines[NR]=$0; next} END{start=1; while (start<=NR && lines[start] ~ /^[[:space:]]*$/) start++; end=NR; while (end>=start && lines[end] ~ /^[[:space:]]*$/) end--; for (i=start;i<=end;i++) print lines[i];}' "$in" "$in" > "$out"
  else
    : > "$out"
  fi
}

# Strip ANSI color codes from a string
__ask_strip_ansi() {
  # Strip both real ESC sequences and literal \e sequences
  sed -E $'s/\x1B\[[0-9;]*[A-Za-z]//g; s/\\e\[[0-9;]*[A-Za-z]//g'
}

# Render two columns with per-column timing in the header:
# args: left_header left_file right_header right_file left_timing right_timing
__ask_render_two_columns() {
  local left_header="$1" left_file="$2" right_header="$3" right_file="$4" left_timing="$5" right_timing="$6"

  local cols
  cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}
  local spacer=" | "
  # Compute timing cell width based on plain (ANSI-stripped) strings; minimum 10
  local t_plain_l t_plain_r t_width
  t_plain_l=$(printf "%s" "${left_timing}" | __ask_strip_ansi)
  t_plain_r=$(printf "%s" "${right_timing}" | __ask_strip_ansi)
  t_width=${#t_plain_l}
  (( ${#t_plain_r} > t_width )) && t_width=${#t_plain_r}
  (( t_width < 10 )) && t_width=10
  # Header text width per side
  local colw_hdr=$(( (cols - 3*${#spacer} - 2*t_width) / 2 ))
  (( colw_hdr < 24 )) && colw_hdr=24
  # Content column width per side (includes timing + one spacer) so middle border aligns
  local colw=$(( colw_hdr + ${#spacer} + t_width ))

  # Prepare wrapped content
  local ltmp rtmp
  ltmp=$(mktemp -t askcol_l_XXXXXX)
  rtmp=$(mktemp -t askcol_r_XXXXXX)
  __ask_trim_to_file "$left_file" "$ltmp"
  __ask_trim_to_file "$right_file" "$rtmp"
  local lwrap rwrap
  lwrap=$(mktemp -t askcol_lw_XXXXXX)
  rwrap=$(mktemp -t askcol_rw_XXXXXX)
  fold -s -w "$colw" "$ltmp" > "$lwrap"
  fold -s -w "$colw" "$rtmp" > "$rwrap"

  # Header line: strip ANSI, truncate to column width, then colorize consistently
  local left_plain right_plain
  left_plain=$(printf "%s" "$left_header" | __ask_strip_ansi)
  right_plain=$(printf "%s" "$right_header" | __ask_strip_ansi)
  # Remove any accidental leading/trailing backslashes
  while [[ "$left_plain" == \\* ]]; do left_plain=${left_plain#\\}; done
  while [[ "$right_plain" == \\* ]]; do right_plain=${right_plain#\\}; done
  while [[ "$left_plain" == *\\ ]]; do left_plain=${left_plain%\\}; done
  while [[ "$right_plain" == *\\ ]]; do right_plain=${right_plain%\\}; done
  # Do not hard-truncate headers; pad when shorter, leave intact when longer
  # Choose colors based on model names
  local BOLD="\e[1m" RESET="\e[0m" BLUE="\e[34m" CYAN="\e[36m" MAGENTA="\e[35m" YELLOW="\e[33m"
  local lcol="$CYAN" rcol="$CYAN"
  [[ "$left_plain" == *"${ASK_NAME_CODEX}"* ]] && lcol="$BLUE"
  [[ "$left_plain" == *"${ASK_NAME_COPILOT}"* ]] && lcol="$BLUE"
  [[ "$left_plain" == *"${ASK_NAME_CLAUDE}"* ]] && lcol="$MAGENTA"
  [[ "$left_plain" == *"${ASK_NAME_FLASH}"* ]] && lcol="$YELLOW"
  [[ "$right_plain" == *"${ASK_NAME_CODEX}"* ]] && rcol="$BLUE"
  [[ "$right_plain" == *"${ASK_NAME_COPILOT}"* ]] && rcol="$BLUE"
  [[ "$right_plain" == *"${ASK_NAME_CLAUDE}"* ]] && rcol="$MAGENTA"
  [[ "$right_plain" == *"${ASK_NAME_FLASH}"* ]] && rcol="$YELLOW"
  # Decide if padded header fits; if not, print without padding to avoid cropping
  local required_width=$(( ${#left_plain} + ${#spacer} + t_width + ${#spacer} + ${#right_plain} + ${#spacer} + t_width ))
  if (( required_width > cols )); then
    printf "%b%s%b%s%b%s%b%s%b\n" \
      "$BOLD$lcol" "$left_plain" "$RESET" "$spacer" "$BOLD$lcol" "$t_plain_l" "$RESET" "$spacer" \
      "$BOLD$rcol" "$right_plain" "$RESET" "$spacer" "$BOLD$rcol" "$t_plain_r" "$RESET"
  else
    # Left header cell
    printf "%b" "$BOLD$lcol"
    printf "%-*s" "$colw_hdr" "$left_plain"
    printf "%b" "$RESET"
    # Left timing cell
    printf "%s" "$spacer"
    printf "%b" "$BOLD$lcol"
    printf "%-*s" "$t_width" "${t_plain_l}"
    printf "%b" "$RESET"
    # Middle spacer
    printf "%s" "$spacer"
    # Right header cell
    printf "%b" "$BOLD$rcol"
    printf "%-*s" "$colw_hdr" "$right_plain"
    printf "%b" "$RESET"
    # Right timing cell
    printf "%s" "$spacer"
    printf "%b" "$BOLD$rcol"
    printf "%-*s" "$t_width" "${t_plain_r}"
    printf "%b\n" "$RESET"
  fi

  # Content rows
  paste -d '\t' "$lwrap" "$rwrap" | while IFS=$'\t' read -r L R; do
    printf "%-*s%s%s\n" "$colw" "${L:-}" "$spacer" "${R:-}"
  done

  printf "\n"
  rm -f "$ltmp" "$rtmp" "$lwrap" "$rwrap"
}

# Spinner helpers (single status line)
start_spinner() {
  local delay=${SPINNER_DELAY:-0.12}
  local default_frames='[    ████    ]|[   ████     ]|[  ████      ]|[ ████       ]|[████        ]|[███        █]|[██        ██]|[█        ███]|[        ████]|[       ████ ]|[      ████  ]|[     ████   ]'
  local frames_src
  if [[ -n ${SPINNER_FRAMES:-} ]]; then
    frames_src="$SPINNER_FRAMES"
  elif [[ -n ${ASK_SIMPLE_SPINNER:-} ]]; then
    frames_src='-|-|\\|/'
  else
    frames_src="$default_frames"
  fi
  [[ -n $SPINNER_PID ]] && return
  (
    local frames; frames=(${(s:|:)frames_src})
    local i=1
    while :; do
      printf "\r%b %s " "${SPINNER_TEXT}" "${frames[$i]}"
      (( i = (i % ${#frames[@]}) + 1 ))
      sleep "$delay"
    done
  ) &
  SPINNER_PID=$!
}

stop_spinner() {
  if [[ -n $SPINNER_PID ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    unset SPINNER_PID
    # Clear the spinner line
    printf "\r\033[2K"
  fi
}

Ask() {
  if [[ -z "$*" ]]; then
    echo "Usage: Ask <question>"
    return 1
  fi
  local prompt="$*"
  local safety_note="Note: This prompt is sent to multiple agents in parallel; to avoid conflicting operations, do not edit or write files, and do not run disruptive commands."
  local full_prompt="$prompt $safety_note"
  local start_epoch; start_epoch=$(date +%s)

  # Colors
  local BOLD="\e[1m" RESET="\e[0m" BLUE="\e[34m" CYAN="\e[36m" MAGENTA="\e[35m" YELLOW="\e[33m"

  # Suppress job-control noise within this function
  setopt localoptions
  unsetopt monitor
  unsetopt notify

  # Temp files
  local codex_out gem_out gemf_out copilot_out claude_out
  codex_out=$(mktemp -t ask_codex_XXXXXX)
  gem_out=$(mktemp -t ask_gemini_XXXXXX)
  gemf_out=$(mktemp -t ask_geminif_XXXXXX)
  copilot_out=$(mktemp -t ask_copilot_XXXXXX)
  claude_out=$(mktemp -t ask_claude_XXXXXX)

  # Launch all in background
  codex exec "$full_prompt" --skip-git-repo-check --output-last-message "$codex_out" > /dev/null 2>&1 & local pid_codex=$!
  gemini -p "$full_prompt" > "$gem_out" 2>&1 & local pid_gem=$!
  gemini --model "gemini-2.0-flash-001" -p "$full_prompt" > "$gemf_out" 2>&1 & local pid_gemf=$!
  copilot -p "$full_prompt" > "$copilot_out" 2>&1 & local pid_copilot=$!
  claude -p "$full_prompt" > "$claude_out" 2>&1 & local pid_claude=$!
  # Ctrl-C trap: stop spinner, kill jobs, cleanup
  local __ask_cleanup_done=0
  __ask_sigint_handler() {
    (( __ask_cleanup_done )) && return
    __ask_cleanup_done=1
    stop_spinner
    printf "\r\033[2K"
    kill $pid_codex $pid_gem $pid_gemf $pid_claude 2>/dev/null
    rm -f "$codex_out" "$gem_out" "$gemf_out" "$claude_out"
    printf "%bUser terminated. Cleaned up background tasks.%b\n" "$BOLD" "$RESET"
    trap - INT
    return 130
  }
  trap __ask_sigint_handler INT
  # Spinner status (single line) and completion tracking
  local codex_mark="⏳" gem_mark="⏳" gemf_mark="⏳" copilot_mark="⏳" claude_mark="⏳"
  SPINNER_DELAY=0.15
  SPINNER_TEXT="${BOLD}${BLUE}${ASK_NAME_CODEX}${RESET} ${codex_mark}  ${CYAN}${ASK_NAME_GEMINI}${RESET} ${gem_mark}  ${YELLOW}${ASK_NAME_FLASH}${RESET} ${gemf_mark}  ${BLUE}${ASK_NAME_COPILOT}${RESET} ${copilot_mark}  ${MAGENTA}${ASK_NAME_CLAUDE}${RESET} ${claude_mark}"
  start_spinner

  local done_codex=0 done_gem=0 done_gemf=0 done_copilot=0 done_claude=0
  while (( done_codex + done_gem + done_gemf + done_copilot + done_claude < 5 )); do
    if (( ! done_codex )) && ! kill -0 $pid_codex 2>/dev/null; then
      stop_spinner
      printf "%b%s%b\n" "$BOLD$BLUE" "$(__ask_build_header "${ASK_NAME_CODEX}" "${ASK_DESC_CODEX}" "${ASK_MODEL_CODEX}")" "$RESET"
      local d=$(( $(stat -f "%m" "$codex_out" 2>/dev/null || echo "$start_epoch") - start_epoch ))
      printf "%b⏱ Took %ds%b\n" "$BOLD$BLUE" "$d" "$RESET"
      __ask_print_block "$codex_out"
      done_codex=1; codex_mark="✓"
      SPINNER_TEXT="${BOLD}${BLUE}${ASK_NAME_CODEX}${RESET} ${codex_mark}  ${CYAN}${ASK_NAME_GEMINI}${RESET} ${gem_mark}  ${YELLOW}${ASK_NAME_FLASH}${RESET} ${gemf_mark}  ${BLUE}${ASK_NAME_COPILOT}${RESET} ${copilot_mark}  ${MAGENTA}${ASK_NAME_CLAUDE}${RESET} ${claude_mark}"
      start_spinner
    fi
    if (( ! done_gem )) && ! kill -0 $pid_gem 2>/dev/null; then
      stop_spinner
      printf "%b%s%b\n" "$BOLD$CYAN" "$(__ask_build_header "${ASK_NAME_GEMINI}" "${ASK_DESC_GEMINI}" "${ASK_MODEL_GEMINI}")" "$RESET"
      local d=$(( $(stat -f "%m" "$gem_out" 2>/dev/null || echo "$start_epoch") - start_epoch ))
      printf "%b⏱ Took %ds%b\n" "$BOLD$CYAN" "$d" "$RESET"
      __ask_print_block "$gem_out"
      done_gem=1; gem_mark="✓"
      SPINNER_TEXT="${BOLD}${BLUE}${ASK_NAME_CODEX}${RESET} ${codex_mark}  ${CYAN}${ASK_NAME_GEMINI}${RESET} ${gem_mark}  ${YELLOW}${ASK_NAME_FLASH}${RESET} ${gemf_mark}  ${BLUE}${ASK_NAME_COPILOT}${RESET} ${copilot_mark}  ${MAGENTA}${ASK_NAME_CLAUDE}${RESET} ${claude_mark}"
      start_spinner
    fi
    if (( ! done_gemf )) && ! kill -0 $pid_gemf 2>/dev/null; then
      stop_spinner
      printf "%b%s%b\n" "$BOLD$YELLOW" "$(__ask_build_header "${ASK_NAME_FLASH}" "${ASK_DESC_FLASH}" "${ASK_MODEL_FLASH}")" "$RESET"
      local d=$(( $(stat -f "%m" "$gemf_out" 2>/dev/null || echo "$start_epoch") - start_epoch ))
      printf "%b⏱ Took %ds%b\n" "$BOLD$YELLOW" "$d" "$RESET"
      __ask_print_block "$gemf_out"
      done_gemf=1; gemf_mark="✓"
      SPINNER_TEXT="${BOLD}${BLUE}${ASK_NAME_CODEX}${RESET} ${codex_mark}  ${CYAN}${ASK_NAME_GEMINI}${RESET} ${gem_mark}  ${YELLOW}${ASK_NAME_FLASH}${RESET} ${gemf_mark}  ${BLUE}${ASK_NAME_COPILOT}${RESET} ${copilot_mark}  ${MAGENTA}${ASK_NAME_CLAUDE}${RESET} ${claude_mark}"
      start_spinner
    fi
    if (( ! done_copilot )) && ! kill -0 $pid_copilot 2>/dev/null; then
      stop_spinner
      printf "%b%s%b\n" "$BOLD$BLUE" "$(__ask_build_header "${ASK_NAME_COPILOT}" "${ASK_DESC_COPILOT}" "${ASK_MODEL_COPILOT}")" "$RESET"
      local d=$(( $(stat -f "%m" "$copilot_out" 2>/dev/null || echo "$start_epoch") - start_epoch ))
      printf "%b⏱ Took %ds%b\n" "$BOLD$BLUE" "$d" "$RESET"
      __ask_print_block "$copilot_out"
      done_copilot=1; copilot_mark="✓"
      SPINNER_TEXT="${BOLD}${BLUE}${ASK_NAME_CODEX}${RESET} ${codex_mark}  ${CYAN}${ASK_NAME_GEMINI}${RESET} ${gem_mark}  ${YELLOW}${ASK_NAME_FLASH}${RESET} ${gemf_mark}  ${BLUE}${ASK_NAME_COPILOT}${RESET} ${copilot_mark}  ${MAGENTA}${ASK_NAME_CLAUDE}${RESET} ${claude_mark}"
      start_spinner
    fi
    if (( ! done_claude )) && ! kill -0 $pid_claude 2>/dev/null; then
      stop_spinner
      printf "%b%s%b\n" "$BOLD$MAGENTA" "$(__ask_build_header "${ASK_NAME_CLAUDE}" "${ASK_DESC_CLAUDE}" "${ASK_MODEL_CLAUDE}")" "$RESET"
      local d=$(( $(stat -f "%m" "$claude_out" 2>/dev/null || echo "$start_epoch") - start_epoch ))
      printf "%b⏱ Took %ds%b\n" "$BOLD$MAGENTA" "$d" "$RESET"
      __ask_print_block "$claude_out"
      done_claude=1; claude_mark="✓"
      SPINNER_TEXT="${BOLD}${BLUE}Codex${RESET} ${codex_mark}  ${CYAN}Gemini${RESET} ${gem_mark}  ${YELLOW}Flash${RESET} ${gemf_mark}  ${MAGENTA}Claude${RESET} ${claude_mark}"
      start_spinner
    fi
    sleep 0.1
  done
  stop_spinner
  trap - INT

  # Ensure all background jobs are reaped to avoid SIGHUP warnings
  wait $pid_codex $pid_gem $pid_gemf $pid_copilot $pid_claude 2>/dev/null

  # Cleanup
  rm -f "$codex_out" "$gem_out" "$gemf_out" "$copilot_out" "$claude_out"
  # Final status line
  printf "%bDone:%b %b%s%b ✓  %b%s%b ✓  %b%s%b ✓  %b%s%b ✓  %b%s%b ✓\n" \
    "$BOLD" "$RESET" "$BLUE" "${ASK_NAME_CODEX}" "$RESET" "$CYAN" "${ASK_NAME_GEMINI}" "$RESET" "$YELLOW" "${ASK_NAME_FLASH}" "$RESET" "$BLUE" "${ASK_NAME_COPILOT}" "$RESET" "$MAGENTA" "${ASK_NAME_CLAUDE}" "$RESET"
}

# AskFast: run all models in parallel and print each block as soon as it completes
AskFast() {
  if [[ -z "$*" ]]; then
    echo "Usage: AskFast <question>"
    return 1
  fi
  local prompt="$*"
  local safety_note="Note: This prompt is sent to multiple agents in parallel; to avoid conflicting operations, do not edit or write files, and do not run disruptive commands."
  local full_prompt="$prompt $safety_note"

  # Colors
  local BOLD="\e[1m" RESET="\e[0m" BLUE="\e[34m" CYAN="\e[36m" MAGENTA="\e[35m" YELLOW="\e[33m"

  # Temp files
  local codex_out gem_out gemf_out claude_out
  codex_out=$(mktemp -t askfast_codex_XXXXXX)
  gem_out=$(mktemp -t askfast_gem_XXXXXX)
  gemf_out=$(mktemp -t askfast_gemf_XXXXXX)
  claude_out=$(mktemp -t askfast_claude_XXXXXX)

  # Launch all in background
  codex exec "$full_prompt" --skip-git-repo-check --output-last-message "$codex_out" > /dev/null 2>&1 & local pid_codex=$!
  gemini -p "$full_prompt" > "$gem_out" 2>&1 & local pid_gem=$!
  gemini --model "gemini-2.0-flash-001" -p "$full_prompt" > "$gemf_out" 2>&1 & local pid_gemf=$!
  claude -p "$full_prompt" > "$claude_out" 2>&1 & local pid_claude=$!

  # Print headers with initial spinners
  local frames=("|" "/" "-" "\\") idx=0
  printf "%b=== Codex (%s) === ⏳%b\n" "$BOLD$BLUE" "${OPENAI_MODEL:-unknown}" "$RESET"
  printf "%b=== Gemini (%s) === ⏳%b\n" "$BOLD$CYAN" "${GEMINI_MODEL:-default}" "$RESET"
  printf "%b=== Gemini (gemini-2.0-flash-001) === ⏳%b\n" "$BOLD$YELLOW" "$RESET"
  printf "%b=== Claude (%s) === ⏳%b\n" "$BOLD$MAGENTA" "${ANTHROPIC_MODEL:-unknown}" "$RESET"

  # Track completion flags
  local done_codex=0 done_gem=0 done_gemf=0 done_claude=0
  local appended_lines=0

  # Helper: update a header spinner or mark done
  __update_header() {
    local header_index=$1; local text=$2
    # Move cursor up to the header line from current bottom
    local up=$(( appended_lines + 4 - (header_index - 1) ))
    printf "\033[%dA" "$up"  # move up
    printf "\r\033[2K%b\n" "$text"  # clear line and rewrite, keep newline to remain on next header line
    # Move cursor back down to bottom
    printf "\033[%dB" "$up"
  }

  # Spinner + completion loop
  while (( done_codex + done_gem + done_gemf + done_claude < 4 )); do
    local f=${frames[idx % ${#frames[@]}]}
    ((idx++))
    if (( ! done_codex )); then
      if kill -0 $pid_codex 2>/dev/null; then
        __update_header 1 "${BOLD}${BLUE}=== Codex (${OPENAI_MODEL:-unknown}) === ${f}${RESET}"
      else
        __update_header 1 "${BOLD}${BLUE}=== Codex (${OPENAI_MODEL:-unknown}) === ✓${RESET}"
        # Print output block
        __ask_print_block "$codex_out"
        done_codex=1
      fi
    fi
    if (( ! done_gem )); then
      if kill -0 $pid_gem 2>/dev/null; then
        __update_header 2 "${BOLD}${CYAN}=== Gemini (${GEMINI_MODEL:-default}) === ${f}${RESET}"
      else
        __update_header 2 "${BOLD}${CYAN}=== Gemini (${GEMINI_MODEL:-default}) === ✓${RESET}"
        __ask_print_block "$gem_out"
        done_gem=1
      fi
    fi
    if (( ! done_gemf )); then
      if kill -0 $pid_gemf 2>/dev/null; then
        __update_header 3 "${BOLD}${YELLOW}=== Gemini (gemini-2.0-flash-001) === ${f}${RESET}"
      else
        __update_header 3 "${BOLD}${YELLOW}=== Gemini (gemini-2.0-flash-001) === ✓${RESET}"
        __ask_print_block "$gemf_out"
        done_gemf=1
      fi
    fi
    if (( ! done_claude )); then
      if kill -0 $pid_claude 2>/dev/null; then
        __update_header 4 "${BOLD}${MAGENTA}=== Claude (${ANTHROPIC_MODEL:-unknown}) === ${f}${RESET}"
      else
        __update_header 4 "${BOLD}${MAGENTA}=== Claude (${ANTHROPIC_MODEL:-unknown}) === ✓${RESET}"
        __ask_print_block "$claude_out"
        done_claude=1
      fi
    fi
    # Update appended_lines by counting last printed block (approximate by reading file length)
    # Note: We cannot easily count without recomputing; skip dynamic cursor math and rely on relative moves
    sleep 0.1
  done

  # Cleanup
  rm -f "$codex_out" "$gem_out" "$gemf_out" "$claude_out"
}

# AskColumns: run in parallel, then render two-column summary
AskColumns() {
  if [[ -z "$*" ]]; then
    echo "Usage: AskColumns <question>"
    return 1
  fi
  local prompt="$*"
  local safety_note="Note: This prompt is sent to multiple agents in parallel; to avoid conflicting operations, do not edit or write files, and do not run disruptive commands."
  local full_prompt="$prompt $safety_note"

  # Colors
  local BOLD="\e[1m" RESET="\e[0m" BLUE="\e[34m" CYAN="\e[36m" MAGENTA="\e[35m" YELLOW="\e[33m"

  # Suppress job-control noise within this function
  setopt localoptions
  unsetopt monitor
  unsetopt notify

  # Temp files
  local codex_out gem_out gemf_out copilot_out claude_out
  codex_out=$(mktemp -t askcol_codex_XXXXXX)
  gem_out=$(mktemp -t askcol_gem_XXXXXX)
  gemf_out=$(mktemp -t askcol_gemf_XXXXXX)
  copilot_out=$(mktemp -t askcol_copilot_XXXXXX)
  claude_out=$(mktemp -t askcol_claude_XXXXXX)

  # Run all in background
  local start_epoch; start_epoch=$(date +%s)
  codex exec "$full_prompt" --skip-git-repo-check --output-last-message "$codex_out" > /dev/null 2>&1 & local pid_codex=$!
  gemini -p "$full_prompt" > "$gem_out" 2>&1 & local pid_gem=$!
  gemini --model "gemini-2.0-flash-001" -p "$full_prompt" > "$gemf_out" 2>&1 & local pid_gemf=$!
  copilot -p "$full_prompt" > "$copilot_out" 2>&1 & local pid_copilot=$!
  claude -p "$full_prompt" > "$claude_out" 2>&1 & local pid_claude=$!

  # Show question and a spinner while waiting
  local BOLD="\e[1m" RESET="\e[0m" BLUE="\e[34m" CYAN="\e[36m" MAGENTA="\e[35m" YELLOW="\e[33m"
  printf "%bQuestion:%b %s\n" "$BOLD" "$RESET" "$prompt"
  SPINNER_DELAY=0.15
  SPINNER_TEXT="${BOLD}${BLUE}${ASK_NAME_CODEX}${RESET} ⏳  ${CYAN}${ASK_NAME_GEMINI}${RESET} ⏳  ${YELLOW}${ASK_NAME_FLASH}${RESET} ⏳  ${MAGENTA}${ASK_NAME_CLAUDE}${RESET} ⏳"
  start_spinner

  # Trap for Ctrl-C
  local __askcol_cleanup_done=0
  __askcol_sigint_handler() {
    (( __askcol_cleanup_done )) && return
    __askcol_cleanup_done=1
    stop_spinner
    printf "\r\033[2K"
    kill $pid_codex $pid_gem $pid_gemf $pid_claude 2>/dev/null
    rm -f "$codex_out" "$gem_out" "$gemf_out" "$claude_out"
    printf "%bUser terminated. Cleaned up background tasks.%b\n" "$BOLD" "$RESET"
    trap - INT
    return 130
  }
  trap __askcol_sigint_handler INT

  # Live spinner with per-model marks; update as models finish
  local codex_mark="⏳" gem_mark="⏳" gemf_mark="⏳" claude_mark="⏳"
  while :; do
    local alive=0
    if kill -0 $pid_codex 2>/dev/null; then alive=1; else [[ $codex_mark != "✓" ]] && codex_mark="✓"; fi
    if kill -0 $pid_gem 2>/dev/null; then alive=1; else [[ $gem_mark != "✓" ]] && gem_mark="✓"; fi
    if kill -0 $pid_gemf 2>/dev/null; then alive=1; else [[ $gemf_mark != "✓" ]] && gemf_mark="✓"; fi
    if kill -0 $pid_claude 2>/dev/null; then alive=1; else [[ $claude_mark != "✓" ]] && claude_mark="✓"; fi
    SPINNER_TEXT="${BOLD}${BLUE}Codex${RESET} ${codex_mark}  ${CYAN}Gemini${RESET} ${gem_mark}  ${YELLOW}Flash${RESET} ${gemf_mark}  ${MAGENTA}Claude${RESET} ${claude_mark}"
    (( alive == 0 )) && break
    sleep 0.1
  done
  stop_spinner
  trap - INT

  # Reap background jobs
  wait $pid_codex $pid_gem $pid_gemf $pid_claude 2>/dev/null || true

  # Compute durations from start to file mtime
  local m_codex m_gem m_gemf m_copilot m_claude
  m_codex=$(stat -f "%m" "$codex_out" 2>/dev/null || echo "$start_epoch")
  m_gem=$(stat -f "%m" "$gem_out" 2>/dev/null || echo "$start_epoch")
  m_gemf=$(stat -f "%m" "$gemf_out" 2>/dev/null || echo "$start_epoch")
  m_copilot=$(stat -f "%m" "$copilot_out" 2>/dev/null || echo "$start_epoch")
  m_claude=$(stat -f "%m" "$claude_out" 2>/dev/null || echo "$start_epoch")
  local d_codex d_gem d_gemf d_copilot d_claude
  d_codex=$(( m_codex - start_epoch ))
  d_gem=$(( m_gem - start_epoch ))
  d_gemf=$(( m_gemf - start_epoch ))
  d_copilot=$(( m_copilot - start_epoch ))
  d_claude=$(( m_claude - start_epoch ))

  # Augment outputs with trimmed content only (timing now inline in header)
  local codex_aug gem_aug gemf_aug copilot_aug claude_aug tmp
  codex_aug=$(mktemp -t askcol_codex_aug_XXXXXX)
  gem_aug=$(mktemp -t askcol_gem_aug_XXXXXX)
  gemf_aug=$(mktemp -t askcol_gemf_aug_XXXXXX)
  copilot_aug=$(mktemp -t askcol_copilot_aug_XXXXXX)
  claude_aug=$(mktemp -t askcol_claude_aug_XXXXXX)
  # Prepare trimmed content
  tmp=$(mktemp -t askcol_trim_XXXXXX); __ask_trim_to_file "$codex_out" "$tmp"; cat "$tmp" > "$codex_aug"; rm -f "$tmp"
  tmp=$(mktemp -t askcol_trim_XXXXXX); __ask_trim_to_file "$gem_out" "$tmp"; cat "$tmp" > "$gem_aug"; rm -f "$tmp"
  tmp=$(mktemp -t askcol_trim_XXXXXX); __ask_trim_to_file "$gemf_out" "$tmp"; cat "$tmp" > "$gemf_aug"; rm -f "$tmp"
  tmp=$(mktemp -t askcol_trim_XXXXXX); __ask_trim_to_file "$copilot_out" "$tmp"; cat "$tmp" > "$copilot_aug"; rm -f "$tmp"
  tmp=$(mktemp -t askcol_trim_XXXXXX); __ask_trim_to_file "$claude_out" "$tmp"; cat "$tmp" > "$claude_aug"; rm -f "$tmp"

  # Render two rows: [Codex | Gemini], then [Claude | Gemini Flash]
  local codex_hdr gem_hdr gemf_hdr copilot_hdr claude_hdr
  codex_hdr="${BOLD}${BLUE}$(__ask_build_header "${ASK_NAME_CODEX}" "${ASK_DESC_CODEX}" "${ASK_MODEL_CODEX}")${RESET}"
  gem_hdr="${BOLD}${CYAN}$(__ask_build_header "${ASK_NAME_GEMINI}" "${ASK_DESC_GEMINI}" "${ASK_MODEL_GEMINI}")${RESET}"
  gemf_hdr="${BOLD}${YELLOW}$(__ask_build_header "${ASK_NAME_FLASH}" "${ASK_DESC_FLASH}" "${ASK_MODEL_FLASH}")${RESET}"
  copilot_hdr="${BOLD}${BLUE}$(__ask_build_header "${ASK_NAME_COPILOT}" "${ASK_DESC_COPILOT}" "${ASK_MODEL_COPILOT}")${RESET}"
  claude_hdr="${BOLD}${MAGENTA}$(__ask_build_header "${ASK_NAME_CLAUDE}" "${ASK_DESC_CLAUDE}" "${ASK_MODEL_CLAUDE}")${RESET}"

  __ask_render_two_columns "$codex_hdr" "$codex_aug" "$gem_hdr" "$gem_aug" "⏱ Took ${d_codex}s" "⏱ Took ${d_gem}s"
  __ask_render_two_columns "$claude_hdr" "$claude_aug" "$copilot_hdr" "$copilot_aug" "⏱ Took ${d_claude}s" "⏱ Took ${d_copilot}s"
  __ask_render_two_columns "$gemf_hdr" "$gemf_aug" "" "/dev/null" "⏱ Took ${d_gemf}s" ""

  rm -f "$codex_out" "$gem_out" "$gemf_out" "$copilot_out" "$claude_out" "$codex_aug" "$gem_aug" "$gemf_aug" "$copilot_aug" "$claude_aug"
  # Final status line
  printf "%bDone:%b %bCodex%b ✓  %bGemini%b ✓  %bFlash%b ✓  %bClaude%b ✓\n" \
    "$BOLD" "$RESET" "$BLUE" "$RESET" "$CYAN" "$RESET" "$YELLOW" "$RESET" "$MAGENTA" "$RESET"
}
