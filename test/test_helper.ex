defmodule DataDiode.TestHelper do
  @moduledoc """
  Helper module for test setup and teardown to prevent state pollution.
  """

  @doc """
  Restores Application environment to defaults after tests.
  Use this in on_exit callbacks to ensure clean state.
  """
  def restore_application_env(opts \\ []) do
    original_s1_port = Application.get_env(:data_diode, :s1_port)
    original_s2_port = Application.get_env(:data_diode, :s2_port)
    original_data_dir = Application.get_env(:data_diode, :data_dir)
    original_allowed_protocols = Application.get_env(:data_diode, :allowed_protocols)
    original_s1_ip = Application.get_env(:data_diode, :s1_ip)
    original_s2_ip = Application.get_env(:data_diode, :s2_ip)
    original_s2_udp_port = Application.get_env(:data_diode, :s2_port)

    on_exit(fn ->
      # Restore to safe defaults if original was nil
      Application.put_env(:data_diode, :s1_port, original_s1_port || 4000)
      Application.put_env(:data_diode, :s2_port, original_s2_port || 42_001)
      Application.put_env(:data_diode, :data_dir, original_data_dir || "./test_data")
      Application.put_env(:data_diode, :allowed_protocols, original_allowed_protocols || [:any])

      # Only restore IP if it was explicitly set
      if original_s1_ip do
        Application.put_env(:data_diode, :s1_ip, original_s1_ip)
      else
        Application.delete_env(:data_diode, :s1_ip)
      end

      if original_s2_ip do
        Application.put_env(:data_diode, :s2_ip, original_s2_ip)
      else
        Application.delete_env(:data_diode, :s2_ip)
      end
    end)
  end

  @doc """
  Ensures the application is started and returns a function to stop it.
  """
  def ensure_application_started do
    Application.ensure_all_started(:data_diode)
  end

  @doc """
  Generates a unique port for testing to avoid conflicts.
  """
  def unique_port(base \\ 45_000) do
    <<unique::32>> = :erlang.term_to_binary({self(), System.monotonic_time(:microsecond)})
    rem(base + unique, 10_000) + 45_000
  end

  @doc """
  Waits for a process to be registered.
  """
  def wait_for_registration(name, retries \\ 10) do
    do_wait_for_registration(name, retries)
  end

  defp do_wait_for_registration(_name, 0), do: {:error, :not_found}

  defp do_wait_for_registration(name, retries) do
    if Process.whereis(name) do
      :ok
    else
      Process.sleep(10)
      do_wait_for_registration(name, retries - 1)
    end
  end
end
