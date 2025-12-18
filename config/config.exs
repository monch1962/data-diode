import Config

# Main configuration for Data Diode
config :data_diode,
  s1_port: 8080,
  s2_port: 42001

# OT Hardening: Logger configuration for Raspberry Pi (protects SD card)
config :logger,
  level: :info, # Avoid :debug in production to reduce I/O
  handle_otp_reports: true,
  handle_sasl_reports: true

# Note: In a real production release (using mix release), 
# you would configure the console backend or a file backend with rotation.
# Example for console:
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides configuration defined above.
if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
