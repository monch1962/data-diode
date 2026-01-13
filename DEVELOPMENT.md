# Development Guide

This guide covers development practices, testing patterns, and contribution guidelines for the Data Diode project.

## Quick Start

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix test --cover

# Format code (run before commits)
mix format

# Check formatting without modifying
mix format --check-formatted

# Run code quality checks
mix credo --strict
```

## Pre-Commit Workflow

The project includes automated pre-commit hooks that run before every commit:

### What Gets Checked

1. **Code Formatting** (`mix format --check-formatted`)
   - Enforces consistent code style
   - Fails commit if code is not formatted
   - **Fix**: Run `mix format` and retry

2. **Credo Linting** (`mix credo --strict`)
   - Checks code quality and design issues
   - Warnings only (non-blocking)
   - **Review**: Address warnings to improve code quality

3. **Test Suite** (`mix test`)
   - Runs all 495 tests
   - Fails commit if any tests fail
   - **Fix**: Fix failing tests before committing

### Bypassing Pre-Commit Hooks

In rare cases where you need to bypass hooks:

```bash
git commit --no-verify -m "Commit message"
```

**Use sparingly** and only when you have a good reason (e.g., documentation-only commits).

## Testing Guidelines

### Test Organization

Tests are organized by category with appropriate tags:

- `@moduletag :chaos` - Chaos engineering tests (120s timeout)
- `@moduletag :concurrent` - Concurrent state tests (60s timeout)
- `@moduletag :shutdown` - Graceful shutdown tests (60s timeout)
- `@moduletag :property` - Property-based tests
- `@moduletag :test` - Standard tests (default)

### Running Specific Test Suites

```bash
# Run only chaos engineering tests
mix test --only chaos

# Run only concurrent state tests
mix test --only concurrent

# Run specific test file
mix test test/s1_encapsulator_test.exs

# Run specific test
mix test test/s1_encapsulator_test.exs:42
```

### Writing Tests

#### async:false Tests

For tests that:

- Modify Application environment
- Start/stop processes
- Use GenServer calls
- Check Process.whereis/1

**Always** add this setup block:

```elixir
setup do
  Application.ensure_all_started(:data_diode)
  :ok
end
```

This prevents race conditions and intermittent failures.

#### Application Environment Tests

When modifying Application environment, **always** clean up:

```elixir
setup do
  original = Application.get_env(:data_diode, :some_key)

  on_exit(fn ->
    # Restore to safe defaults
    Application.put_env(:data_diode, :some_key, original || :default)
  end)

  :ok
end
```

Never leave Application environment in an inconsistent state.

#### Process-Dependent Tests

When checking if a process exists:

```elixir
test "process is running" do
  # Ensure application is started
  Application.ensure_all_started(:data_diode)

  pid = Process.whereis(SomeModule)
  assert pid != nil
  assert Process.alive?(pid)
end
```

### Common Pitfalls

❌ **Don't** rely on default Application state

```elixir
# Bad - assumes application is started
test "checks process" do
  pid = Process.whereis(SomeModule)
  assert pid != nil  # Fails intermittently
end
```

✅ **Do** ensure application is started

```elixir
# Good - ensures application is started
setup do
  Application.ensure_all_started(:data_diode)
  :ok
end

test "checks process" do
  pid = Process.whereis(SomeModule)
  assert pid != nil  # Always passes
end
```

❌ **Don't** leave Application environment dirty

```elixir
# Bad - doesn't clean up
test "sets config" do
  Application.put_env(:data_diode, :port, "invalid")
  # Test breaks subsequent tests
end
```

✅ **Do** clean up in on_exit

```elixir
# Good - restores state
test "sets config" do
  original = Application.get_env(:data_diode, :port)

  Application.put_env(:data_diode, :port, "invalid")

  on_exit(fn ->
    Application.put_env(:data_diode, :port, original || 4000)
  end)
