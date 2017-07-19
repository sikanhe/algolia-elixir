defmodule AlgoliaTest do
  use ExUnit.Case

  import Algolia

  @indexes [
    "test", "test_1", "test_2", "test_3",
    "multi_test_1", "multi_test_2",
    "move_index_test_src", "move_index_test_dst",
    "copy_index_src", "copy_index_dst"
  ]

  @settings_test_index "settings_test"

  setup_all do
    on_exit fn ->
      delete_index(@settings_test_index)
    end

    @indexes
    |> Enum.map(&clear_index/1)
    |> Enum.each(&wait/1)
  end

  test "add object" do
    {:ok, %{"objectID" => object_id}} =
      "test_1"
      |> add_object(%{text: "hello"})
      |> wait

    assert {:ok, %{"text" => "hello"}} =
      get_object("test_1", object_id)
  end

  test "add multiple objects" do
    assert {:ok, %{"objectIDs" => ids}} =
      "test_1"
      |> add_objects([%{text: "add multiple test"}, %{text: "add multiple test"}, %{text: "add multiple test"}])
      |> wait

    for id <- ids do
      assert {:ok, %{"text" => "add multiple test"}} =
        get_object("test_1", id)
    end
  end

  test "list all indexes" do
    assert {:ok, %{"items" => _items}} = list_indexes()
  end

  test "wait task" do
    :rand.seed(:exs1024, :erlang.timestamp)
    object_id = :rand.uniform(1000000) |> to_string
    {:ok, %{"objectID" => ^object_id, "taskID" => task_id}} =
      save_object("test_1", %{}, object_id)

    wait_task("test_1", task_id)

    assert {:ok, %{"objectID" => ^object_id}} = get_object("test_1", object_id)
  end

  test "save one object, and then read it, using wait_task pipeing" do
    :rand.seed(:exs1024, :erlang.timestamp)
    id = :rand.uniform(1000000) |> to_string

    {:ok, %{"objectID" => object_id}} =
      save_object("test_1", %{}, id)
      |> wait

    assert object_id == id
    assert {:ok, %{"objectID" => ^object_id}} = get_object("test_1", id)
  end

  test "search single index" do
    :rand.seed(:exs1024, :erlang.timestamp)
    count = :rand.uniform 10
    docs = Enum.map(1..count, &(%{id: &1, test: "search_single_index"}))

    {:ok, _} =  save_objects("test_3", docs, id_attribute: :id) |> wait

    {:ok, %{"hits" => hits1}} = search("test_3", "search_single_index")
    assert length(hits1) === count
  end

  test "search > 1 pages" do
    docs = Enum.map(1..40, &(%{id: &1, test: "search_more_than_one_pages"}))

    {:ok, _} = save_objects("test_3", docs, id_attribute: :id) |> wait

    {:ok, %{"hits" => hits, "page" => page}} =
      search("test_3", "search_more_than_one_pages", page: 1)

    assert page == 1
    assert length(hits) === 20
  end

  test "search multiple indexes" do
    :rand.seed(:exs1024, :erlang.timestamp)

    indexes = ["multi_test_1", "multi_test_2"]

    fixture_list = Enum.map(indexes, &generate_fixtures_for_index/1)

    {:ok, %{"results" => results}} =
      indexes
      |> Enum.map(&%{index_name: &1, query: "search_multiple_indexes"})
      |> multi()

    for {index, count} <- fixture_list do
      hits =
        results
        |> Enum.find(fn(result) -> result["index"] == index end)
        |> Map.fetch!("hits")

      assert length(hits) == count
    end
  end

  defp generate_fixtures_for_index(index) do
    :rand.seed(:exs1024, :erlang.timestamp)
    count = :rand.uniform(3)
    objects = Enum.map(1..count, &(%{objectID: &1, test: "search_multiple_indexes"}))
    save_objects(index, objects) |> wait(3_000)
    {index, length(objects)}
  end

  test "search query with special characters" do
    {:ok, %{"hits" => _}} = search("test_1", "foo & bar")
  end

  test "partially update object" do
    {:ok, %{"objectID" => object_id}} =
      save_object("test_2", %{id: "partially_update_object"}, id_attribute: :id)
      |> wait

    assert {:ok, _} = partial_update_object("test_2", %{update: "updated"}, object_id) |> wait



    {:ok, object} = get_object("test_2", object_id)
    assert object["update"] == "updated"
  end


  test "partially update object, upsert true" do
    id = "partially_update_object_upsert_true"

    assert {:ok, _} =
      partial_update_object("test_2", %{}, id)
      |> wait



    {:ok, object} = get_object("test_2", id)
    assert object["objectID"] == id
  end


  test "partial update object, upsert is false" do
    id = "partial_update_upsert_false"

    assert {:ok, _} =
      partial_update_object("test_3", %{update: "updated"}, id, upsert?: false)
      |> wait

    assert {:error, 404, _} = get_object("test_3", id)
  end

  test "partially update multiple objects, upsert is default" do
    objects = [%{id: "partial_update_multiple_1"}, %{id: "partial_update_multiple_2"}]

    assert {:ok, _} =
      partial_update_objects("test_3", objects, id_attribute: :id)
      |> wait

    assert {:ok, _} = get_object("test_3", "partial_update_multiple_1")
    assert {:ok, _} = get_object("test_3", "partial_update_multiple_2")
  end

  test "partially update multiple objects, upsert is false" do
    objects = [%{id: "partial_update_multiple_1_no_upsert"},
               %{id: "partial_update_multiple_2_no_upsert"}]

    assert {:ok, _} =
      partial_update_objects("test_3", objects, id_attribute: :id, upsert?: false)
      |> wait

    assert {:error, 404, _} = get_object("test_3", "partial_update_multiple_1_no_upsert")
    assert {:error, 404, _} = get_object("test_3", "partial_update_multiple_2_no_upsert")
  end

  test "delete object" do
    {:ok, %{"objectID" => object_id}} =
      save_object("test_1", %{id: "delete_object"}, id_attribute: :id)
      |> wait

    delete_object("test_1", object_id) |> wait

    assert {:error, 404, _} = get_object("test_1", object_id)
  end

  test "deleting an object with empty string should return an error" do
    assert {:error, %Algolia.InvalidObjectIDError{}} = delete_object("test", "")
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
    attributesToIndex = ~w(foo bar baz)

    assert {:ok, _} =
      @settings_test_index
      |> set_settings(%{attributesToIndex: attributesToIndex})
      |> wait
    assert {:ok, %{"attributesToIndex" => ^attributesToIndex}} = get_settings(@settings_test_index)
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

  test "deletes an index" do
    index = "delete_test_index"
    add_object(index, %{objectID: "delete_test"}) |> wait()

    {:ok, %{"items" => items}} = list_indexes()
    all_indexes = Enum.map(items, & &1["name"])
    assert index in all_indexes

    assert {:ok, _} = delete_index(index) |> wait()
    {:ok, %{"items" => items}} = list_indexes()
    all_indexes = Enum.map(items, & &1["name"])
    refute index in all_indexes
  end
end
