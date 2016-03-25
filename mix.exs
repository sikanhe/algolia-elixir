defmodule Algolia.Mixfile do
  use Mix.Project

  def project do
    [app: :algolia,
     version: "0.3.0",
     description: "Elixir implementation of Algolia Search API",
     elixir: "~> 1.2",
     package: package,
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

     # Docs
     {:ex_doc, "~> 0.10", only: :docs},
     {:earmark, "~> 0.1", only: :docs},
     {:inch_ex, ">= 0.0.0", only: :docs}]
  end
end
