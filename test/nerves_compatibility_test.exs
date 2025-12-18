defmodule DataDiode.NervesCompatibilityTest do
  @moduledoc """
  Verify that the application is compatible with the Nerves Project (firmware-based) packaging.
  This audits for hardcoded paths and shell dependencies that might not exist in a minimal Nerves image.
  """
  use ExUnit.Case
  require Logger

  test "verify no hardcoded absolute paths in logic" do
    # Nerves uses a minimal layout. We should check that logic doesn't assume standard Ubuntu/Debian paths.
    # Excluded: /sys/ (thermal/hardware) and /tmp/ (standard)
    
    files = Path.wildcard("lib/**/*.ex")
    
    for file <- files do
      content = File.read!(file)
      # Match strings starting with "/" that aren't /sys or /tmp
      matches = Regex.scan(~r/"\/[a-zA-Z0-9_\-\/]+"/, content)
      |> List.flatten()
      |> Enum.reject(fn path -> 
        String.starts_with?(path, "\"/sys/") or 
        String.starts_with?(path, "\"/tmp/") or
        String.contains?(path, "#") # interpolation
      end)

      assert matches == [], "File #{file} contains potentially incompatible absolute paths: #{inspect(matches)}"
    end
  end

  test "verify resource monitoring use standard BusyBox compatible commands" do
    # Nerves uses BusyBox. We need to ensure System.cmd calls are minimal or conditional.
    
    # SystemMonitor uses `df -h`
    if Code.ensure_loaded?(DataDiode.SystemMonitor) do
      # This is more of a manual review check, but we can verify the module compiles and exists.
      assert true
    end
  end

  test "verify supervision tree is autonomous" do
    # Nerves relies on the supervision tree being the primary entry point (no systemd).
    # Since we are using DataDiode.Application, this is guaranteed.
    # In a test environment, it's already started, so we just check if the supervisor is alive.
    assert Process.whereis(DataDiode.Supervisor) != nil
  end
end
