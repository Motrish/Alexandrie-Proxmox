#!/usr/bin/env bats

setup() {
    # shellcheck disable=SC1091
    source "$BATS_TEST_DIRNAME/../assets/alexandrie/lib.sh"
}

@test "öffentliche HTTPS-URL wird akzeptiert" {
    run validate_public_url "https://alexandrie.example.org/"
    [ "$status" -eq 0 ]
}

@test "HTTP-URL wird abgelehnt" {
    run validate_public_url "http://alexandrie.example.org"
    [ "$status" -ne 0 ]
}

@test "Cookie-Domain enthält kein Schema oder Port" {
    run validate_cookie_domain "example.org"
    [ "$status" -eq 0 ]
    run validate_cookie_domain "https://example.org"
    [ "$status" -ne 0 ]
    run validate_cookie_domain "example.org:443"
    [ "$status" -ne 0 ]
}

@test "IPv4-CIDR wird validiert" {
    run validate_ipv4_cidr "192.168.1.20/24"
    [ "$status" -eq 0 ]
    run validate_ipv4_cidr "192.168.1.300/24"
    [ "$status" -ne 0 ]
}

@test "Dotenv-Werte werden quotiert" {
    result=$(dotenv_quote 'a$secret#with spaces')
    [ "$result" = '"a$$secret#with spaces"' ]
}
