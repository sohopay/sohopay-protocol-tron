#!/usr/bin/env bash
# sohopay-terminal.sh
# Onchain Venmo-for-agents demo: onboard → @handle + $20 credit → natural-language pay.
#
#   sohopay
#   sohopay --reset
#   EXECUTE=1 sohopay    # isolated 20 USDC @phil Foundry fixture
#
# This shell does NOT authorize payments. On-chain settle remains the source of truth.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PAY_AGENT="$ROOT/scripts/a2a/pay-agent.mjs"
IDENTITY="$ROOT/scripts/a2a/identity.mjs"
EXECUTE="${EXECUTE:-0}"
CHAIN_ID="${EXPECTED_CHAIN_ID:-84532}"
NETWORK_NAME="${NETWORK_NAME:-Base Sepolia}"
TOKEN_SYMBOL="${TOKEN_SYMBOL:-USDC}"

USER_NAME=""
USER_HANDLE=""
USER_PHONE=""
USER_LABEL=""
USER_RECEIVE=""
CREDIT_LIMIT="20"
PER_TX_CAP="20"
OUTSTANDING="0"

hr() { printf '%s\n' "----------------------------------------------------------------"; }
sleepy() { sleep "${1:-0.35}"; }

init_colors() {
  C_BOLD="" C_CYAN="" C_BLUE="" C_DIM="" C_RESET="" C_GREEN="" C_RED=""
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_BOLD=$'\033[1m'
    C_CYAN=$'\033[96m'
    C_BLUE=$'\033[94m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_RESET=$'\033[0m'
  fi
}

ask() {
  local prompt="$1"
  local value=""
  if ! read -r -p "$prompt" value; then
    printf '\n'
    exit 0
  fi
  REPLY="$value"
}

is_quit_command() {
  local n
  n="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  [[ "$n" =~ ^(quit|exit|q|bye)$ ]]
}

is_help_command() {
  local n
  n="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  [[ "$n" =~ ^(help|h|\?)$ ]]
}

is_balance_query() {
  local n
  n="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  case "$n" in
    balance|credit|check\ balance|show\ balance|my\ credit|credit\ limit|whoami|me) return 0 ;;
  esac
  if printf '%s' "$n" | grep -Eqi '\bpay[[:space:]]+[0-9@]'; then return 1; fi
  if printf '%s' "$n" | grep -Eqi '(check|show|what).*(credit|balance|available|limit)'; then return 0; fi
  return 1
}

is_directory_query() {
  local n
  n="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  [[ "$n" =~ ^(people|contacts|directory|who)$ ]]
}

is_logout_command() {
  local n
  n="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  [[ "$n" =~ ^(logout|reset)$ ]]
}

json_field() {
  node -e 'const o=JSON.parse(process.argv[1]); const v=o[process.argv[2]]; process.stdout.write(v==null?"":String(v))' "$1" "$2"
}

load_identity() {
  local raw
  raw="$(node "$IDENTITY" whoami 2>/dev/null || true)"
  [[ -z "$raw" || "$raw" == "{}" ]] && raw='{"handle":"","name":"","phone":"","label":"","receiveAddress":"","creditLimit":"20","perTxCap":"20","outstanding":"0"}'
  USER_HANDLE="$(json_field "$raw" handle)"
  USER_NAME="$(json_field "$raw" name)"
  USER_PHONE="$(json_field "$raw" phone)"
  USER_LABEL="$(json_field "$raw" label)"
  USER_RECEIVE="$(json_field "$raw" receiveAddress)"
  CREDIT_LIMIT="$(json_field "$raw" creditLimit)"
  PER_TX_CAP="$(json_field "$raw" perTxCap)"
  OUTSTANDING="$(json_field "$raw" outstanding)"
  [[ -z "$CREDIT_LIMIT" ]] && CREDIT_LIMIT="20"
  [[ -z "$PER_TX_CAP" ]] && PER_TX_CAP="20"
  [[ -z "$OUTSTANDING" ]] && OUTSTANDING="0"
  return 0
}

credit_left() {
  awk -v l="$CREDIT_LIMIT" -v o="$OUTSTANDING" 'BEGIN{printf "%g", l-o}'
}

