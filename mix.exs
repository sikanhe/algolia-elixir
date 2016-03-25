defmodule Algolia.Mixfile do
  use Mix.Project

  def project do
    [app: :algolia,
     version: "0.3.0",
     description: "Elixir implementation of Algolia Search API",
     elixir: "~> 1.2",
     package: package,
     test_coverage: [tool: ExCoveralls],
     deps: deps]
  end

  def package do
    [
      maintainers: ["Sikan He"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/sikanhe/algolia-elixir"}
    ]
  end

  def application do
    [applications: [:logger, :hackney]]
  end

  defp deps do
    [{:hackney, "~> 1.6.0"},
     {:poison, "~> 1.5"},
     {:excoveralls, "~> 0.5.1", only: :test},
     {:ex_doc, "~> 0.11", only: :dev},
     {:markdown, github: "devinus/markdown", only: :dev},
     {:earmark, "~> 0.2.1", only: :dev}]
  end
end
