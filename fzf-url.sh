#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2218
#===============================================================================
#   Author: Wenxuan
#    Email: wenxuangm@gmail.com
#  Created: 2018-04-06 12:12
#===============================================================================
RG="${RG:-rg}"

version_ge() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# get_fzf_options keeps sorting and fzf invocation on the same option value.
get_fzf_options() {
    tmux show -gqv '@fzf-url-fzf-options'
}

# reverse_lines avoids tac so the plugin keeps the same behavior on macOS.
reverse_lines() {
    awk '{ lines[NR] = $0 } END { for (i = NR; i >= 1; i--) print lines[i] }'
}

# fzf_uses_reverse_layout detects layouts where the prompt is above the list.
fzf_uses_reverse_layout() {
    local fzf_options="$1"

    [[ " $fzf_options " == *" --reverse "* ]] && return 0
    [[ " $fzf_options " == *" --layout reverse "* ]] && return 0
    [[ " $fzf_options " == *" --layout=reverse "* ]] && return 0

    return 1
}

# sort_extraction_input lets extraction keep the latest duplicate URL for recency.
sort_extraction_input() {
    local sort_by="$1"

    if [[ "$sort_by" == "recency" ]]; then
        reverse_lines
    else
        cat
    fi
}

# sort_extracted_urls applies the requested display order after URL normalization.
sort_extracted_urls() {
    local sort_by="$1"
    local fzf_options="$2"

    case "$sort_by" in
        alphabetical)
            sort -u
            ;;

        recency)
            if fzf_uses_reverse_layout "$fzf_options"; then
                awk '!seen[$0]++' | reverse_lines
            else
                awk '!seen[$0]++'
            fi
            ;;

        *)
            echo "tmux-fzf-url: unsupported @fzf-url-sort-by value: $sort_by" >&2
            return 1
            ;;
    esac
}

# validate_sort_by rejects typos before they can create an empty fzf result.
validate_sort_by() {
    local sort_by="$1"

    case "$sort_by" in
        alphabetical | recency)
            return 0
            ;;

        *)
            return 1
            ;;
    esac
}

fzf_filter() {
    local fzf_version fzf_options copy_bind
    fzf_version="$(fzf --version 2>/dev/null | awk '{print $1}')"
    fzf_options="$(get_fzf_options)"
    copy_bind="ctrl-y:execute-silent(printf '%s\n' {+} | awk '{print \$2}' | $_copy_cmd)"

    if [ -n "$fzf_options" ]; then
        # Custom options are fzf-tmux flags — always use fzf-tmux
        eval "fzf-tmux $fzf_options --bind $(printf '%q' "$copy_bind")"
    elif version_ge "$fzf_version" "0.53.0"; then
        fzf --tmux center,100%,50% --multi --exit-0 --no-preview --bind "$copy_bind"
    else
        fzf-tmux -w 100% -h 50% --multi --exit-0 --no-preview --bind "$copy_bind"
    fi
}

open_url() {
    if [[ -n $custom_open ]]; then
        $custom_open "$@"
    elif [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSL_INTEROP:-} ]]; then
        if hash wslview &>/dev/null; then
            nohup wslview "$@"
        else
            nohup explorer.exe "$@"
        fi
    elif hash xdg-open &>/dev/null; then
        nohup xdg-open "$@"
    elif hash open &>/dev/null; then
        nohup open "$@"
    elif [[ -n $BROWSER ]]; then
        nohup "$BROWSER" "$@"
    fi
}

# Standard URLs
#   https://example.com/path?q=1
#   ftp://files.example.com/file.tar.gz
read -r PAT_URL <<'PATTERN'
(?:https?|ftp|file):/?//[-\w+&@#/%?=~|!:,.;]*[-\w+&@#/%=~|]
PATTERN

