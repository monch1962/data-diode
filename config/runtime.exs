import Config

# config/runtime.exs is executed for all environments, including releases.
# It is executed after compilation and before the system starts.

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
valid_protocols = MapSet.new([
  :any, :modbus, :dnp3, :mqtt, :snmp,
  :opcua, :iec104, :bacnet, :ethernet_ip
])

protocol_list =
  allowed_str
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.map(&String.downcase/1)
  |> Enum.map(fn protocol_str ->
    # Safely convert string to known atom, default to :any if unknown
    case protocol_str do
      "any" -> :any
      "modbus" -> :modbus
      "dnp3" -> :dnp3
      "mqtt" -> :mqtt
      "snmp" -> :snmp
      "opcua" -> :opcua
      "iec104" -> :iec104
      "bacnet" -> :bacnet
      "ethernet_ip" -> :ethernet_ip
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
