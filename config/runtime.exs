import Config

# config/runtime.exs is executed for all environments, including releases.
# It is executed after compilation and before the system starts.

# Basic configuration
config :data_diode,
  listen_ip: System.get_env("LISTEN_IP", "127.0.0.1"),
  listen_ip_s2: System.get_env("LISTEN_IP_S2", "127.0.0.1"),
  data_dir: System.get_env("DATA_DIR", ".")

# S1 Ports: Support both legacy LISTEN_PORT and specific LISTEN_PORT_TCP / LISTEN_PORT_UDP
s1_tcp_port = System.get_env("LISTEN_PORT_TCP") || System.get_env("LISTEN_PORT")

if s1_tcp_port do
  config :data_diode, :s1_port, String.to_integer(s1_tcp_port)
end

if s1_udp_port = System.get_env("LISTEN_PORT_UDP") do
  config :data_diode, :s1_udp_port, String.to_integer(s1_udp_port)
end

# S2 Port
if s2_port = System.get_env("LISTEN_PORT_S2") do
  config :data_diode, :s2_port, String.to_integer(s2_port)
end

# Parse PROTOCOL_ALLOW_LIST from env var (comma separated)
# Example: ALLOWED_PROTOCOLS="MODBUS,MQTT" -> [:modbus, :mqtt]
# Default: "ANY" -> [:any]
allowed_str = System.get_env("ALLOWED_PROTOCOLS", "ANY")

# Define valid protocol atoms to prevent atom table exhaustion
valid_protocols =
  MapSet.new([
    :any,
    :modbus,
    :dnp3,
    :mqtt,
    :snmp,
    :opcua,
    :iec104,
    :bacnet,
    :ethernet_ip
  ])

protocol_list =
  allowed_str
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.map(&String.downcase/1)
  |> Enum.map(fn protocol_str ->
    # Safely convert string to known atom, default to :any if unknown
    case protocol_str do
      "any" ->
        :any

      "modbus" ->
        :modbus

      "dnp3" ->
        :dnp3

      "mqtt" ->
        :mqtt

      "snmp" ->
        :snmp

      "opcua" ->
        :opcua

      "iec104" ->
        :iec104

      "bacnet" ->
        :bacnet

      "ethernet_ip" ->
        :ethernet_ip

      _ ->
        # Log warning for unknown protocol, default to allowing it as a string atom
        # but use try/rescue to safely create it
        try do
          String.to_existing_atom(protocol_str)
        rescue
          ArgumentError ->
            # Unknown protocol, log warning and skip
            :any
        end
    end
  end)

config :data_diode, :protocol_allow_list, protocol_list

# ============================================================================
# HARSH ENVIRONMENT CONFIGURATION
# ============================================================================

# These settings are optimized for unattended operation in extreme conditions:
# - Temperature: -20°C to +70°C ambient
# - Humidity: 10% to 90% (non-condensing)
# - No maintenance for months at a time
# - Remote/inaccessible locations

# Temperature thresholds (Celsius)
# Lower than standard (80°C) for safety in harsh conditions
config :data_diode,
  watchdog_max_temp: 75.0,
  cpu_temp_warning: 65.0,
  cpu_temp_critical_cold: -20,
  ambient_temp_max: 70.0,
  ambient_temp_min: 5.0

# Environmental sensor configuration
# Uncomment and configure if sensors are available:
# config :data_diode,
#   thermal_zone_path: "/sys/class/thermal/thermal_zone0/temp",
#   ambient_temp_sensor: %{type: :dht22, pin: 4},
#   humidity_sensor: %{type: :dht22, pin: 4},
#   storage_temp_sensor: %{type: :ds18b20, id: "28-00000..."}

# Power management
config :data_diode,
  ups_monitoring: :nut,
  nut_ups_name: "ups@localhost",
  power_supply_path: "/sys/class/power_supply/",
  ups_check_interval: 10_000

# Disk management (more aggressive for harsh environments)
config :data_diode,
  disk_cleaner_interval: 1_800_000,
  disk_cleanup_batch_size: 200,
  log_rotation_interval: 86_400_000,
  integrity_check_interval: 7_200_000

# Network resilience
config :data_diode,
  network_check_interval: 30_000,
  auto_recovery_enabled: true,
  s1_interface: System.get_env("S1_INTERFACE", "eth0"),
  s2_interface: System.get_env("S2_INTERFACE", "eth1")

# Memory management
config :data_diode,
  memory_check_interval: 300_000

# Rate limiting (reduced for stability)
config :data_diode,
  max_packets_per_sec: 500

# Health monitoring
config :data_diode,
  health_check_interval: 30_000,
  watchdog_interval: 5_000,
  heartbeat_interval: 120_000,
  heartbeat_timeout_ms: 360_000

# API configuration
# Generate secure token with: openssl rand -hex 32
config :data_diode,
  health_api_auth_token:
    System.get_env("HEALTH_API_TOKEN", "insecure_change_this_token_in_production")

# Alert file for power/environmental events
config :data_diode,
  alert_file: System.get_env("ALERT_FILE", "/var/log/data-diode/alerts.log")

# Log retention (increased for harsh environments)
config :data_diode,
  log_retention_days: 90
