#!/usr/bin/env bash

# aws-alb-maintenance-page
# Copyright (C) 2026  Nicolas PELLEGRIN
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -Eeuo pipefail

# ALB configuration.
# !! EDIT THESE VALUES TO MATCH YOUR ENVIRONMENT.
readonly LISTENER_ARN=""
readonly AWS_REGION=""

# Script configuration
readonly BASE_RULE_PRIORITY=1
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly MAX_FIXED_RESPONSE_BYTES=1024

usage() {
    cat <<USAGE
Usage: $(basename "$0") <maintenance|sleep> <on|off>

Enable or disable the selected maintenance page on the configured ALB.
USAGE
}

error() {
    printf 'Error: %s\n' "$*" >&2
}

fail() {
    error "$*"
    exit 1
}

require_command() {
    local command_name=$1

    command -v "$command_name" >/dev/null 2>&1 || \
        fail "Required command not found: $command_name"
}

validate_variables() {
    [[ -n "$LISTENER_ARN" ]] || fail "LISTENER_ARN must be set."
    [[ -n "$AWS_REGION" ]] || fail "AWS_REGION must be set."
}

parse_arguments() {
    if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ $# -ne 2 ]]; then
        usage >&2
        exit 1
    fi

    MODE=$1
    ACTION=$2

    [[ $MODE == "maintenance" || $MODE == "sleep" ]] || \
        fail "Invalid mode '$MODE'."
    [[ $ACTION == "on" || $ACTION == "off" ]] || \
        fail "Invalid action '$ACTION'."
}

get_mode_file() {
    local extension=$1
    printf '%s/html/%s.%s' "$SCRIPT_DIR" "$MODE" "$extension"
}

minify_file() {
    local file_path=$1

    # ALB fixed responses are limited to 1,024 bytes and must be single-line.
    tr '\r\n\t' '   ' <"$file_path" |
        sed 's/  */ /g; s/> </></g; s/'"'"'/"/g'
}

validate_file_exists() {
    local file_path=$1

    [[ -f $file_path ]] || fail "File '$file_path' not found."
}

get_payload_size() {
    local content=$1
    printf '%s' "$content" | wc -c | tr -d '[:space:]'
}

validate_payload_size() {
    local content=$1
    local filename=$2
    local size

    size=$(get_payload_size "$content")
    (( size <= MAX_FIXED_RESPONSE_BYTES )) ||
        fail "$filename content is too large ($size bytes). The ALB limit is ${MAX_FIXED_RESPONSE_BYTES} bytes."

    printf '%s' "$size"
}

find_rule_arn() {
    local priority=$1

    aws elbv2 describe-rules \
        --listener-arn "$LISTENER_ARN" \
        --region "$AWS_REGION" \
        --query "Rules[?Priority=='${priority}'].RuleArn" \
        --output text
}

assert_priorities_are_available() {
    local priority rule_arn

    for priority in "$CSS_RULE_PRIORITY" "$HTML_RULE_PRIORITY"; do
        rule_arn=$(find_rule_arn "$priority" 2>/dev/null || true)
        if [[ -n $rule_arn && $rule_arn != "None" ]]; then
            fail "A rule already exists with priority $priority. ARN: $rule_arn. Disable the current mode first by running '$0 $MODE off'."
        fi
    done
}

create_fixed_response_rule() {
    local priority=$1
    local path_pattern=$2
    local message_body=$3
    local status_code=$4
    local content_type=$5

    aws elbv2 create-rule \
        --listener-arn "$LISTENER_ARN" \
        --region "$AWS_REGION" \
        --priority "$priority" \
        --conditions "Field=path-pattern,Values=$path_pattern" \
        --actions "Type=fixed-response,FixedResponseConfig={MessageBody='$message_body',StatusCode=$status_code,ContentType=$content_type}" \
        >/dev/null
}

enable_mode() {
    local html_file css_file html_content css_content html_size css_size

    html_file=$(get_mode_file html)
    css_file=$(get_mode_file css)
    validate_file_exists "$html_file"
    validate_file_exists "$css_file"

    html_content=$(minify_file "$html_file")
    css_content=$(minify_file "$css_file")
    html_size=$(validate_payload_size "$html_content" "${MODE}.html")
    css_size=$(validate_payload_size "$css_content" "${MODE}.css")

    assert_priorities_are_available
    create_fixed_response_rule "$CSS_RULE_PRIORITY" "/${MODE}.css" "$css_content" 200 text/css
    create_fixed_response_rule "$HTML_RULE_PRIORITY" '/*' "$html_content" 503 text/html

    printf '%s mode enabled (HTTP 503).\n' "$MODE"
    printf '%s\n' "- CSS payload:  $css_size/$MAX_FIXED_RESPONSE_BYTES bytes"
    printf '%s\n' "- HTML payload: $html_size/$MAX_FIXED_RESPONSE_BYTES bytes"
}

disable_mode() {
    local priority rule_arn
    local rules_removed=0

    for priority in "$CSS_RULE_PRIORITY" "$HTML_RULE_PRIORITY"; do
        rule_arn=$(find_rule_arn "$priority" 2>/dev/null || true)
        if [[ -n $rule_arn && $rule_arn != "None" ]]; then
            aws elbv2 delete-rule \
                --rule-arn "$rule_arn" \
                --region "$AWS_REGION"
            (( rules_removed += 1 ))
        fi
    done

    if (( rules_removed == 0 )); then
        printf '%s\n' "No rules found at defined priorities. Traffic is already flowing normally."
    else
        printf 'Disabled successfully. %d rules removed. Traffic is restored.\n' "$rules_removed"
    fi
}

main() {
    parse_arguments "$@"
    require_command aws
    validate_variables

    CSS_RULE_PRIORITY=$BASE_RULE_PRIORITY
    HTML_RULE_PRIORITY=$((BASE_RULE_PRIORITY + 1))

    if [[ $ACTION == "on" ]]; then
        printf '%s\n' "Enabling $MODE mode on the ALB..."
        enable_mode
    else
        printf '%s\n' "Disabling mode (removing rules)..."
        disable_mode
    fi
}

main "$@"
