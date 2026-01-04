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

  @type interface_status :: %{
          up: boolean(),
          interface: String.t()
        }

  @type interface_state :: :up | :down | :unknown

  @type network_status :: %{
          s1: interface_status(),
          s2: interface_status(),
          timestamp: integer()
        }

  @type history_entry :: %{
          s1_up: boolean(),
          s2_up: boolean(),
          timestamp: integer()
        }

  @type state :: %{
          history: [history_entry()],
          interface_state: %{s1: interface_state(), s2: interface_state()},
          flapping: boolean()
        }

  # 30 seconds
  @interface_check_interval 30_000
  # 5 state changes
  @flapping_threshold 5
  # 5 minutes
  @flapping_window 300_000
  # 1 minute penalty when flapping detected
  @flapping_penalty_delay 60_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  @spec init(:ok) :: {:ok, state()}
  def init(:ok) do
    Logger.info("NetworkGuard: Starting network interface monitoring")
    schedule_check()
    {:ok, %{history: [], interface_state: %{s1: :unknown, s2: :unknown}, flapping: false}}
  end

  @impl true
  @spec handle_info(:check_interfaces, state()) :: {:noreply, state()}
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
  @spec handle_info(:recovery_ready, state()) :: {:noreply, state()}
  def handle_info(:recovery_ready, state) do
    Logger.info("NetworkGuard: Flapping penalty period over, attempting recovery")
    {:noreply, %{state | flapping: false}}
  end

  @doc """
  Manually check network interface status.
  """
  @spec check_network_interfaces() :: network_status()
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
        Logger.warning(
          "NetworkGuard: Cannot check interface #{interface}: #{String.trim(output)}"
        )

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
        Logger.error(
          "NetworkGuard: Flapping detected! #{max_changes} changes in #{@flapping_window}ms"
        )

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
    s1_changed = state.interface_state.s1 != up_status(current_state.s1.up)
    s2_changed = state.interface_state.s2 != up_status(current_state.s2.up)

    new_interface_state = %{
      s1: up_status(current_state.s1.up),
      s2: up_status(current_state.s2.up)
    }

    # Handle interface state changes
    handle_interface_change(state, :s1, current_state.s1, s1_changed)
    handle_interface_change(state, :s2, current_state.s2, s2_changed)

    %{state | interface_state: new_interface_state}
  end

  defp up_status(true), do: :up
  defp up_status(false), do: :down

  defp handle_interface_change(state, interface_key, current_info, changed?) do
    previous_state = Map.get(state.interface_state, interface_key)
    current_state = up_status(current_info.up)

    cond do
      # Interface went down
      changed? and current_state == :down and previous_state == :up ->
        log_interface_down(interface_key, current_info.interface)
        maybe_attempt_recovery(state, current_info.interface)

      # Interface came back up
      changed? and current_state == :up and previous_state == :down ->
        log_interface_recovery(interface_key, current_info.interface)
        flush_arp_cache()

      true ->
        :ok
    end
  end

  defp log_interface_down(:s1, interface),
    do: Logger.warning("NetworkGuard: S1 interface (#{interface}) went down")

  defp log_interface_down(:s2, interface),
    do: Logger.warning("NetworkGuard: S2 interface (#{interface}) went down")

  defp log_interface_recovery(:s1, interface),
    do: Logger.info("NetworkGuard: S1 interface (#{interface}) recovered")

  defp log_interface_recovery(:s2, interface),
    do: Logger.info("NetworkGuard: S2 interface (#{interface}) recovered")

  defp maybe_attempt_recovery(state, interface) do
    unless state.flapping do
      attempt_interface_recovery(interface)
    end
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
          Logger.error(
            "NetworkGuard: Failed to reset interface #{interface}: #{String.trim(output)} (exit #{exit_code})"
          )
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
    interval =
      Application.get_env(:data_diode, :network_check_interval, @interface_check_interval)

    Process.send_after(self(), :check_interfaces, interval)
  end
end
