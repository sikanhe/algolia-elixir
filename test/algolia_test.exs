defmodule AlgoliaTest do
  use ExUnit.Case, async: true

  import Algolia

  @indexes [
    "test_1", "test_2", "test_3",
    "move_index_test_src", "move_index_test_dst",
    "copy_index_src", "copy_index_dst"
  ]

  setup_all do
    @indexes
    |> Enum.map(&clear_index/1)
    |> Enum.each(&wait/1)

    :timer.sleep(2000)
  end

  test "wait task" do
    :random.seed(:erlang.timestamp)
    id = :random.uniform(1000000) |> to_string
    {:ok, %{"objectID" => object_id, "taskID" => task_id}} =
      save_object("test_1", %{}, id)

    wait_task("test_1", task_id)

    assert {:ok, %{"objectID" => ^object_id}} = get_object("test_1", id)
  end

  test "save one object, and then read it, using wait_task pipeing" do
    :random.seed(:erlang.timestamp)
    id = :random.uniform(1000000) |> to_string

    {:ok, %{"objectID" => object_id}} =
      save_object("test_1", %{}, id)
      |> wait

    assert object_id == id
    assert {:ok, %{"objectID" => ^object_id}} = get_object("test_1", id)
  end

  test "search single index" do
    :random.seed(:erlang.timestamp)
    count = :random.uniform 10
    docs = Enum.map(1..count, &(%{id: &1, test: "search single index"}))

    {:ok, _} = save_objects("test_2", docs, id_attribute: :id)
    |> wait

    {:ok, %{"hits" => hits1}} = search("test_2", "search single index")
    assert length(hits1) === count
  end

  test "search > 1 pages" do
    docs = Enum.map(1..40, &(%{id: &1, test: "search pages"}))

    {:ok, _} = save_objects("test_3", docs, id_attribute: :id) |> wait

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

  test "partially update object" do
    {:ok, %{"objectID" => object_id}} =
      save_object("test_2", %{id: "partially_update_object"}, id_attribute: :id)
      |> wait

    assert {:ok, _} = partial_update_object("test_2", %{update: "updated"}, object_id) |> wait

    :timer.sleep(2_000)

    {:ok, object} = get_object("test_2", object_id)
    assert object["update"] == "updated"
  end


  test "partially update object, upsert true" do
    id = "partially_update_object_upsert_true"

    assert {:ok, _} =
      partial_update_object("test_2", %{}, id)
      |> wait

    :timer.sleep(2_000)

    {:ok, object} = get_object("test_2", id)
    assert object["objectID"] == id
  end


  test "partial update object, upsert is false" do
    id = "partial_update_upsert_false"

    assert {:ok, _} =
      partial_update_object("test_3", %{update: "updated"}, id, upsert?: false)
      |> wait

    :timer.sleep(2_000)

    assert {:error, 404, _} = get_object("test_3", id)
  end

  test "delete object" do
    {:ok, %{"objectID" => object_id}} =
      save_object("test_1", %{id: "delete_object"}, id_attribute: :id)
      |> wait

    delete_object("test_1", object_id) |> wait

    assert {:error, 404, _} = get_object("test_1", object_id)
  end

  test "delete multiple objects" do
    objects = [%{id: "delete_multipel_objects_1"}, %{id: "delete_multipel_objects_2"}]
    {:ok, %{"objectIDs" => object_ids}} =
      save_objects("test_1", objects, id_attribute: :id)
      |> wait

    delete_objects("test_1", object_ids) |> wait

    assert {:error, 404, _} = get_object("test_1", "delete_multipel_objects_1")
    assert {:error, 404, _} = get_object("test_1", "delete_multipel_objects_2")
  end

  test "settings" do
    :random.seed(:erlang.timestamp)
    attributesToIndex = :random.uniform(10000000)

    set_settings("test", %{ attributesToIndex: attributesToIndex})
    |> wait

    assert {:ok, %{ "attributesToIndex" => attributesToIndex}} = get_settings("test")
  end

  test "move index" do
    src = "move_index_test_src"
    dst = "move_index_test_dst"

    objects = [%{id: "move_1"}, %{id: "move_2"}]

    {:ok, _} = save_objects(src, objects, id_attribute: :id) |> wait
    {:ok, _} = move_index(src, dst) |> wait

    assert {:ok, %{"objectID" => "move_1"}} = get_object(dst, "move_1")
    assert {:ok, %{"objectID" => "move_2"}} = get_object(dst, "move_2")
  end

  test "copy index" do
    src = "copy_index_src"
    dst = "copy_index_dst"

    objects = [%{id: "copy_1"}, %{id: "copy_2"}]

    {:ok, _} = save_objects(src, objects, id_attribute: :id) |> wait
    {:ok, _} = copy_index(src, dst) |> wait

    assert {:ok, %{"objectID" => "copy_1"}} = get_object(dst, "copy_1")
    assert {:ok, %{"objectID" => "copy_2"}} = get_object(dst, "copy_2")
  end
end
