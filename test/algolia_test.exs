defmodule AlgoliaTest do
  use ExUnit.Case, async: true

  import Algolia

  @indexes ["test_1", "test_2", "test_3"]

  setup_all do
    @indexes
    |> Enum.map(&clear_index/1)
    |> Enum.each(&wait/1)

    :timer.sleep(2000)
  end

  test "save one object, and then read it" do
    :random.seed(:erlang.timestamp)
    id = :random.uniform(1000000) |> to_string

    {:ok, %{"objectID" => object_id}} =
      save_object("test_1", %{}, id)
      |> wait

    :timer.sleep(1000)

    assert object_id == id
    assert {:ok, %{"objectID" => ^object_id}} = get_object("test_1", id)
  end

  test "search single index" do
    :random.seed(:erlang.timestamp)
    count = :random.uniform 10
    docs = Enum.map(1..count, &(%{id: &1, test: "search single index"}))
    save_objects("test_2", docs, id_attribute: :id) |> wait

    :timer.sleep(1000)

    {:ok, %{"hits" => hits1}} = search("test_2", "search single index")
    assert length(hits1) === count
  end

  test "search > 1 pages" do
    docs = Enum.map(1..40, &(%{id: &1, test: "search pages"}))
    save_objects("test_3", docs, id_attribute: :id) |> wait

    :timer.sleep(1000)

    {:ok, results = %{"hits" => hits, "page" => page}} =
      search("test_3", "search pages", page: 1)

    assert page == 1
    assert length(hits) === 20
  end

  test "search multiple indexes" do
    :random.seed(:erlang.timestamp)

    fixture_list =
      @indexes
      |> Enum.map(fn(index) -> Task.async(fn -> generate_fixtures_for_index(index) end) end)
      |> Enum.map(fn(task) -> Task.await(task, :infinity) end)

    :timer.sleep(1_000)

    queries = format_multi_index_queries("search multiple indexes", @indexes)
    {:ok, body} = search(queries)

    results = body["results"]

    for {index, count} <- fixture_list do
      hits =
        results
        |> Enum.find(fn(result) -> result["index"] == index end)
        |> Map.fetch!("hits")

      assert length(hits) == count
    end
  end

  defp generate_fixtures_for_index(index) do
    :random.seed(:erlang.timestamp)
    count = :random.uniform(3)

    objects = Enum.map(1..count, &(%{objectID: &1, test: "search multiple indexes"}))
    save_objects(index, objects) |> wait(3_000)

    {index, length(objects)}
  end

  defp format_multi_index_queries(query, indexes) do
    requests = Enum.map indexes, fn(index) ->
      %{indexName: index, params: "query=#{query}"}
    end
    %{ requests: requests }
  end
end
