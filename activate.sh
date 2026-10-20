# Activate the project venv and enable just tab completion (bash).
# Usage: source ./activate.sh
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Run this with: source ${0}" >&2
    exit 1
fi

_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$_project_dir/.venv" ]] && ! (cd "$_project_dir" && uv sync); then
    echo "uv sync failed; venv not activated" >&2
    unset _project_dir
    return 1
fi

source "$_project_dir/.venv/bin/activate"
eval "$(JUST_COMPLETE=bash just)"
# Marker for the justfile's `default` recipe: completion is registered in this shell.
export JUST_COMPLETION_REGISTERED=1
unset _project_dir

