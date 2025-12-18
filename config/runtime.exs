import Config

# config/runtime.exs is executed for all environments, including releases.
# It is executed after compilation and before the system starts.

if s1_port = System.get_env("LISTEN_PORT") do
  config :data_diode, :s1_port, String.to_integer(s1_port)
end

if s1_ip = System.get_env("LISTEN_IP") do
  config :data_diode, :s1_ip, s1_ip
end

if s2_port = System.get_env("LISTEN_PORT_S2") do
  config :data_diode, :s2_port, String.to_integer(s2_port)
end

if s2_ip = System.get_env("LISTEN_IP_S2") do
  config :data_diode, :s2_ip, s2_ip
end
