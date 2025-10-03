defmodule DataDiode.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_diode,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Add configuration for releases
      releases: [
        data_diode: [
          # Ensure the application start logic handles env variables
          include_erts: true,
          include_src: false,
          # Define the target runtime environment
          # IMPORTANT: Change this to a secure, random string in production
          cookie: :a_secure_cookie
        ]
      ]
    ]
  end

  # Defines the application environment for OTP.
  def application do
    [
      mod: {DataDiode.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Defines the project dependencies.
  defp deps do
    [
      # Add any necessary dependencies here.
    ]
  end
end
