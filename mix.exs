defmodule DataDiode.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_diode,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      # 🚨 FIX: Removed external compilers that were causing the "task not found" error.
      compilers: Mix.compilers(),
      preferred_cli_env: [
        release: :prod,
        test: :test
      ],
      # 🚨 FINAL FIX: Changed conflicting :applications key back to standard :extra_applications.
      extra_applications: applications(),
      deps: deps(),
      releases: [
        data_diode: [
          include_erts: true,
          include_src: false
        ]
      ]
    ]
  end

  # Configuration for the OTP application
  # This function now correctly populates the :extra_applications list.
  defp applications do
    [
      :logger,
      :runtime_tools,
      :mox # Ensure Mox is loaded for test environment compilation
    ]
  end

  # Dependencies can be any of those defined in Hex, other Mix projects or git
  defp deps do
    [
      # 🚨 FINAL ATTEMPT FIX: Removing 'only:' to ensure Mox is compiled and available in all environments,
      # forcing the compiler to see the macros.
      {:mox, "~> 1.0"},
      # Add other dependencies here as needed
    ]
  end
end
