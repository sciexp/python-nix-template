#!/usr/bin/env bash

set -euo pipefail

update_or_append() {
    local var_name=$1
    local var_value=$2
    local file=".env"

    if [ -f "$file" ] && [ "$(tail -c1 "$file"; echo x)" != $'\nx' ]; then
        echo >> "$file"
    fi

    if grep -q "^$var_name=" "$file"; then
        sed -i.bak "s/^$var_name=.*/$var_name=$var_value/" "$file"
    else
        echo "$var_name=$var_value" >> "$file"
    fi
}

GIT_REPO_NAME=$(basename -s .git $(git config --get remote.origin.url 2>/dev/null || echo "unknown-repo"))
update_or_append "GIT_REPO_NAME" "$GIT_REPO_NAME"

GIT_REF=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)
update_or_append "GIT_REF" "$GIT_REF"

GIT_SHA=$(git rev-parse HEAD)
update_or_append "GIT_SHA" "$GIT_SHA"

GIT_SHA_SHORT=$(git rev-parse --short HEAD)
update_or_append "GIT_SHA_SHORT" "$GIT_SHA_SHORT"
