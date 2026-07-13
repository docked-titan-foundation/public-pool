# Makefile
REGISTRY      := ghcr.io/docked-titan-foundation
IMAGE_NAME    := public-pool
VERSION       := v0.0.0.local
DEBUG         ?= 0

.PHONY: all build test precommit help commitlint hadolint

# Capture arguments after the target name for commitlint
COMMITLINT_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))

all: precommit

build: ## Build the Docker image locally
	@DEBUG=$(DEBUG) IMAGE_NAME=$(IMAGE_NAME) VERSION=$(VERSION) scripts/build.sh

test: build ## Boot the image and assert stratum + API + non-root
	@DEBUG=$(DEBUG) IMAGE_NAME=$(IMAGE_NAME) VERSION=$(VERSION) scripts/test.sh

precommit: ## Run pre-commit hooks
	pre-commit run --all-files

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

commitlint: ## Lint commit messages
	@npx commitlint --edit $(COMMITLINT_ARGS)

hadolint: ## Lint Dockerfile with hadolint
	@docker run --rm -i hadolint/hadolint < Dockerfile

# Consume any extra goals (filenames) passed by pre-commit
%:
	@true
