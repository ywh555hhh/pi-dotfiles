#!/usr/bin/env bash
# Pi dotfiles installer — Mac / Linux
# Usage:  ./install.sh
# Env vars expected for API keys (export them before running):
#   DEEPSEEK_API_KEY, MINIMAX_API_KEY, VOLCANO_ARK_API_KEY

set -euo pipefail

DOT="$(cd "$(dirname "$0")" && pwd)"
PI_HOME="${HOME}/.pi/agent"

echo "==> pi dotfiles installer"
echo "    source: $DOT"
echo "    target: $PI_HOME"

# 1. Install pi itself if missing
if ! command -v pi >/dev/null 2>&1; then
	echo "==> pi not found. Installing globally via npm…"
	npm install -g --ignore-scripts @earendil-works/pi-coding-agent
fi

mkdir -p "$PI_HOME/agents"

# 2. agents/  (skills come in via the pi-package, but agents/ has no manifest support)
echo "==> copying agents/"
cp -v "$DOT"/agents/*.md "$PI_HOME/agents/"

# 3. Global AGENTS.md
echo "==> writing AGENTS.md"
cp -v "$DOT/config/AGENTS.md" "$PI_HOME/AGENTS.md"

# 4. settings.json  (skip if already exists — don't clobber)
if [ ! -f "$PI_HOME/settings.json" ]; then
	echo "==> installing fresh settings.json"
	# Inject this dotfiles repo as a local package so skills/ is loaded.
	python3 - "$DOT" "$PI_HOME/settings.json" <<'PY'
import json, sys, pathlib
dot, target = sys.argv[1], sys.argv[2]
tpl = json.loads(pathlib.Path(dot, "config/settings.template.json").read_text())
tpl.setdefault("packages", []).append(dot)   # load my-pi-dotfiles as a local package
pathlib.Path(target).write_text(json.dumps(tpl, indent=2))
PY
else
	echo "==> settings.json already exists, leaving it alone."
	echo "    To pick up skills, add this line to your packages array:"
	echo "      \"$DOT\""
fi

# 5. models.json — expand ${ENV_VAR} from the template
echo "==> rendering models.json (expanding env vars)"
python3 - "$DOT" "$PI_HOME/models.json" <<'PY'
import os, pathlib, re, sys
dot, target = sys.argv[1], sys.argv[2]
text = pathlib.Path(dot, "config/models.template.json").read_text()
def sub(m):
    key = m.group(1)
    val = os.environ.get(key, "")
    if not val:
        print(f"    !! WARN: env var {key} not set — leaving placeholder", file=sys.stderr)
        return m.group(0)
    return val
text = re.sub(r"\$\{([A-Z0-9_]+)\}", sub, text)
pathlib.Path(target).write_text(text)
PY

echo ""
echo "==> done."
echo "    Launch pi to auto-install npm packages declared in settings.json."
echo "    First run will fetch: pi-web-access, context-mode, pi-subagents, pi-mcp-adapter,"
echo "    pi-lens, pi-ask-user, pi-zhihu-search, and the mattpocock/skills git package."
