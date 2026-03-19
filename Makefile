.DEFAULT_GOAL := help

.PHONY: help build test clean

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build the SDK
	swift build

test: ## Run tests
	swift test

test-integration: ## Run integration tests against real ingestor (requires LOGFLUX_API_KEY)
	swift test --filter Integration

clean: ## Clean build artifacts
	swift package clean
	rm -rf .build

publish-dry: ## Dry-run publish to public repo
	./scripts/publish.sh --dry-run

publish: ## Publish to public repo
	./scripts/publish.sh

publish-tag: ## Publish with tag (TAG=v1.2.3)
	@test -n "$(TAG)" || (echo "Usage: make publish-tag TAG=v1.2.3" && exit 1)
	./scripts/publish.sh --tag $(TAG)
