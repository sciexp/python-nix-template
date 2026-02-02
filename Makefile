# infra bootstrap makefile
#
# tl;dr:
#
# 1. Run 'make bootstrap' to install nix and direnv
# 2. Run 'make verify' to check the installation
# 3. Run 'make setup-user' to generate sops-nix age key
# 4. Run 'nix develop' to enter the development environment
# 5. Use 'just ...' to run tasks
#
# This Makefile handles bootstrap only. After this is complete,
# see the justfile for development and configuration tasks.

.DEFAULT_GOAL := help

#-------
##@ help
#-------

# based on "https://gist.github.com/prwhite/8168133?permalink_comment_id=4260260#gistcomment-4260260"
.PHONY: help
help: ## Display this help. (Default)
	@grep -hE '^(##@|[A-Za-z0-9_ \-]*?:.*##).*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; /^##@/ {print "\n" substr($$0, 5)} /^[A-Za-z0-9_ \-]*?:.*##/ {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

help-sort: ## Display alphabetized version of help (no section headings).
	@grep -hE '^[A-Za-z0-9_ \-]*?:.*##.*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; /^[A-Za-z0-9_ \-]*?:.*##/ {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

HELP_TARGETS_PATTERN ?= test
help-targets: ## Print commands for all targets matching a given pattern. Copy this example into your shell:
help-targets: ## Copy this example into your shell:
help-targets: ## eval "$(make help-targets HELP_TARGETS_PATTERN=bootstrap | sed 's/\x1b\[[0-9;]*m//g')"
	@make help-sort | awk '{print $$1}' | grep '$(HELP_TARGETS_PATTERN)' | xargs -I {} printf "printf '___\n\n{}:\n\n'\nmake -n {}\nprintf '\n'\n"

# catch-all pattern rule
#
# This rule matches any targets that are not explicitly defined in this
# Makefile. It prevents 'make' from failing due to unrecognized targets, which
# is particularly useful when passing arguments or targets to sub-Makefiles. The
# '@:' command is a no-op, indicating that nothing should be done for these
# targets within this Makefile.
#
%:
	@:

#-------
##@ bootstrap
#-------

.PHONY: bootstrap
bootstrap: ## Main bootstrap target that runs all necessary setup steps
bootstrap: install-nix install-direnv
	@printf "\nBootstrap of nix and direnv complete!\n\n"
	@printf "Next steps:\n\n"
	@printf "  1. Start a new shell session\n"
	@printf "  2. Run 'make verify' to check the installation\n"
	@printf "  3. Run 'make setup-user' to generate your age key for secrets\n"
	@printf "  4. Run 'nix develop' to enter the development environment\n"
	@printf "  5. Use 'just ...' to run tasks\n"
	@printf "\n"
	@printf "To auto-activate the dev environment on directory entry:\n"
	@printf "  - see https://direnv.net/docs/hook.html to add direnv to your shell\n"
	@printf "  - start a new shell session\n"
	@printf "  - 'cd' out and back into the project directory\n"
	@printf "  - allow direnv by running 'direnv allow'\n"

.PHONY: install-nix
install-nix: ## Install Nix using the Determinate Systems installer
	@echo "Installing Nix..."
	@if command -v nix >/dev/null 2>&1; then \
		echo "Nix is already installed."; \
	else \
		curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install; \
	fi

.PHONY: install-direnv
install-direnv: ## Install direnv using the official installation script
	@echo "Installing direnv..."
	@if command -v direnv >/dev/null 2>&1; then \
		echo "direnv is already installed."; \
	else \
		curl -sfL https://direnv.net/install.sh | bash; \
	fi
	@echo ""
	@echo "See https://direnv.net/docs/hook.html if you would like to add direnv to your shell"

#-------
##@ verify
#-------

.PHONY: verify
verify: ## Verify nix installation and environment setup
	@printf "\nVerifying installation...\n\n"
	@printf "Checking nix installation: "
	@if command -v nix >/dev/null 2>&1; then \
		printf "found at %s\n" "$$(command -v nix)"; \
		nix --version; \
	else \
		printf "not found\n"; \
		printf "Run 'make install-nix' to install nix\n"; \
		exit 1; \
	fi
	@printf "\nChecking nix flakes support: "
	@if nix flake --help >/dev/null 2>&1; then \
		printf "enabled\n"; \
	else \
		printf "not enabled\n"; \
		exit 1; \
	fi
	@printf "\nChecking direnv installation: "
	@if command -v direnv >/dev/null 2>&1; then \
		printf "found\n"; \
	else \
		printf "not found (optional but recommended)\n"; \
		printf "Run 'make install-direnv' to install\n"; \
	fi
	@printf "\nChecking flake validity: "
	@if nix flake metadata . >/dev/null 2>&1; then \
		printf "valid\n"; \
	else \
		printf "flake has errors\n"; \
		exit 1; \
	fi
	@printf "\nChecking required tools in devShell: "
	@if nix develop --command bash -c 'command -v just && command -v python && command -v uv && command -v pixi && command -v ruff' >/dev/null 2>&1; then \
		printf "just, python, uv, pixi, ruff available\n"; \
	else \
		printf "some tools missing from devShell\n"; \
		exit 1; \
	fi
	@printf "\nAll verification checks passed.\n\n"

#-------
##@ setup
#-------

.PHONY: setup-user
setup-user: ## Generate age key for sops-nix secrets
	@if [ -f "$$HOME/.config/sops/age/keys.txt" ]; then \
		printf "Age key already exists at $$HOME/.config/sops/age/keys.txt\n"; \
		printf "Public key: "; \
		grep 'public key:' "$$HOME/.config/sops/age/keys.txt" | awk '{print $$NF}'; \
	else \
		mkdir -p "$$HOME/.config/sops/age"; \
		nix develop --command age-keygen -o "$$HOME/.config/sops/age/keys.txt" 2>&1 | tee /dev/stderr; \
		printf "\nAge key generated. Share the public key above with the team.\n"; \
	fi

.PHONY: check-secrets
check-secrets: ## Verify you can decrypt shared secrets
	@if [ ! -f "$$HOME/.config/sops/age/keys.txt" ]; then \
		printf "No age key found. Run 'make setup-user' first.\n"; \
		exit 1; \
	fi
	@if [ -f secrets/shared.yaml ]; then \
		nix develop --command sops -d secrets/shared.yaml > /dev/null 2>&1 && \
		printf "Secrets decryption verified.\n" || \
		(printf "Cannot decrypt secrets. Your age key may not be registered.\n"; exit 1); \
	else \
		printf "No secrets/shared.yaml found. Secrets not yet configured for this project.\n"; \
	fi

#-------
##@ clean
#-------

.PHONY: clean
clean: ## Clean any temporary files or build artifacts
	@echo "Cleaning up..."
	@rm -rf result result-*
	@find . -type d -name "__pycache__" -exec rm -rf {} +
	@find . -type f -name "*.pyc" -delete