generate_otp() {
  if [[ -n "${SOHOPAY_DEMO_OTP:-}" ]]; then
    printf '%s' "$SOHOPAY_DEMO_OTP"
    return
  fi
  awk 'BEGIN{srand(); printf "%06d", int(rand()*1000000)}'
}

onboard() {
  init_colors
  printf '\n'
  printf '%sCreate your agent%s\n' "$C_BOLD" "$C_RESET"
  printf '%sSohoPay is onchain Venmo for agents. We issue a unique @handle and a $%s credit line.%s\n' \
    "$C_DIM" "$CREDIT_LIMIT" "$C_RESET"
  printf '%sPhone is for signup only — payments use @handle. Demo SMS, no real text.%s\n' "$C_DIM" "$C_RESET"
  printf '\n'

  local name phone code typed suggested handle claim
  name="${SOHOPAY_NAME:-}"
  phone="${SOHOPAY_PHONE:-}"
  handle="${SOHOPAY_HANDLE:-}"

  if [[ -z "$name" ]]; then
    ask "  Name: "
    name="$REPLY"
  else
    printf '  Name: %s\n' "$name"
  fi
  if [[ -z "$phone" ]]; then
    ask "  Phone: "
    phone="$REPLY"
  else
    printf '  Phone: %s\n' "$phone"
  fi
  if ! phone="$(node "$IDENTITY" phone "$phone")"; then
    printf '%sERROR:%s enter a valid phone number (10–15 digits).\n' "$C_RED" "$C_RESET"
    exit 1
  fi

  local otp masked
  otp="$(generate_otp)"
  masked="$(node -e 'const d=process.argv[1]; process.stdout.write(d.length<4?"••••":"••••"+d.slice(-4))' "$phone")"
  printf '\n  %sSMS (demo)%s to %s — code %s%s%s\n' "$C_DIM" "$C_RESET" "$masked" "$C_CYAN" "$otp" "$C_RESET"
  printf '  %sNo real text was sent. Enter the code above.%s\n' "$C_DIM" "$C_RESET"
  if [[ -n "${SOHOPAY_DEMO_OTP:-}" && -n "${SOHOPAY_NAME:-}" ]]; then
    code="$otp"
    printf '  Code: %s\n' "$code"
  else
    ask "  Code: "
    code="$REPLY"
  fi
  if [[ "$code" != "$otp" ]]; then
    printf '%sERROR:%s code did not match.\n' "$C_RED" "$C_RESET"
    exit 1
  fi

  if [[ -z "$handle" ]]; then
    suggested="$(node "$IDENTITY" suggest "$name")"
    printf '\n  Suggested handle: %s@%s%s\n' "$C_CYAN" "$suggested" "$C_RESET"
    ask "  Press enter to accept, or type another: "
    handle="${REPLY:-$suggested}"
    handle="${handle#@}"
  else
    handle="${handle#@}"
    printf '\n  Handle: @%s\n' "$handle"
  fi

  if ! claim="$(node "$IDENTITY" claim "$(node -e 'console.log(JSON.stringify({name:process.argv[1],phone:process.argv[2],handle:process.argv[3]}))' "$name" "$phone" "$handle")")"; then
    printf '%sERROR:%s could not create @%s.\n' "$C_RED" "$C_RESET" "$handle"
    exit 1
  fi
  load_identity

  printf '\n'
  printf '  %s●%s @%s is yours\n' "$C_GREEN" "$C_RESET" "$USER_HANDLE"
  printf '  %s●%s $%s SohoPay credit issued\n' "$C_GREEN" "$C_RESET" "$CREDIT_LIMIT"
  printf '  %s●%s Pay @phil (agent) or @acme (merchant) in plain English\n' "$C_GREEN" "$C_RESET"
  printf '\n'
}

banner() {
  init_colors
  local mode_label
  mode_label="$([[ "$EXECUTE" == "1" ]] && echo "live fixture" || echo "demo")"

  printf '\n'
  printf '%sWelcome to SohoPay%s\n' "$C_DIM" "$C_RESET"
  printf '\n'

  local line row=0
  while IFS= read -r line; do
    row=$((row + 1))
    case "$row" in
      3|4|5|6|7|8) printf '%s%s%s\n' "$C_CYAN$C_BOLD" "$line" "$C_RESET" ;;
      *)           printf '%s%s%s\n' "$C_DIM" "$line" "$C_RESET" ;;
    esac
  done <<'EOF'
