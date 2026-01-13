#!/bin/bash
# Setup script for Data Diode development environment
# This script installs dependencies and sets up pre-commit hooks

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up Data Diode development environment...${NC}"

# Check if Elixir is installed
if ! command -v elixir &> /dev/null; then
    echo -e "${YELLOW}⚠️  Elixir is not installed. Please install Elixir first.${NC}"
    echo "Visit: https://elixir-lang.org/install.html"
    exit 1
fi

echo -e "${GREEN}✓ Elixir is installed${NC}"

# Install Elixir dependencies
echo -e "${BLUE}📦 Installing Elixir dependencies...${NC}"
mix deps.get
echo -e "${GREEN}✓ Dependencies installed${NC}"

# Install npm dependencies for markdownlint (optional)
if command -v npm &> /dev/null; then
    echo -e "${BLUE}📦 Installing npm dependencies (for markdown linting)...${NC}"
    if [ -f "package.json" ]; then
        npm install
        echo -e "${GREEN}✓ npm dependencies installed${NC}"
    else
        echo -e "${YELLOW}⚠️  No package.json found, skipping npm setup${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  npm not found, markdown linting will be skipped${NC}"
fi

# Setup pre-commit hooks
echo -e "${BLUE}🔧 Setting up pre-commit hooks...${NC}"

# Create .git/hooks directory if it doesn't exist
mkdir -p .git/hooks

# Check if pre-commit hook already exists
if [ -f ".git/hooks/pre-commit" ]; then
    # Check if it's our hook
    if grep -q "Data Diode project" .git/hooks/pre-commit; then
        echo -e "${YELLOW}⚠️  Pre-commit hook already exists and will be updated${NC}"
    else
        # Backup existing hook
        cp .git/hooks/pre-commit .git/hooks/pre-commit.backup
        echo -e "${YELLOW}⚠️  Backed up existing pre-commit hook to .git/hooks/pre-commit.backup${NC}"
    fi
fi

# Copy pre-commit hook
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
echo -e "${GREEN}✓ Pre-commit hook installed${NC}"

# Create scripts directory if it doesn't exist
mkdir -p scripts

# Save pre-commit hook to scripts directory for version control
if [ -f "scripts/pre-commit" ]; then
    echo -e "${BLUE}📝 scripts/pre-commit already exists, skipping copy${NC}"
else
    cp .git/hooks/pre-commit scripts/pre-commit
    echo -e "${GREEN}✓ Pre-commit hook saved to scripts/pre-commit${NC}"
fi

# Run tests to verify setup
echo -e "${BLUE}🧪 Running tests to verify setup...${NC}"
if mix test > /dev/null 2>&1; then
    echo -e "${GREEN}✓ All tests pass!${NC}"
else
    echo -e "${YELLOW}⚠️  Some tests failed. Please check your setup.${NC}"
    echo "Run 'mix test' to see details."
fi

echo ""
echo -e "${GREEN}✅ Development environment setup complete!${NC}"
echo ""
echo -e "${BLUE}Quick start:${NC}"
echo "  mix test          # Run tests"
echo "  mix format        # Format code"
echo "  mix credo         # Code quality checks"
echo ""
echo -e "${BLUE}Pre-commit hooks will run automatically before each commit:${NC}"
echo "  ✓ Code formatting check"
echo "  ✓ Credo code quality"
echo "  ✓ Markdown linting (if available)"
echo "  ✓ Full test suite"
echo ""
echo -e "${YELLOW}To bypass pre-commit hooks (use sparingly):${NC}"
echo "  git commit --no-verify -m \"Commit message\""
echo ""
echo -e "${BLUE}For more information, see DEVELOPMENT.md${NC}"
