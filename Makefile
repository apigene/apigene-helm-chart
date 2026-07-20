.PHONY: lint template test smoke integration test-local-cluster ci ci-chart ci-e2e

NAMESPACE ?= apigene
AUTH_SECRET ?= testsecret12345678901234567890123456789012
HELM_ARGS := --set auth.secretKey=$(AUTH_SECRET)

lint:
	helm lint chart/apigene $(HELM_ARGS)

template:
	helm template apigene chart/apigene -n $(NAMESPACE) $(HELM_ARGS)

smoke:
	BASE_URL=http://localhost:8080 ./scripts/smoke.sh

integration:
	BASE_URL=http://localhost:8080 ./tests/integration.sh

# Smoke + integration with auto port-forward (requires deployed release)
test:
	./scripts/run-tests.sh --port-forward

# Deploy to k3d and run full test suite (local CI)
test-local-cluster:
	./scripts/test-local-cluster.sh

# Mirror GitHub Actions CI locally
ci:
	./scripts/ci.sh all

ci-chart:
	./scripts/ci.sh chart

ci-e2e:
	./scripts/ci.sh e2e