╭────────────────────────────────────────────────────────────────────────────╮
│                                                                            │
│   ███████╗ ██████╗ ██╗  ██╗ ██████╗ ██████╗  █████╗ ██╗   ██╗              │
│   ██╔════╝██╔═══██╗██║  ██║██╔═══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝              │
│   ███████╗██║   ██║███████║██║   ██║██████╔╝███████║ ╚████╔╝               │
│   ╚════██║██║   ██║██╔══██║██║   ██║██╔═══╝ ██╔══██║  ╚██╔╝                │
│   ███████║╚██████╔╝██║  ██║╚██████╔╝██║     ██║  ██║   ██║                 │
│   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝   ╚═╝                 │
│                                                                            │
│       The Credit & Settlement Layer for Autonomous AI Agents               │
│                                                                            │
│             Onchain Venmo for agents · USDC · Base Sepolia                 │
│                                                                            │
╰────────────────────────────────────────────────────────────────────────────╯
EOF

  printf '\n'
  printf '%s  Command-line interface · Base Sepolia USDC · Agent Terminal%s\n' "$C_DIM" "$C_RESET"
  printf '\n'
  printf 'Agents pay agents (or merchants) with a unique @handle and a SohoPay credit line.\n'
  printf '%sExperimental A2A — not covered by the prior audit. Demo SMS is not a real text.%s\n' "$C_DIM" "$C_RESET"
  printf '\n'
  printf '  %s●%s Connected to %s (chain %s) · mode: %s\n' "$C_BLUE" "$C_RESET" "$NETWORK_NAME" "$CHAIN_ID" "$mode_label"
  if [[ -n "$USER_HANDLE" ]]; then
    printf '  %s⎇%s signed in as %s@%s%s · $%s credit · %s USDC left\n' \
      "$C_DIM" "$C_RESET" "$C_CYAN" "$USER_HANDLE" "$C_RESET" "$CREDIT_LIMIT" "$(credit_left)"
  fi
  printf '\n'
}

print_help() {
  printf 'Examples\n'
  printf '  pay @phil 20\n'
  printf '  Pay Phil'\''s agent $20\n'
  printf '  pay 6 usdc to @acme\n'
  printf '  pay 20 to 0x178905fE008BfD6B743406fcFDA01D98F68CF790\n'
  printf '  balance · people · logout · quit\n'
  printf '\n'
  printf '@%s per-tx cap is %s %s; credit line is %s %s.\n' "$USER_HANDLE" "$PER_TX_CAP" "$TOKEN_SYMBOL" "$CREDIT_LIMIT" "$TOKEN_SYMBOL"
}

prompt_input() {
  init_colors
  local compact="${1:-0}"
  if [[ "$compact" == "1" ]]; then
    printf '%sEnter a payment, or type %squit%s to exit.%s\n' "$C_DIM" "$C_CYAN" "$C_DIM" "$C_RESET"
    if ! read -r -p "> " RAW_PROMPT; then RAW_PROMPT="quit"; fi
    printf '\n'
    return
  fi
  printf '%s┌────────────────────────────────────────────────────────────────────────────┐%s\n' "$C_DIM" "$C_RESET"
  printf '%s│%s  Pay someone to get started.%s\n' "$C_DIM" "$C_RESET" "$C_DIM"
  printf '%s│%s  e.g. pay @phil 20 ·  Pay Phil'\''s agent $20 ·  pay @acme 6 ·  quit%s\n' "$C_DIM" "$C_RESET" "$C_DIM"
  printf '%s└────────────────────────────────────────────────────────────────────────────┘%s\n' "$C_DIM" "$C_RESET"
  printf '\n'
  if ! read -r -p "> " RAW_PROMPT; then RAW_PROMPT="quit"; fi
  printf '\n'
}

