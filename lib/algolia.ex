defmodule Algolia do
  @moduledoc """
  Elixir implementation of Algolia search API, using Hackney for http requests
  """

  defmodule MissingApplicationIDError do
    defexception message: """
      The `application_id` settings is required to use Algolia. Please include your
      application_id in your application config file like so:
        config :algilia, application_id: YOUR_APPLICATION_ID
      Alternatively, you can also set the secret key as an environment variable:
        ALGOLIA_APPLICATION_ID=YOUR_APP_ID
    """
  end

  defmodule MissingAPIKeyError do
    defexception message: """
      The `api_key` settings is required to use Algolia. Please include your
      api key in your application config file like so:
        config :algolia, api_key: YOUR_API_KEY
      Alternatively, you can also set the secret key as an environment variable:
        ALGOLIA_API_KEY=YOUR_SECRET_API_KEY
    """
  end

  def application_id do
    Application.get_env(:algolia, :application_id, System.get_env("ALGOLIA_APPLICATION_ID"))
    || raise MissingApplicationIDError
  end

  def api_key do
    Application.get_env(:algolia, :api_key, System.get_env("ALGOLIA_API_KEY"))
    || raise MissingAPIKeyError
  end

  defp host(:read, 0),
    do: "#{application_id()}-dsn.algolia.net"
  defp host(:write, 0),
    do: "#{application_id()}.algolia.net"
  defp host(_read_or_write, curr_retry) when curr_retry <= 3,
    do: "#{application_id()}-#{curr_retry}.algolianet.com"

  @doc """
  Multiple queries
  """
  def multi(queries, opts \\ [strategy: :none]) do
    strategy = opts[:strategy]

    params = case strategy do
      :none -> "?strategy=none"
      :stop_if_enough_matches -> "?strategy=stopIfEnoughMatches"
      _ -> ""
    end

    path = "*/queries" <> params
    body = Poison.encode! format_multi(queries)

    send_request(:read, :post, path, body)
  end

  defp format_multi(queries) do
    requests = Enum.map queries, fn(query) ->
      index_name = query[:index_name] || query["index_name"]

      if !index_name,
        do: raise ArgumentError, message: "Missing index_name for one of the multiple queries"

      params =
        query
        |> Map.delete(:index_name)
        |> Map.delete("index_name")
        |> format_multi_params

      %{indexName: index_name, params: params }
    end

    %{ requests: requests }
  end


  def format_multi_params(query) do
    query
    |> Stream.map(fn {k, v} ->
      "#{k}=#{v}"
    end)
    |> Enum.join("&")
    |> URI.encode
  end

  @doc """
  Search a single index
  """
  def search(index, query, opts) do
    path = "#{index}?query=#{query}" <> opts_to_query_params(opts)
    send_request(:read, :get, path)
  end
  def search(index, query), do: search(index, query, [])

  defp opts_to_query_params([]), do: ""
  defp opts_to_query_params(opts) do
    opts
    |> Stream.map(fn {key, value} ->
      "&#{key}=#{value}"
    end)
    |> Enum.join
    |> URI.encode
  end

  defp send_request(_, _, _, _, 4),
    do: {:error, "Unable to connect to Algolia"}
  defp send_request(read_or_write, method, path),
    do: send_request(read_or_write, method, path, "", 0)
  defp send_request(read_or_write, method, path, body),
    do: send_request(read_or_write, method, path, body, 0)
  defp send_request(read_or_write, method, path, body, curr_retry) do
    url =
      "https://"
      |> Path.join(host(read_or_write, curr_retry))
      |> Path.join("/1/indexes")
      |> Path.join(path)

    headers = [
      "X-Algolia-API-Key": api_key(),
      "X-Algolia-Application-Id": application_id()
    ]

    :hackney.request(method, url, headers, body, [
      :with_body,
      path_encode_fun: &(&1),
      connect_timeout: 3_000 * (curr_retry + 1),
      recv_timeout: 30_000 * (curr_retry + 1),
    ])
    |> case do
      {:ok, 200, _headers, body} ->
        {:ok, body |> Poison.decode!}
      {:ok, code, _, body} ->
        {:error, code, body}
      _ ->
        send_request(read_or_write, method, path, body, curr_retry + 1)
    end
  end

  @doc """
  Get an object in an index by objectID
  """
  def get_object(index, object_id) do
    path = "#{index}/#{object_id}"

    send_request(:read, :get, path)
    |> inject_index_into_response(index)
  end

  @doc """
  Add an Object
  """
  def add_object(index, object) do
    body = object |> Poison.encode!
    path = "#{index}"

    send_request(:write, :post, path, body)
    |> inject_index_into_response(index)
  end

  @doc """
  Add an object with an attribute as the objectID
  """
  def add_object(index, object, [id_attribute: id_attribute]) do
    save_object(index, object, [id_attribute: id_attribute])
  end

  @doc """
  Add multiple objects
  """
  def add_objects(index, objects) do
    objects
    |> build_batch_request("addObject")
    |> send_batch_request(index)
  end

  @doc """
  Add multiple objects, with an attribute as objectID
  """
  def add_objects(index, objects, [id_attribute: id_attribute]) do
    save_objects(index, objects, [id_attribute: id_attribute])
  end

  @doc """
  Save a single object, without objectID specified, must have objectID as
  a field
  """
  def save_object(index, object, [id_attribute: id_attribute]) do
    object_id = object[id_attribute] || object[to_string(id_attribute)]

    if !object_id do
      raise ArgumentError,
        message: "Your object #{object} does not have a attribute #{id_attribute}"
    end

    save_object(index, object, object_id)
  end

  def save_object(index, object, object_id) when is_map(object) do
    body = object |> Poison.encode!
    path = "#{index}/#{object_id}"

    send_request(:write, :put, path, body)
    |> inject_index_into_response(index)
  end

  def save_object(index, object) when is_map(object) do
    object_id = object["objectID"] || object[:objectID]
    if !object_id do
      raise ArgumentError,
        message: "Your object must have an objectID to be saved using save_object"
    end

    body = object |> Poison.encode!
    path = "#{index}/#{object_id}"

    send_request(:write, :put, path, body)
    |> inject_index_into_response(index)
  end

  @doc """
  Save multiple objects
  """
  def save_objects(index, objects, [id_attribute: id_attribute]) when is_list(objects) do
    objects
    |> add_object_ids(id_attribute: id_attribute)
    |> build_batch_request("updateObject")
    |> send_batch_request(index)
  end

  def save_objects(index, objects) when is_list(objects) do
    objects
    |> build_batch_request("updateObject")
    |> send_batch_request(index)
  end

  @doc """
  Partially updates an object, takes option upsert: true or false
  """
  def partial_update_object(index, object, object_id, opts \\ [upsert?: true]) do
    body = object |> Poison.encode!

    params = if opts[:upsert?] do
      ""
    else
      "?createIfNotExists=false"
    end

    path = "#{index}/#{object_id}/partial" <> URI.encode(params)

    send_request(:write, :post, path, body)
    |> inject_index_into_response(index)
  end

  @doc """
  Partially updates multiple objects
  """
  def partial_update_objects(index, objects, opts \\ [upsert?: true, id_attribute: :objectID]) do
    id_attribute = opts[:id_attribute] || :objectID

    upsert = case opts[:upsert?] do
      false -> false
      _ -> true
    end

    action = if upsert, do: "partialUpdateObject", else: "partialUpdateObjectNoCreate"

    objects
    |> add_object_ids(id_attribute: id_attribute)
    |> build_batch_request(action)
    |> send_batch_request(index)
  end

  # No need to add any objectID by default
  defp add_object_ids(objects, id_attribute: :objectID), do: objects
  defp add_object_ids(objects, id_attribute: "objectID"), do: objects
  defp add_object_ids(objects, id_attribute: attribute) do
    Enum.map(objects, fn(object) ->
      object_id = object[attribute] || object[to_string attribute]

      if !object_id do
        raise ArgumentError, message: "id attribute `#{attribute}` doesn't exist"
      end

      add_object_id(object, object_id)
    end)
  end

  defp add_object_id(object, object_id) do
    Map.put(object, :objectID, object_id)
  end

  defp get_object_id(object) do
    case object[:objectID] || object["objectID"] do
      nil -> {:error, "Not objectID found"}
      object_id -> {:ok, object_id}
    end
  end

  defp get_object_id!(object) do
    case get_object_id(object) do
      {:error, _} ->
        raise ArgumentError, message: "objectID doesn't exist"
      {:ok, object_id} -> object_id
    end
  end

  defp send_batch_request(requests, index) do
    path = "/#{index}/batch"
    body = requests |> Poison.encode!

    send_request(:write, :post, path, body)
    |> inject_index_into_response(index)
  end

  defp build_batch_request(objects, action) do
    requests = Enum.map objects, fn (object) ->
      case get_object_id(object) do
        {:ok, object_id} -> %{action: action, body: object, objectID: object_id}
        _ -> %{action: action, body: object}
      end
    end

    %{requests: requests}
  end

  @doc """
  Delete a object by its objectID
  """
  def delete_object(index, object_id) do
    path = "#{index}/#{object_id}"
    send_request(:write, :delete, path)
    |> inject_index_into_response(index)
  end

  @doc """
  Delete multiple objects
  """
  def delete_objects(index, object_ids) do
    object_ids
    |> Enum.map(fn (id) ->
      %{objectID: id}
    end)
    |> build_batch_request("deleteObject")
    |> send_batch_request(index)
  end

  @doc """
  List all indexes
  """
  def list_indexes do
    send_request(:read, :get, "")
  end

  @doc """
  Clears all content of an index
  """
  def clear_index(index) do
    path = "#{index}/clear"
    send_request(:write, :post, path)
    |> inject_index_into_response(index)
  end

  @doc """
  Set the settings of a index
  """
  def set_settings(index, settings) do
    body = settings |> Poison.encode!
    send_request(:write, :put, "/#{index}/settings", body)
    |> inject_index_into_response(index)
  end

  @doc """
  Get the settings of a index
  """
  def get_settings(index) do
    send_request(:read, :get, "/#{index}/settings")
    |> inject_index_into_response(index)
  end

  @doc """
  Moves an index to new one
  """
  def move_index(src_index, dst_index) do
    body = %{ operation: "move", destination: dst_index } |> Poison.encode!
    send_request(:write, :post, "/#{src_index}/operation", body)
    |> inject_index_into_response(src_index)
  end

  @doc """
  Copies an index to a new one
  """
  def copy_index(src_index, dst_index) do
    body = %{ operation: "copy", destination: dst_index } |> Poison.encode!
    send_request(:write, :post, "/#{src_index}/operation", body)
    |> inject_index_into_response(src_index)
  end

  ## Helps piping a response into wait_task, as it requires the index
  defp inject_index_into_response({:ok, body}, index) do
    {:ok, Map.put(body, "indexName", index)}
  end
  defp inject_index_into_response(response, index), do: response

  @doc """
  Wait for a task for an index to complete
  returns :ok when it's done
  """
  def wait_task(index, task_id, time_before_retry \\ 1000) do
    case send_request(:write, :get, "#{index}/task/#{task_id}") do
      {:ok, %{"status" => "published"}} -> :ok
      {:ok, %{"status" => "notPublished"}} ->
        :timer.sleep(time_before_retry)
        wait_task(index, task_id, time_before_retry)
      other -> other
    end
  end

  @doc """
  Convinient version of wait_task/4, accepts a response to be waited on
  directly. This enables piping a operation directly into wait_task
  """
  def wait(response = {:ok, %{"indexName" => index, "taskID" => task_id}}, time_before_retry) do
    with :ok <- wait_task(index, task_id, time_before_retry), do: response
  end
  def wait(response = {:ok, _}), do: wait(response, 1000)
  def wait(response = {:error, _}), do: response
  def wait(response), do: response
end
