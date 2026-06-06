# my-pi-dotfiles

Personal [pi coding-agent](https://pi.dev) configuration: skills, agents, models, and settings.
Synced across Windows / Mac / Linux.

## Layout

| Path | What | How it's loaded on a new machine |
|------|------|---------------------------------|
| `skills/` | 11 personal skills (character-card, ghost-hero-*, sillytavern-dev, tavern2agent, …) | **Declarative** — loaded as a pi-package via `package.json` `pi.skills` |
| `agents/` | 3 drama sub-agents (`drama.afan.md` etc.) | Copied to `~/.pi/agent/agents/` by `install.sh` |
| `config/settings.template.json` | Default provider/model + npm package list | Copied to `~/.pi/agent/settings.json` |
| `config/models.template.json` | DeepSeek / MiniMax / Volcano-Ark with `${ENV}` placeholders | Rendered to `~/.pi/agent/models.json` |
| `config/AGENTS.md` | Global agent instructions | Copied to `~/.pi/agent/AGENTS.md` |
| `install.sh` | One-shot installer | `bash install.sh` |

The 7 community npm packages (`pi-web-access`, `context-mode`, `pi-subagents`,
`pi-mcp-adapter`, `pi-lens`, `pi-ask-user`, `pi-zhihu-search`) plus
`mattpocock/skills` are declared in `settings.json` → pi installs them
automatically on first launch.

## Bootstrap on a new Mac / Linux

```bash
git clone <this-repo> ~/pi-dotfiles
cd ~/pi-dotfiles

# Set your API keys (don't commit these)
export DEEPSEEK_API_KEY=sk-...
export MINIMAX_API_KEY=...
export VOLCANO_ARK_API_KEY=ark-...

bash install.sh
pi    # first launch auto-installs all npm/git packages
```

## On Windows

This repo lives at `C:\Users\<you>\pi-dotfiles\`. Use Git Bash / WSL to run `install.sh`,
or replicate its steps manually (cp + edit JSON).

## Security

- `auth.json` (subscription tokens) is **never** committed — pi recreates it on `/login`.
- API keys go through env vars; `models.template.json` only contains `${ENV_VAR}` placeholders.
- This repo should be **private** if you commit any real secrets.

## Notes

- `skills/tavern2agent/` was originally a `git clone` of <https://github.com/Xerxes-2/tavern2agent>; the inner `.git` was stripped so it stores as plain files inside this repo. If you want to track upstream updates, convert it to a git submodule instead.

## Updating from Windows → repo

Re-run the export step (or ask pi to do it):

```bash
cp ~/.pi/agent/skills/{character-card,codebase-analysis,...}/* skills/ -r
cp ~/.pi/agent/agents/drama.*.md agents/
# Re-export models.template.json by sed'ing your real keys back to ${ENV} placeholders
```
