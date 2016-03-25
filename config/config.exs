use Mix.Config

config :algolia,
  application_id: System.get_env("ALGOLIA_APPLICATION_ID"),
  api_key: System.get_env("ALGOLIA_API_KEY")
