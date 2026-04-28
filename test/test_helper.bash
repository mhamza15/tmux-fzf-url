PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export __FZF_URL_TESTING=1
source "$PROJECT_ROOT/fzf-url.sh"
export RG
export -f version_ge get_fzf_options reverse_lines fzf_uses_reverse_layout
export -f sort_extraction_input sort_extracted_urls validate_sort_by
export -f get_copy_cmd rg_extract rg_line strip_ansi
export PAT_URL PAT_GIT SUB_GIT PAT_WWW SUB_WWW PAT_IP SUB_IP PAT_GH SUB_GH
load 'libs/bats-support/load'
load 'libs/bats-assert/load'
