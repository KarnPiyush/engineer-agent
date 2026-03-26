#!/bin/bash
# Cache manager for engineer-agent
# Handles review result caching based on diff hash

set -euo pipefail

# ---------------------------------------------------------------------------
# Cache utilities
# ---------------------------------------------------------------------------

# get_cache_key DIFF PROMPT_TEMPLATE_VERSION
# Generates a cache key from diff and prompt version
get_cache_key() {
  local diff="$1"
  local prompt_version="${2:-v1}"
  
  local hash
  if command -v md5 >/dev/null 2>&1; then
    hash="$(echo "${prompt_version}${diff}" | md5 | cut -d' ' -f1)"
  elif command -v md5sum >/dev/null 2>&1; then
    hash="$(echo "${prompt_version}${diff}" | md5sum | cut -d' ' -f1)"
  else
    hash="$(date +%s)"
  fi
  
  echo "$hash"
}

# get_cache_path CACHE_KEY
# Returns the path to the cached review
get_cache_path() {
  local cache_key="$1"
  echo "${EA_CACHE_DIR}/review_${cache_key}.md"
}

# get_cached_review CACHE_KEY
# Returns cached review if exists and valid
get_cached_review() {
  local cache_key="$1"
  local cache_path
  cache_path="$(get_cache_path "$cache_key")"
  
  if [[ -f "$cache_path" ]]; then
    local cache_age
    cache_age="$(($(date +%s) - $(stat -f %m "$cache_path" 2>/dev/null || stat -c %Y "$cache_path" 2>/dev/null || echo "0")))"
    
    local max_age=86400
    if [[ "$cache_age" -lt "$max_age" ]]; then
      cat "$cache_path"
      return 0
    fi
  fi
  
  return 1
}

# save_review CACHE_KEY REVIEW_CONTENT
# Saves review to cache
save_review() {
  local cache_key="$1"
  local review_content="$2"
  local cache_path
  cache_path="$(get_cache_path "$cache_key")"
  
  echo "$review_content" > "$cache_path"
}

# clear_cache [AGE_SECONDS]
# Clears old cache entries
clear_cache() {
  local age_threshold="${1:-604800}"
  
  if [[ -d "$EA_CACHE_DIR" ]]; then
    find "$EA_CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Review caching wrapper
# ---------------------------------------------------------------------------

# get_cached_or_run_review DIFF PROMPT_TEMPLATE_VERSION REVIEW_PROMPT
# Returns cached review or runs the review and caches result
get_cached_or_run_review() {
  local diff="$1"
  local prompt_version="$2"
  local review_prompt="$3"
  
  local cache_key
  cache_key="$(get_cache_key "$diff" "$prompt_version")"
  
  local cached_review
  if cached_review="$(get_cached_review "$cache_key")"; then
    echo "$cached_review"
    return 0
  fi
  
  local review_result
  review_result="$(route_task "review" "$review_prompt" "$(echo "$diff" | wc -l)")"
  
  save_review "$cache_key" "$review_result"
  
  echo "$review_result"
}
