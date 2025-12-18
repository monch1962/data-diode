import Config

# In test mode, we use ephemeral ports (0) to avoid conflicts (eaddrinuse)
# when running tests in parallel or if the app is already running.
config :data_diode,
  s1_port: 0,
  s2_port: 0

config :logger, level: :debug
config :data_diode, :s2_port, 0
