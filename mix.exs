defmodule Algolia.Mixfile do
  use Mix.Project

  @source_url "https://github.com/sikanhe/algolia-elixir"
  @version "0.8.0"

  def project do
    [
      app: :algolia,
      version: @version,
      elixir: "~> 1.5",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def package do
    [
      description: "Elixir implementation of Algolia Search API",
      maintainers: ["Sikan He"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/algolia/changelog.html",
        "GitHub" => @source_url
      }
    ]
  end

  def application do
    [
      applications: [:logger, :hackney]
    ]
  end

  defp deps do
    [
      {:hackney, "~> 1.9 or ~> 1.10"},
      {:jason, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:inch_ex, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end
end