show_credit_balance() {
  load_identity
  local left
  left="$(credit_left)"
  printf '\nPHASE 1: CREDIT LOOKUP\n'
  hr
  printf 'Checking @%s spending policy...\n' "$USER_HANDLE"
  sleepy
  printf '  • payer         : @%s (%s)\n' "$USER_HANDLE" "$USER_NAME"
  printf '  • handle        : @%s\n' "$USER_HANDLE"
  printf '  • per-tx cap    : %s %s\n' "$PER_TX_CAP" "$TOKEN_SYMBOL"
  printf '  • credit line   : %s %s\n' "$CREDIT_LIMIT" "$TOKEN_SYMBOL"
  printf '  • outstanding   : %s %s\n' "$OUTSTANDING" "$TOKEN_SYMBOL"
  printf '  • available     : %s %s\n' "$left" "$TOKEN_SYMBOL"
  printf 'Lookup complete.\n'
  printf '%s\n' "================================================================"
}

show_directory() {
  printf '\nDirectory\n'
  hr
  printf '  • @phil   Phil Agent     agent (A2A receive)\n'
  printf '  • @acme   Acme Coffee    merchant\n'
  printf '  • @bob    Bob Agent      agent (no receive in this demo)\n'
  if [[ -n "$USER_HANDLE" ]]; then
    printf '  • @%-6s %s  you\n' "$USER_HANDLE" "$USER_NAME"
  fi
  printf '%sAmbiguous first names do not pay — use a unique @handle.%s\n' "$C_DIM" "$C_RESET"
}

parse_prompt() {
  node "$PAY_AGENT" "$RAW_PROMPT"
}

fake_hash() {
  local seed="$1"
  local hex
  hex="$(printf '%s' "$seed" | shasum -a 256 | awk '{print $1}')"
  echo "0x$hex"
}

