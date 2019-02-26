defmodule Algolia.Paths do
  @moduledoc false

  @version 1

  def indexes, do: "/#{@version}/indexes"

  def multiple_queries(strategy) do
    params = strategy_params(strategy)
    indexes() <> "/*/queries" <> to_query(params)
  end

  defp strategy_params(:stop_if_enough_matches), do: [strategy: "stopIfEnoughMatches"]
  defp strategy_params(_), do: []

  def index(index), do: indexes() <> "/" <> URI.encode(index)

  def batch(index), do: index(index) <> "/batch"

  def operation(index), do: index(index) <> "/operation"

  def task(index, task_id), do: index(index) <> "/task/#{task_id}"

  def object(index, object_id), do: index(index) <> "/#{object_id}"

  def partial_object(index, object_id, upsert) do
    params = if upsert, do: [], else: [createIfNotExists: false]
    object(index, object_id) <> "/partial" <> to_query(params)
  end

  def search(index, query, opts) do
    params = Keyword.put(opts, :query, query)
    index(index) <> to_query(params)
  end

  def search_facet(index, facet) do
    index(index) <> "/facets/" <> URI.encode(facet) <> "/query"
  end

  def clear(index), do: index(index) <> "/clear"

  def delete_by(index), do: index(index) <> "/deleteByQuery"

  def settings(index, opts \\ []), do: index(index) <> "/settings" <> to_query(opts)

  def synonyms(index), do: index(index) <> "/synonyms"

  def search_synonyms(index), do: synonyms(index) <> "/search"

  def batch_synonyms(index, opts \\ []) do
    synonyms(index) <> "/batch" <> to_query(opts)
  end

  def rules(index), do: index(index) <> "/rules"

  def search_rules(index), do: rules(index) <> "/search"

  def batch_rules(index, opts \\ []) do
    rules(index) <> "/batch" <> to_query(opts)
  end

  def logs(opts \\ []) do
    "/#{@version}/logs" <> to_query(opts)
  end

  defp to_query([]), do: ""
  defp to_query(params), do: "?" <> build_query(params)

  defp build_query(params) do
    params
    |> Enum.map(&encode_param/1)
    |> URI.encode_query()
  end

  defp encode_param({key, value}), do: {key, encode_value(value)}

  defp encode_value(value) when is_list(value), do: Enum.join(value, ",")
  defp encode_value(value), do: value
end
