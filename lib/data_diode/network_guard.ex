defmodule DataDiode.NetworkGuard do
  @moduledoc """
  Network interface monitoring and automatic recovery for harsh environments.
  Handles network flapping, interface failures, and automatic reconfiguration.

  Features:
  - Monitors S1 and S2 network interfaces every 30 seconds
  - Detects network flapping (5+ state changes in 5 minutes)
  - Automatic interface recovery with configurable delays
  - ARP cache flushing on reconnection
  - Interface state tracking and alerting
  """

  use GenServer
  require Logger

  @interface_check_interval 30_000  # 30 seconds
  @flapping_threshold 5  # 5 state changes
  @flapping_window 300_000  # 5 minutes
  @flapping_penalty_delay 60_000  # 1 minute penalty when flapping detected

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Logger.info("NetworkGuard: Starting network interface monitoring")
    schedule_check()
    {:ok, %{history: [], interface_state: %{s1: :unknown, s2: :unknown}, flapping: false}}
  end

  @impl true
  def handle_info(:check_interfaces, state) do
    current_state = check_network_interfaces()

    new_state =
      state
      |> update_history(current_state)
      |> detect_flapping()
      |> handle_network_changes(current_state)

    schedule_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:recovery_ready, state) do
    Logger.info("NetworkGuard: Flapping penalty period over, attempting recovery")
    {:noreply, %{state | flapping: false}}
  end

  @doc """
  Manually check network interface status.
  """
  def check_network_interfaces do
    s1_interface = get_interface_status(:s1)
    s2_interface = get_interface_status(:s2)

    %{
      s1: s1_interface,
      s2: s2_interface,
      timestamp: System.system_time(:millisecond)
    }
  end

  # Interface status checking

  defp get_interface_status(:s1) do
    interface = Application.get_env(:data_diode, :s1_interface, "eth0")
    check_interface(interface)
  end

  defp get_interface_status(:s2) do
    interface = Application.get_env(:data_diode, :s2_interface, "eth1")
    check_interface(interface)
  end

  defp check_interface(interface) do
    # Use 'ip' command to check if interface is up
    case System.cmd("ip", ["link", "show", interface]) do
      {output, 0} ->
        up = String.contains?(output, "UP")
        lower_up = String.contains?(output, "LOWER_UP")
        carrier = String.contains?(output, "state UP")

        # Interface is truly up when all conditions are met
        %{up: up and lower_up and carrier, interface: interface}

      {output, _exit_code} ->
        # Interface doesn't exist or command failed
        Logger.warning("NetworkGuard: Cannot check interface #{interface}: #{String.trim(output)}")
        %{up: false, interface: interface}
    end
  end

  # History and flapping detection

  defp update_history(state, current_state) do
    entry = %{
      s1_up: current_state.s1.up,
      s2_up: current_state.s2.up,
      timestamp: current_state.timestamp
    }

    %{state | history: [entry | state.history]}
  end

  defp detect_flapping(state) do
    if state.flapping do
      # Already in flapping state
      state
    else
      recent = filter_recent_history(state.history, @flapping_window)

      # Count state changes for S1 and S2 separately
      s1_changes = count_state_changes(recent, :s1)
      s2_changes = count_state_changes(recent, :s2)

      max_changes = max(s1_changes, s2_changes)

      if max_changes > @flapping_threshold do
        Logger.error("NetworkGuard: Flapping detected! #{max_changes} changes in #{@flapping_window}ms")
        activate_flapping_protection(state)
      else
        state
      end
    end
  end

  defp filter_recent_history(history, window_ms) do
    cutoff = System.system_time(:millisecond) - window_ms
    Enum.filter(history, fn entry -> entry.timestamp > cutoff end)
  end

  defp count_state_changes(history, :s1) do
    count_transitions(history, fn entry -> entry.s1_up end)
  end

  defp count_state_changes(history, :s2) do
    count_transitions(history, fn entry -> entry.s2_up end)
  end

  defp count_transitions(history, getter) do
    history
    |> Enum.map(getter)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [a, b] -> a != b end)
  end

  defp activate_flapping_protection(state) do
    Logger.warning("NetworkGuard: Activating flapping protection - delaying recovery attempts")
    Process.send_after(self(), :recovery_ready, @flapping_penalty_delay)
    %{state | flapping: true}
  end

  # Network change handling

  defp handle_network_changes(state, current_state) do
    s1_changed = state.interface_state.s1 != (if current_state.s1.up, do: :up, else: :down)
    s2_changed = state.interface_state.s2 != (if current_state.s2.up, do: :up, else: :down)

    new_interface_state = %{
      s1: if(current_state.s1.up, do: :up, else: :down),
      s2: if(current_state.s2.up, do: :up, else: :down)
    }

    cond do
      # S1 went down
      s1_changed and not current_state.s1.up and state.interface_state.s1 == :up ->
        Logger.warning("NetworkGuard: S1 interface (#{current_state.s1.interface}) went down")
        if not state.flapping, do: attempt_interface_recovery(current_state.s1.interface)

      # S1 came back up
      s1_changed and current_state.s1.up and state.interface_state.s1 == :down ->
        Logger.info("NetworkGuard: S1 interface (#{current_state.s1.interface}) recovered")
        flush_arp_cache()

      # S2 went down
      s2_changed and not current_state.s2.up and state.interface_state.s2 == :up ->
        Logger.warning("NetworkGuard: S2 interface (#{current_state.s2.interface}) went down")
        if not state.flapping, do: attempt_interface_recovery(current_state.s2.interface)

      # S2 came back up
      s2_changed and current_state.s2.up and state.interface_state.s2 == :down ->
        Logger.info("NetworkGuard: S2 interface (#{current_state.s2.interface}) recovered")
        flush_arp_cache()

      true ->
        :ok
    end

    %{state | interface_state: new_interface_state}
  end

  defp attempt_interface_recovery(interface) do
    if Application.get_env(:data_diode, :auto_recovery_enabled, true) do
      Logger.info("NetworkGuard: Attempting to recover interface #{interface}")

      # Bring interface down
      System.cmd("ip", ["link", "set", interface, "down"])

      # Wait 2 seconds
      Process.sleep(2000)

      # Bring interface back up
      case System.cmd("ip", ["link", "set", interface, "up"]) do
        {_, 0} ->
          Logger.info("NetworkGuard: Interface #{interface} reset successfully")
          flush_arp_cache()

        {output, exit_code} ->
          Logger.error("NetworkGuard: Failed to reset interface #{interface}: #{String.trim(output)} (exit #{exit_code})")
      end
    else
      Logger.warning("NetworkGuard: Auto-recovery disabled, not attempting recovery")
    end
  end

  defp flush_arp_cache do
    Logger.debug("NetworkGuard: Flushing ARP cache")
    System.cmd("ip", ["neigh", "flush", "all"])
  end

  # Scheduling

  defp schedule_check do
    interval = Application.get_env(:data_diode, :network_check_interval, @interface_check_interval)
    Process.send_after(self(), :check_interfaces, interval)
  end
end
