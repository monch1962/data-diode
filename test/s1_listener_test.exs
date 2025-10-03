defmodule DataDiode.S1.ListenerTest do
  use ExUnit.Case, async: true
  alias DataDiode.S1.Listener

  # Use a module attribute to access the private function for testing purposes
  @resolve_port :resolve_listen_port

  setup do
    # Ensure no environment variables interfere with tests
    System.delete_env("LISTEN_PORT")
    :ok
  end

  test "resolves to default port when LISTEN_PORT is not set" do
    # Assuming @default_listen_port is 8080 or defined internally
    assert {:ok, 8080} = apply(Listener, @resolve_port, [])
  end

  test "resolves to specified port from environment variable" do
    System.put_env("LISTEN_PORT", "42000")
    assert {:ok, 42000} = apply(Listener, @resolve_port, [])
  end

  test "returns error for non-integer port" do
    System.put_env("LISTEN_PORT", "not_a_number")
    assert {:error, {:invalid_port, "not_a_number"}} = apply(Listener, @resolve_port, [])
  end

  test "returns error for zero port" do
    System.put_env("LISTEN_PORT", "0")
    assert {:error, {:invalid_port, "0"}} = apply(Listener, @resolve_port, [])
  end
end