process_turn() {
  local parsed recipient amount currency label receive handle role merchant agent
  if ! parsed="$(parse_prompt 2>/tmp/sohopay-parse.err)"; then
    printf '%sERROR:%s could not parse that payment.\n' "$C_RED" "$C_RESET"
    printf '  %s\n' "$(tr -d '\n' </tmp/sohopay-parse.err | tail -c 240)"
    printf '  Try: pay @phil 20\n'
    return 1
  fi

  recipient="$(json_field "$parsed" recipient)"
  amount="$(json_field "$parsed" amount)"
  currency="$(json_field "$parsed" currency)"
  label="$(json_field "$parsed" label)"
  receive="$(json_field "$parsed" receiveAddress)"
  handle="$(json_field "$parsed" handle)"
  role="$(json_field "$parsed" role)"
  merchant="$(json_field "$parsed" registeredMerchant)"
  agent="$(json_field "$parsed" registeredAgent)"
  [[ -z "$handle" ]] && handle="@$recipient"

  if [[ "$currency" != "USDC" ]]; then
    printf '%sERROR:%s this demo settles USDC, not %s.\n' "$C_RED" "$C_RESET" "$currency"
    return 1
  fi

  local intent
  if [[ "$merchant" == "true" ]]; then
    intent="PAY_MERCHANT"
  else
    intent="PAY_AGENT"
  fi

  printf '\nPHASE 1: NLP INTENT RECOGNITION\n'
  hr
  printf 'Interpreting user intent...\n'
  sleepy
  printf '  • intent        : %s\n' "$intent"
  printf '  • from          : @%s\n' "$USER_HANDLE"
  printf '  • asset         : %s\n' "$currency"
  printf '  • amount        : %s\n' "$amount"
  printf '  • payee         : %s\n' "$handle"
  printf '  • command       : "pay %s %s"\n' "$handle" "$amount"
  printf 'Parsing complete.\n'
  sleepy

  printf '\nPHASE 2: RECIPIENT RESOLUTION\n'
  hr
  printf 'Resolving %s through the SohoPay directory...\n' "$handle"
  sleepy

  if [[ "$recipient" == "$USER_HANDLE" || "$handle" == "@$USER_HANDLE" ]]; then
    printf '%sERROR:%s self-payment is blocked (@%s cannot pay @%s).\n' "$C_RED" "$C_RESET" "$USER_HANDLE" "$USER_HANDLE"
    return 1
  fi

  if [[ "$merchant" == "true" ]]; then
    printf '  • handle        : %s\n' "$handle"
    printf '  • merchant      : %s\n' "$label"
    printf '  • merchant id   : keccak256("%s")\n' "$(json_field "$parsed" merchantIdPreimage)"
    printf '  • IdentityRegistry : n/a (merchant payee)\n'
    printf '  • MerchantRegistry : YES (Active)\n'
    printf '  • payout        : %s\n' "$receive"
    printf 'Resolution complete.\n'
  elif [[ "$agent" == "true" ]]; then
    if [[ -z "$receive" ]]; then
      printf '  • handle        : %s\n' "$handle"
      printf '  • IdentityRegistry : YES\n'
      printf '\n%sERROR:%s %s has no receive address, so A2A cannot pay them.\n' "$C_RED" "$C_RESET" "$handle"
      printf '  Use: pay @phil 20\n'
      return 1
    fi
    printf '  • handle        : %s\n' "$handle"
    printf '  • agent         : %s\n' "$label"
    printf '  • agent id      : keccak256("%s")\n' "$(json_field "$parsed" agentIdPreimage)"
    printf '  • IdentityRegistry : YES (Active)\n'
    printf '  • MerchantRegistry : NO\n'
    printf '  • receive       : %s\n' "$receive"
    printf 'Resolution complete.\n'
  else
    printf '  • handle        : (raw address)\n'
    printf '  • IdentityRegistry : NOT a registered agent\n'
    printf '  • MerchantRegistry : NOT a registered merchant\n'
    printf '\n%sERROR:%s A2A pays a registered @handle, not an arbitrary EOA.\n' "$C_RED" "$C_RESET"
    printf '  Use: pay @phil 20\n'
    return 1
  fi
  sleepy

  load_identity
  local left
  left="$(credit_left)"

  printf '\nPHASE 3: SPENDING POLICY\n'
  hr
  printf 'Checking @%s credit line...\n' "$USER_HANDLE"
  sleepy
  printf '  • per-tx cap    : %s %s\n' "$PER_TX_CAP" "$TOKEN_SYMBOL"
  printf '  • credit line   : %s %s\n' "$CREDIT_LIMIT" "$TOKEN_SYMBOL"
  printf '  • available     : %s %s\n' "$left" "$TOKEN_SYMBOL"
  printf '  • requested     : %s %s\n' "$amount" "$TOKEN_SYMBOL"
  if awk -v a="$amount" -v c="$PER_TX_CAP" 'BEGIN{exit !(a+0 > c+0)}'; then
    printf '%sERROR:%s above per-transaction cap (%s > %s).\n' "$C_RED" "$C_RESET" "$amount" "$PER_TX_CAP"
    return 1
  fi
  if awk -v a="$amount" -v l="$left" 'BEGIN{exit !(a+0 > l+0)}'; then
    printf '%sERROR:%s insufficient SohoPay credit (%s requested, %s left).\n' "$C_RED" "$C_RESET" "$amount" "$left"
    return 1
  fi
  printf 'Policy checks passed.\n'
  sleepy

  printf '\nPHASE 4: SETTLEMENT\n'
  hr
  if [[ "$EXECUTE" == "1" ]]; then
    if [[ "$recipient" != "phil" ]] || awk -v a="$amount" 'BEGIN{exit !(a+0 != 20)}'; then
      printf '%sERROR:%s live fixture currently settles 20 USDC to @phil only.\n' "$C_RED" "$C_RESET"
      printf '  Re-run without EXECUTE=1, or type: pay @phil 20\n'
      return 1
    fi
    printf 'Submitting settleAgentToAgent (isolated local demo)...\n'
    sleepy
    if ! (cd "$ROOT" && ./scripts/a2a/run-base-a2a-demo.sh); then
      printf '%sERROR:%s settlement was not confirmed. Not claiming success.\n' "$C_RED" "$C_RESET"
      return 1
    fi
    node "$IDENTITY" debit "$amount" >/dev/null
    load_identity
  else
    local path_name
    if [[ "$merchant" == "true" ]]; then
      path_name="settleWithAttestation (agent → merchant)"
    else
      path_name="settleAgentToAgent (agent → agent)"
    fi
    printf 'Preparing %s...\n' "$path_name"
    printf '  • payer         : @%s EIP-712\n' "$USER_HANDLE"
    printf '  • attestation   : trusted CreditAttestation\n'
    printf '  • mode          : demo (no chain write)\n'
    sleepy
    printf 'Submitted.\n\n'
    printf 'Waiting for confirmation...\n'
    sleepy 0.6
    local tx
    tx="$(fake_hash "sohopay|$USER_HANDLE|$handle|$amount|$CHAIN_ID|$(date +%s)")"
    if ! node "$IDENTITY" debit "$amount" >/dev/null; then
      printf '%sERROR:%s credit debit failed. Not claiming success.\n' "$C_RED" "$C_RESET"
      return 1
    fi
    load_identity
    printf '  • tx_hash       : %s\n' "$tx"
    printf '  • explorer      : https://sepolia.basescan.org (demo)\n'
    printf '  • confirmations : 1/1\n'
    printf '%sConfirmed.%s\n' "$C_GREEN" "$C_RESET"
    printf '\nSettlement summary\n'
    printf '  • settled       : %s %s\n' "$amount" "$TOKEN_SYMBOL"
    printf '  • from          : @%s\n' "$USER_HANDLE"
    printf '  • to            : %s (%s)\n' "$handle" "$([[ "$merchant" == "true" ]] && echo "merchant" || echo "agent, not merchant")"
    printf '  • receive       : %s\n' "$receive"
    printf '  • your debt     : +%s %s (credit float → payee)\n' "$amount" "$TOKEN_SYMBOL"
    printf '  • credit left   : %s %s\n' "$(credit_left)" "$TOKEN_SYMBOL"
    printf '  • network       : %s (%s)\n' "$NETWORK_NAME" "$CHAIN_ID"
    printf '  • tx_hash       : %s\n' "$tx"
    if [[ "$merchant" == "true" ]]; then
      printf '\n%sSTATUS: MERCHANT PAYMENT SUCCESSFUL%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
    else
      printf '\n%sSTATUS: A2A PAYMENT SUCCESSFUL%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
    fi
    printf '%s\n' "================================================================"
  fi
}

