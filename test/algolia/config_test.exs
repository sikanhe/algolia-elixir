defmodule Algolia.ConfigTest do
  use ExUnit.Case, async: true

  alias Algolia.Config

  test "inspect does not show the API key" do
    config = Config.new(application_id: "foo", api_key: "secret")

    refute inspect(config) =~ "secret"
  end
end