end
```

## Code Style Conventions

### Elixir Formatting

- Use `mix format` to format all code
- Configure in `.formatter.exs`
- Run `mix format --check-formatted` in CI/CD

### Credo Rules

- Run `mix credo` to check code quality
- Run `mix credo --strict` for enforcement
- Configuration in `.credo.exs`

### Type Specifications

Add `@spec` to all public functions:

```elixir
@spec encapsulate_and_send(String.t(), :inet.port_number(), binary()) :: :ok
def encapsulate_and_send(src_ip, src_port, payload) do
  # ...
end
```

### Documentation

Add `@moduledoc` to modules:

```elixir
@moduledoc """
  Encapsulates TCP packets with source metadata and forwards to Service 2.

  Implements protocol whitelisting via Deep Packet Inspection (DPI).
"""
```

Add `@doc` to public functions:

```elixir
@doc """
  Encapsulates data with source info and sends over UDP to Service 2.
"""
```

## Debugging Tips

### Check Application State

```elixir
# See if application is started
Application.started_applications() |> Keyword.key?(:data_diode)

# See where a process is registered
Process.whereis(DataDiode.SomeModule)

# Get GenServer state
:sys.get_state(pid)

# Get process info
Process.info(pid, :message_queue_len)
Process.info(pid, :dictionary)
```

### Trace GenServer Messages

```elixir
# Enable tracing
:sys.trace(pid, true)

# Disable tracing
:sys.trace(pid, false)
```

### View Registry Contents

```elixir
# See all registered processes
Registry.select(DataDiode.SomeRegistry, [{:_, :_, :_}])
```

## Performance Considerations

### UDP Packet Handling

- Default MTU is 1500 bytes
- Encapsulator limits packet size to 1MB
- CRC32 calculation on every packet (fast, Erlang built-in)

### Rate Limiting

- Connection rate limiting prevents DoS on accept loop
- Per-IP rate limiting prevents single-source floods
- Token bucket refill: `tokens = min(limit, tokens + elapsed_ms * limit / 1000)`

### Concurrent Processing

- S2.TaskSupervisor limited to 200 concurrent file operations
- TCP handlers are `:temporary` (not restarted) to prevent supervisor thrashing
- Use `Task.Supervisor.async_nolink/4` for fire-and-forget operations

## CI/CD Pipeline

The project uses GitHub Actions for CI/CD:

### .github/workflows/elixir.yml

- Runs on `ubuntu-22.04`
- Checks out code
- Installs Erlang/Elixir
- Installs dependencies (`mix deps.get`)
- Runs `mix format --check-formatted`
- Runs `mix credo --strict`
- Runs `mix test --cover`
- Uploads coverage reports

### Adding New Dependencies

1. Add to `mix.exs`:

```elixir
defp deps do
  [
    {:new_dep, "~> 1.0", only: :test}
  ]
end
```

1. Install: `mix deps.get`

2. Update documentation if needed

## Submitting Changes

1. **Update tests** for new features
2. **Run test suite**: `mix test`
3. **Format code**: `mix format`
4. **Check quality**: `mix credo --strict`
5. **Update documentation** if API changes
6. **Commit** with descriptive message
7. **Push** and create PR (if contributing)

### Commit Message Format

```text
[Category] Brief description

Detailed explanation of the change.

- Bullet points for specific changes
- Referenced issue numbers

Co-Authored-By: Your Name <email>
```

Categories:

- `[Feature]` - New functionality
- `[Fix]` - Bug fix
- `[Refactor]` - Code restructuring
- `[Test]` - Test improvements
- `[Docs]` - Documentation updates
- `[Chore]` - Maintenance tasks

## Getting Help

- **Documentation**: Check `CLAUDE.md` for AI development guidance
- **Tests**: Look at `test/` directory for usage examples
- **Issues**: File GitHub issues for bugs or feature requests
- **README**: See `README.md` for project overview

## Resources

- [Elixir Documentation](https://hexdocs.pm/elixir/)
- [OTP Design Principles](https://erlang.org/doc/design_principles/des_princ.html)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit/)
- [Credo Documentation](https://hexdocs.pm/credo/)
