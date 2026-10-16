.PHONY: help test install skill lint

help:
	@echo "make test     - run the e2e + unit test harness"
	@echo "make install  - chmod scripts"
	@echo "make skill    - install as a Claude Code skill (~/.claude/skills)"
	@echo "make lint     - syntax-check every script"

test:
	@bash tests/run.sh

install:
	@./install.sh

skill:
	@./install.sh --skill

lint:
	@python3 -m py_compile scripts/serve.py scripts/complete_mirror.py && echo "python ok"
	@bash -n scripts/grab.sh && bash -n scripts/mirror.sh && bash -n scripts/extract_copy.sh && echo "bash ok"
	@command -v node >/dev/null 2>&1 && node --check scripts/capture_playwright.js && echo "node ok" || echo "node not present (skipped)"
