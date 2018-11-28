defmodule MusicCrypt.MixProject do
  use Mix.Project

  def project do
    [
      app: :music_crypt,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {MusicCrypt, []},
      extra_applications: [
        :ssl,
        :logger,
        :inets,
        :crypto,
        :elixium_core
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:local_dependency, path: "../elixium_core", app: false},
      {:decimal, "~> 1.0"},
      {:poison, "~> 3.1"}
    ]
  end
end
