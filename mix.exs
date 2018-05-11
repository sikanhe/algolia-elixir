defmodule Algolia.Mixfile do
  use Mix.Project

  def project do
    [
      app: :algolia,
      version: "0.6.5",
      description: "Elixir implementation of Algolia Search API",
      elixir: "~> 1.5",
      package: package(),
      deps: deps(),
      docs: [extras: ["README.md"], main: "readme"]
    ]
  end

  def package do
    [
      maintainers: ["Sikan He"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/sikanhe/algolia-elixir"}
    ]
  end

  def application do
    [applications: [:logger, :hackney]]
  end

  defp deps do
    [
      {:hackney, "~> 1.9 or ~> 1.10"},
      {:poison, "~> 2.2 or ~> 3.0"},
      {:ex_doc, "~> 0.15", only: :docs},
      {:inch_ex, only: :docs}
    ]
  end
end
