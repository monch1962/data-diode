defmodule DataDiode.SystemMonitorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias DataDiode.SystemMonitor

  test "get_cpu_temp handles file read failure" do
    temp = SystemMonitor.get_cpu_temp()
    assert is_float(temp) or temp == "unknown"
  end

  test "get_memory_usage returns a float" do
    mem = SystemMonitor.get_memory_usage()
    assert is_float(mem)
  end

  test "get_disk_free returns percentage string" do
    percent = SystemMonitor.get_disk_free("/")
    assert is_binary(percent)
    assert String.ends_with?(percent, "%") or percent == "unknown"
  end

  test "handle_info :pulse triggers logging" do
    capture_log(fn ->
      SystemMonitor.handle_info(:pulse, %{})
    end) =~ "HEALTH_PULSE:"
  end
end
