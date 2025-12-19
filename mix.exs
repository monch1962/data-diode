defmodule DataDiode.MixProject do
  use Mix.Project

  @target System.get_env("MIX_TARGET")

  def project do
    [
      app: :data_diode,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: [
        release: :prod,
        test: :test
      ],
      deps: deps(),
      releases: releases(),
      config_path: "config/config.exs"
    ]
  end

  def application do
    [
      mod: {DataDiode.Application, []},
      extra_applications: [
        :logger,
        :runtime_tools,
        :inets,
        :ssl,
        :opentelemetry_api,
        :opentelemetry_exporter,
        :opentelemetry
      ]
    ]
  end

  defp deps do
    [
      {:logger_json, "~> 5.0"},
      {:opentelemetry_api, "~> 1.0"},
      {:opentelemetry, "~> 1.0"},
      {:opentelemetry_exporter, "~> 1.0"},
      {:mox, "~> 1.0", only: :test}
    ] ++ nerves_deps()
  end

  defp nerves_deps do
    if @target do
      [
        {:nerves, "~> 1.10.0", runtime: false},
        {:nerves_bootstrap, "~> 1.13"},
        {:shoehorn, "~> 0.9.1"},
        {:vintage_net, "~> 0.13.0"},
        # Official Nerves Systems for Raspberry Pi
        {:nerves_system_rpi, "~> 1.25", runtime: false, targets: :rpi},
        {:nerves_system_rpi0, "~> 1.25", runtime: false, targets: :rpi0},
        {:nerves_system_rpi2, "~> 1.25", runtime: false, targets: :rpi2},
        {:nerves_system_rpi3a, "~> 1.25", runtime: false, targets: :rpi3a},
        {:nerves_system_rpi4, "~> 1.25", runtime: false, targets: :rpi4}
      ]
    else
      []
    end
  end

  defp releases do
    [
      data_diode: [
        include_erts: true,
        include_src: false
      ]
    ] ++ nerves_releases()
  end

  defp nerves_releases do
    if @target do
      [
        nerves: [
          include_erts: false,
          include_src: false,
          steps: [:assemble, &Nerves.Release.init/1, :tar]
        ]
      ]
    else
      []
    end
  end
end