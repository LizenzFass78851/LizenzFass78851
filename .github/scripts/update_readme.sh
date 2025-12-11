#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Function: get_latest_success_url
# Returns environment_url for the latest successful Production deployment
# -----------------------------------------------------------------------------
get_latest_success_url() {
    local repo_url="$1"
    local owner_repo
    local api_deployments
    local candidate_ids
    local deployment_id
    local api_statuses
    local status
    local env_url

    # Parse owner/repo
    owner_repo="$(echo "$repo_url" \
        | sed -E 's#https://github\.com/([^/]+)/([^/]+)/.*#\1/\2#')"

    if [[ -z "$owner_repo" ]]; then
        echo "::warning::Could not parse owner/repo from '$repo_url'"
        return 1
    fi

    # Get all production deployments
    api_deployments="https://api.github.com/repos/$owner_repo/deployments"
    api_deployments="$(curl -fsSL -H "Authorization: token $GH_TOKEN" "$api_deployments")"

    if [[ -z "$api_deployments" ]]; then
        echo "::warning::No deployments found for $owner_repo"
        return 1
    fi

    # Get sorted list of Production deployment IDs (newest first)
    candidate_ids=($(echo "$api_deployments" \
        | jq -r '.[] | select(.environment=="Production") | [.id, .created_at] | @tsv' \
        | sort -r -k2 \
        | cut -f1))

    if [[ "${#candidate_ids[@]}" -eq 0 ]]; then
        echo "::warning::No Production deployments found in $owner_repo"
        return 1
    fi

    # Iterate through IDs to find the most recent one with success status
    for deployment_id in "${candidate_ids[@]}"; do

        api_statuses="https://api.github.com/repos/$owner_repo/deployments/$deployment_id/statuses"
        api_statuses="$(curl -fsSL -H "Authorization: token $GH_TOKEN" "$api_statuses")"

        # Check if any status is success
        status="$(echo "$api_statuses" | jq -r 'map(select(.state == "success")) | .[0].state // empty')"

        if [[ "$status" == "success" ]]; then
            # Get corresponding environment_url
            env_url="$(echo "$api_statuses" \
                | jq -r 'map(select(.state=="success" and .environment_url != null)) | .[0].environment_url // empty')"

            if [[ -n "$env_url" ]]; then
                echo "$env_url"
                return 0
            fi
        fi
    done

    echo "::warning::No successful Production deployment found for $owner_repo"
    return 1
}

# -----------------------------------------------------------------------------
# README operations
# -----------------------------------------------------------------------------
readme="README.md"

# Read the repo patterns
stats_repo="$(grep '\[stats-deployments\]:' "$readme" | awk '{print $2}')"
trophy_repo="$(grep '\[trophy-deployments\]:' "$readme" | awk '{print $2}')"

# Fetch URLs
stats_url="$(get_latest_success_url "$stats_repo" || true)"
trophy_url="$(get_latest_success_url "$trophy_repo" || true)"

# Replace only if a URL is found
if [[ -n "$stats_url" ]]; then
    sed -i -E "s#https://github-readme-stats-[^/]+\.vercel\.app#$stats_url#g" "$readme"
    echo "::notice::Updated stats URL -> $stats_url"
fi

if [[ -n "$trophy_url" ]]; then
    sed -i -E "s#https://github-profile-trophy-[^/]+\.vercel\.app#$trophy_url#g" "$readme"
    echo "::notice::Updated trophy URL -> $trophy_url"
fi
