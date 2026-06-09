.PHONY: install uninstall list nightly help

help:
	@echo "make install    - install agents/skills/workflows into ~/.claude (all repos)"
	@echo "make uninstall  - remove the installed agents/skills/workflows from ~/.claude"
	@echo "make list       - list what is installed"
	@echo "make nightly    - run the nightly coding queue (QUEUE=... WORK_ROOT=...)"

install:
	@bash install.sh

uninstall:
	@DEST="$${CLAUDE_CONFIG_DIR:-$$HOME/.claude}"; \
	rm -f $$DEST/agents/orchestrator.md; \
	rm -rf $$DEST/agents/code $$DEST/agents/troubleshoot $$DEST/agents/research; \
	for s in terraform-troubleshooting kubernetes-troubleshooting node-npm-troubleshooting \
	         go-development python-scripting uat-testing multi-repo-workflow; do \
	  rm -rf $$DEST/skills/$$s; done; \
	rm -f $$DEST/workflows/multi-repo-feature.js $$DEST/workflows/troubleshoot-fanout.js; \
	echo "Removed installed components from $$DEST (settings.json left untouched)."

list:
	@DEST="$${CLAUDE_CONFIG_DIR:-$$HOME/.claude}"; \
	echo "Agents:";    find $$DEST/agents -name '*.md' 2>/dev/null | sed 's,.*/,  ,'; \
	echo "Skills:";    find $$DEST/skills -name 'SKILL.md' 2>/dev/null | sed 's,/SKILL.md,,;s,.*/,  ,'; \
	echo "Workflows:"; find $$DEST/workflows -name '*.js' 2>/dev/null | sed 's,.*/,  ,'

nightly:
	@bash scripts/nightly-code.sh $(QUEUE) $(WORK_ROOT)
