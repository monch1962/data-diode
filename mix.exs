defmodule DataDiode.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_diode,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        data_diode: [
          include_erts: true,
          include_src: false
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        release: :prod,
        test: :test
      ]
    ]
  end

  # Configuration for the OTP application
  # This function now correctly populates the :extra_applications list.
  def application do
    [
      mod: {DataDiode.Application, []},
      # Ensure all required applications, including OTel, are started
      extra_applications: [
        :logger,
        :runtime_tools,
        # For networking functions
        :inets,
        # For secure transport
        :ssl,
        # OTel depends on telemetry
        :opentelemetry_api,
        :opentelemetry_exporter,
        :opentelemetry
      ]
    ]
  end

  # Dependencies can be any of those defined in Hex, other Mix projects or git
  defp deps do
    [
      {:logger_json, "~> 5.0"},
      # OpenTelemetry Tracing Dependencies
      {:opentelemetry_api, "~> 1.0"},
      {:opentelemetry, "~> 1.0"},
      # Use the Exporter for console output and eventual external collection
      {:opentelemetry_exporter, "~> 1.0"},
      # Mox dependency for testing (fixed to run globally due to compile error)
      {:mox, "~> 1.0"}
    ]
  end
end
