#!/usr/bin/env bats

setup() {
    load test_helper
}

@test "sort_extracted_urls: alphabetical sorts and deduplicates URLs" {
    input=$'https://z.example\nhttps://a.example\nhttps://z.example'

    run bash -c "printf '%s\n' '$input' | sort_extracted_urls alphabetical ''"

    assert_success
    assert_line --index 0 "https://a.example"
    assert_line --index 1 "https://z.example"
}

@test "sort_extraction_input: recency scans newest pane lines first" {
    input=$'https://old.example\nhttps://new.example'

    run bash -c "printf '%s\n' '$input' | sort_extraction_input recency"

    assert_success
    assert_line --index 0 "https://new.example"
    assert_line --index 1 "https://old.example"
}

@test "sort_extracted_urls: recency preserves newest-first order for default layout" {
    input=$'https://new.example\nhttps://old.example'

    run bash -c "printf '%s\n' '$input' | sort_extracted_urls recency ''"

    assert_success
    assert_line --index 0 "https://new.example"
    assert_line --index 1 "https://old.example"
}

@test "sort_extracted_urls: recency reverses order for reverse fzf layout" {
    input=$'https://new.example\nhttps://old.example'

    run bash -c "printf '%s\n' '$input' | sort_extracted_urls recency '--reverse'"

    assert_success
    assert_line --index 0 "https://old.example"
    assert_line --index 1 "https://new.example"
}

@test "recency pipeline positions duplicates by latest occurrence" {
    input=$'https://repeat.example\nhttps://other.example\nhttps://repeat.example'

    run bash -c "printf '%s\n' '$input' | sort_extraction_input recency | xre_extract | sort_extracted_urls recency ''"

    assert_success
    assert_line --index 0 "https://repeat.example"
    assert_line --index 1 "https://other.example"
}

@test "grep fallback positions duplicates by latest occurrence" {
    input=$'https://repeat.example\nhttps://other.example\nhttps://repeat.example'

    run bash -c "printf '%s\n' '$input' | sort_extraction_input recency | grep_extract | sort_extracted_urls recency ''"

    assert_success
    assert_line --index 0 "https://repeat.example"
    assert_line --index 1 "https://other.example"
}

@test "fzf_uses_reverse_layout: detects --layout=reverse" {
    run fzf_uses_reverse_layout "-w 100% --layout=reverse --multi"

    assert_success
}

@test "fzf_uses_reverse_layout: rejects default layout options" {
    run fzf_uses_reverse_layout "-w 100% --multi --no-preview"

    assert_failure
}
