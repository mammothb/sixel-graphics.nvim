VUSTED := vusted

.PHONY: test
test:
	vusted

.PHONY: format
format:
	stylua --check .

.PHONY: lint
lint:
	selene .