main_loop() {
  local first_prompt=1
  if [[ "${1:-}" == "--reset" || "${1:-}" == "reset" ]]; then
    node "$IDENTITY" reset >/dev/null
    printf 'Identity cleared. Onboarding again.\n'
  fi

  load_identity
  banner
  if [[ -z "$USER_HANDLE" ]]; then
    onboard
    load_identity
  else
    printf '%sWelcome back, @%s%s · %s USDC credit left\n\n' "$C_CYAN" "$USER_HANDLE" "$C_RESET" "$(credit_left)"
  fi

  while true; do
    if [[ "$first_prompt" == "1" ]]; then
      prompt_input 0
      first_prompt=0
    else
      prompt_input 1
    fi
    if is_quit_command "$RAW_PROMPT"; then
      printf '\n%sGoodbye, @%s.%s\n' "$C_DIM" "$USER_HANDLE" "$C_RESET"
      exit 0
    fi
    [[ -z "${RAW_PROMPT//[[:space:]]/}" ]] && continue
    if is_help_command "$RAW_PROMPT"; then
      print_help
      continue
    fi
    if is_logout_command "$RAW_PROMPT"; then
      node "$IDENTITY" reset >/dev/null
      printf 'Logged out. Run sohopay again to create a new @handle.\n'
      exit 0
    fi
    if is_directory_query "$RAW_PROMPT"; then
      show_directory
      continue
    fi
    if is_balance_query "$RAW_PROMPT"; then
      show_credit_balance
      continue
    fi
    process_turn || true
  done
}

command -v node >/dev/null || { echo "error: node is required for the sohopay shell" >&2; exit 1; }
[[ -f "$PAY_AGENT" ]] || { echo "error: missing $PAY_AGENT" >&2; exit 1; }
[[ -f "$IDENTITY" ]] || { echo "error: missing $IDENTITY" >&2; exit 1; }

main_loop "${1:-}"
