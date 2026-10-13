# Makefile

.PHONY: test-integration test-unit test-all setup clean

# Run integration tests
test-integration:
	@echo "?? Running integration tests..."
	flutter test integration_test/

# Run unit tests
test-unit:
	@echo "?? Running unit tests..."
	flutter test test/

# Run all tests
test-all: test-unit test-integration

# Setup test environment
setup:
	@echo "?? Setting up test environment..."
	flutter pub get
	flutter pub run build_runner build

# Clean build artifacts
clean:
	@echo "?? Cleaning build artifacts..."
	flutter clean
	flutter pub get

# Run tests with coverage
test-coverage:
	@echo "?? Running tests with coverage..."
	flutter test --coverage
	genhtml coverage/lcov.info -o coverage/html
