import Config

# config/runtime.exs is executed for all environments, including releases.
# It is executed after compilation and before the system starts.

config :data_diode,
  listen_ip: System.get_env("LISTEN_IP", "127.0.0.1"),
  listen_ip_s2: System.get_env("LISTEN_IP_S2", "127.0.0.1"),
  data_dir: System.get_env("DATA_DIR", ".")

# Also keep s1_port/s2_port for backward compat if needed, but they are in config.exs
if s1_port = System.get_env("LISTEN_PORT") do
  config :data_diode, :s1_port, String.to_integer(s1_port)
end

if s2_port = System.get_env("LISTEN_PORT_S2") do
  config :data_diode, :s2_port, String.to_integer(s2_port)
end
