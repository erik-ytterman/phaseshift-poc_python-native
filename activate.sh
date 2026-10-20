# Activate the project venv and enable just tab completion (bash).
# Usage: source ./activate.sh
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Run this with: source ${0}" >&2
    exit 1
fi

_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$_project_dir/.venv" ]]; then
    (cd "$_project_dir" && uv sync)
fi

source "$_project_dir/.venv/bin/activate"
eval "$(JUST_COMPLETE=bash just)"
unset _project_dir