# Git SSH URLs
#   git@github.com:user/repo.git -> https://github.com/user/repo.git
#   ssh://git@github.com/user/repo.git -> https://github.com/user/repo.git
read -r PAT_GIT <<'PATTERN'
(?:ssh://)?git@([^\s'"`:]+)[:/]([^\s'"`]+)
PATTERN
SUB_GIT='https://$1/$2'

# Bare www domains
#   www.example.com -> http://www.example.com
#   www.example.com/path -> http://www.example.com/path
read -r PAT_WWW <<'PATTERN'
(?<!https://)(?<!http://)(?<!ftp://)(?<!file://)www\.[a-zA-Z](?:-?[a-zA-Z0-9])+\.[a-zA-Z]{2,}(?:/[^\s'"`]+)*
PATTERN
SUB_WWW='http://$0'

# IP addresses
#   192.168.1.1 -> http://192.168.1.1
#   10.0.0.1:8080/api -> http://10.0.0.1:8080/api
read -r PAT_IP <<'PATTERN'
\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?::\d{1,5})?(?:/[^\s'"`]+)*
PATTERN
SUB_IP='http://$0'

# GitHub shorthand
#   'user/repo' -> https://github.com/user/repo
#   "my-org/my-repo" -> https://github.com/my-org/my-repo
read -r PAT_GH <<'PATTERN'
['"]([\w-]+/[\w.-]+)['"]
PATTERN
SUB_GH='https://github.com/$1'

strip_ansi() {
    sed -E 's/\x1B\[[0-9;]*[mK]//g'
}

# rg_matches prefixes matches with line and column so pattern passes can merge.
rg_matches() {
    local content="$1"
    local pattern="$2"
    local replacement="${3:-}"

    if (($# >= 3)); then
        printf '%s\n' "$content" |
            "$RG" --color=never --no-heading --line-number --column --only-matching --pcre2 \
                --replace "$replacement" "$pattern" ||
            true
    else
        printf '%s\n' "$content" |
            "$RG" --color=never --no-heading --line-number --column --only-matching --pcre2 \
                "$pattern" ||
            true
    fi
}

# rg_extract keeps pane line order while using per-pattern URL normalization.
rg_extract() {
    local content custom_pat custom_sub

    while (($# > 0)); do
        case "$1" in
            -e)
                custom_pat="${2:-}"
                shift 2
                ;;

            -r)
                custom_sub="${2:-}"
                shift 2
                ;;

            *)
                shift
                ;;
        esac
    done

    content="$(strip_ansi)"

    {
        rg_matches "$content" "$PAT_URL"
        rg_matches "$content" "$PAT_GIT" "$SUB_GIT"
        rg_matches "$content" "$PAT_WWW" "$SUB_WWW"
        rg_matches "$content" "$PAT_IP" "$SUB_IP"
        rg_matches "$content" "$PAT_GH" "$SUB_GH"

        # Custom patterns use the same PCRE2 and replacement syntax as ripgrep.
        if [[ -n "$custom_pat" ]]; then
            if [[ -n "$custom_sub" ]]; then
                rg_matches "$content" "$custom_pat" "$custom_sub"
            else
                rg_matches "$content" "$custom_pat"
            fi
        fi
    } |
        sort -t: -k1,1n -k2,2n |
        cut -d: -f3- |
        awk '$0 != "" && !seen[$0]++'
}

get_copy_cmd() {
    local custom="$1"
    if [[ -n "$custom" ]]; then
        echo "$custom"
    elif [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && hash clip.exe &>/dev/null; then
        echo "clip.exe"
    elif hash pbcopy &>/dev/null; then
        echo "pbcopy"
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && hash wl-copy &>/dev/null; then
        echo "wl-copy"
    elif [[ -n "${DISPLAY:-}" ]] && hash xclip &>/dev/null; then
        echo "xclip -selection clipboard"
    elif [[ -n "${DISPLAY:-}" ]] && hash xsel &>/dev/null; then
        echo "xsel --clipboard --input"
    else
        echo "tmux load-buffer -"
    fi
}

# Source guard: when testing, stop here and don't execute main logic
[[ "${__FZF_URL_TESTING:-}" == 1 ]] && return 0 2>/dev/null || true

if ! command -v "$RG" &>/dev/null; then
    tmux display "tmux-fzf-url: ripgrep is required but was not found: $RG"
    exit 1
fi

limit=$1
custom_open=$2
custom_copy=$3
custom_pat=$4
custom_sub=$5
sort_by=${6:-alphabetical}
[[ -z "$limit" ]] && limit='screen'

if ! validate_sort_by "$sort_by"; then
    tmux display "tmux-fzf-url: unsupported @fzf-url-sort-by value: $sort_by"
    exit 1
fi

if [[ $limit == 'screen' ]]; then
    content="$(tmux capture-pane -J -p -e)"
else
    content="$(tmux capture-pane -J -p -e -S -"$limit")"
fi

custom_args=()
if [[ -n "$custom_pat" ]]; then
    custom_args+=(-e "$custom_pat")
    [[ -n "$custom_sub" ]] && custom_args+=(-r "$custom_sub")
fi

fzf_options="$(get_fzf_options)"

items=$(printf '%s\n' "$content" |
    sort_extraction_input "$sort_by" |
    rg_extract "${custom_args[@]}" |
    sort_extracted_urls "$sort_by" "$fzf_options" |
    nl -w3 -s '  ')

[ -z "$items" ] && tmux display 'tmux-fzf-url: no URLs found' && exit

_copy_cmd=$(get_copy_cmd "$custom_copy")

fzf_filter <<<"$items" | awk '{print $2}' |
    while read -r chosen; do
        open_url "$chosen" &>"/tmp/tmux-$(id -u)-fzf-url.log"
    done
