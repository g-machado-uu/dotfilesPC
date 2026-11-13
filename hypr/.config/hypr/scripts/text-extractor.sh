#!/usr/bin/env bash
# Script by https://github.com/anshifmonz
#
# Grabs an area of the screen, runs it through tesseract and puts the text on
# the clipboard.
#
# The language used to be picked in a rofi menu here; the Quickshell OCR panel
# (SUPER + ALT + A -> "qs ipc call ocr toggle") does that now and passes the
# choice in with --lang. The language list itself still lives here, behind
# --list-langs, so the panel and this script can never disagree about what is
# installed.
#
#   text-extractor.sh                 capture with the default language
#   text-extractor.sh --lang deu      capture with a given language
#   text-extractor.sh --list-langs    print the installed languages and exit

set -Eeuo pipefail

PICKER_PID=""
SLURP_TIMEOUT=10
OCR_LANGUAGE=""
LIST_ONLY=0
DEPS=(grim slurp magick tesseract wl-copy timeout)

while (($#)); do
    case "$1" in
        --lang)
            OCR_LANGUAGE="${2:-}"
            shift 2
            ;;
        --lang=*)
            OCR_LANGUAGE="${1#--lang=}"
            shift
            ;;
        --list-langs)
            LIST_ONLY=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

die() { echo "Error: $*" >&2; exit 1; }
safe_kill() { [[ -n "${1:-}" ]] && kill "$1" 2>/dev/null || true; }
cleanup() { safe_kill "$PICKER_PID"; }
trap cleanup EXIT INT TERM

# Check dependencies
check_deps() {
  local missing_dependencies=()
  for dep in "${DEPS[@]}"; do command -v "$dep" >/dev/null 2>&1 || missing_dependencies+=("$dep"); done
  if (( ${#missing_dependencies[@]} > 0 )); then
    die "Missing dependencies: ${missing_dependencies[*]}"
  fi
}

# Check if command exists
_checkCommandExists() {
    cmd="$1"
    if ! command -v "$cmd" >/dev/null; then
        echo 1
        return
    fi
    echo 0
    return
}

# The language list is wanted on its own (by the OCR panel), so it is read
# before the capture dependencies are checked.

# Arch
if [[ $(_checkCommandExists "pacman") == 0 ]]; then
    OCR_LANGUAGE_LIST="$(pacman -Qq | grep -iE "tesseract-(ocr|data|langpack)*-" | awk -F '-' '{print $NF}')"
# Fedora
elif [[ $(_checkCommandExists "dnf") == 0 ]]; then
    OCR_LANGUAGE_LIST="$(dnf list --installed | grep -iE "tesseract-(ocr|data|langpack)*-" | awk -F '-' '{print $NF}')"
# Opensuse
else
    OCR_LANGUAGE_LIST="$(zypper se -i | grep -iE "tesseract-(ocr|data|langpack)*-" | awk -F '-' '{print $NF}')"
fi

# tesseract ships "osd" (orientation and script detection) as a data file, not
# a language: it is never something to recognise text with.
OCR_LANGUAGE_LIST="$(echo "$OCR_LANGUAGE_LIST" | grep -vx "osd" || true)"

if ((LIST_ONLY)); then
    echo "$OCR_LANGUAGE_LIST"
    exit 0
fi

check_deps

# Fall back to the only installed language, or to English.
if [[ -z "$OCR_LANGUAGE" ]]; then
    if [[ "$(echo "$OCR_LANGUAGE_LIST" | grep -c .)" == "1" ]]; then
        OCR_LANGUAGE="$(echo "$OCR_LANGUAGE_LIST" | tr -d '[:space:]')"
    else
        OCR_LANGUAGE="eng"
    fi
fi

hyprpicker -r -z &
PICKER_PID=$!
sleep 0.1 || true

REGION=$(timeout "$SLURP_TIMEOUT" slurp -b "#00000080" -c "#888888ff" -w 1) || die "No region selected (timeout or cancelled)"
[[ -z "$REGION" ]] && die "No region selected"
cleanup

grim -g "$REGION" - \
  | magick - -colorspace Gray -normalize -contrast-stretch 2% -sharpen 0x1.0 -resize 200% png:- \
  | tesseract - stdout -l $OCR_LANGUAGE --psm 6 \
  | wl-copy \
  || die "Failed to capture or process text"
