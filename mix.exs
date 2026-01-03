defmodule DataDiode.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_diode,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Dialyzer configuration
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [
          :error_handling,
          :race_conditions,
          :unmatched_returns,
          :underspecs
        ]
      ],
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
      # HTTP API for health monitoring (NEW for harsh environments)
      {:plug_cowboy, "~> 2.6"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      # Static analysis tools
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev], runtime: false},
      # Property-based testing
      {:stream_data, "~> 1.0", only: :test},
      # HTTP testing for HealthAPI
      {:bypass, "~> 2.1", only: :test, override: true},
      # Mox dependency for testing
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
