# Multi Agentic AI CLI (zsh)

Zsh functions to query multiple LLM CLIs in parallel:
- codex (OpenAI Codex CLI)
- gemini (Google Gemini CLI)
- gemini flash (2.0-flash-001)
- copilot (GitHub Copilot CLI)
- claude (Claude Code)

Features
- Parallel execution with a single spinner showing per-model status (⏳ → ✓)
- Inline timing (seconds) printed in headers
- Streaming `Ask` view and `AskColumns` two‑column summary (Codex|Gemini, Claude|Copilot, Flash solo)
- CLI‑first, customizable headers (names/descriptions) and optional model display

Getting Started
1. Source the script in `~/.zshrc`:
   `[[ -f "$HOME/Github/multi-agentic-ai-cli/scripts/zsh_ask.sh" ]] && source "$HOME/Github/multi-agentic-ai-cli/scripts/zsh_ask.sh"`
2. Ensure CLIs are installed and available on PATH: `codex`, `gemini`, `copilot`, `claude`.
3. Configure API keys and models via your environment.

Customization (env vars)
- Names/descriptions: `ASK_NAME_CODEX`, `ASK_DESC_CODEX`, `ASK_NAME_GEMINI`, `ASK_DESC_GEMINI`, `ASK_NAME_FLASH`, `ASK_DESC_FLASH`, `ASK_NAME_COPILOT`, `ASK_DESC_COPILOT`, `ASK_NAME_CLAUDE`, `ASK_DESC_CLAUDE`
- Models: `ASK_MODEL_CODEX`, `ASK_MODEL_GEMINI`, `ASK_MODEL_FLASH`, `ASK_MODEL_CLAUDE`
- Header format: `ASK_HEADER_FORMAT=cli` or `ASK_HEADER_FORMAT=cli_model`

Usage
- `Ask "Your prompt"` — live, parallel, spinner, per‑model blocks
- `AskColumns "Your prompt"` — two‑column summary with inline timings

Notes
- Timing uses file mtime minus start time (seconds).
- If a CLI is missing, its section may be blank; install and configure CLIs as needed.
