defmodule Algolia do
  @moduledoc """
  Elixir implementation of Algolia search API, using Hackney for http requests
  """

  alias Algolia.Config
  alias Algolia.Paths

  defmodule MissingApplicationIDError do
    defexception message: """
                   The `application_id` settings is required to use Algolia. Please include your
                   application_id in your application config file like so:
                     config :algolia, application_id: YOUR_APPLICATION_ID
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

  defmodule InvalidObjectIDError do
    defexception message: "The ObjectID cannot be an empty string"
  end

  defdelegate application_id, to: Algolia.Config, as: :application_id_from_env!

  defdelegate api_key, to: Algolia.Config, as: :api_key_from_env!

  @type config_opt :: {:config, Config.t()}

  @doc """
  Multiple queries
  """
  def multi(queries, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    path = Paths.multiple_queries(opts[:strategy])
    body = queries |> format_multi() |> Jason.encode!()

    send_request(config, :read, %{
      method: :post,
      path: path,
      body: body,
      options: opts[:request_options]
    })
  end

  defp format_multi(queries) do
    requests =
      Enum.map(queries, fn query ->
        index_name = query[:index_name] || query["index_name"]

        if !index_name,
          do: raise(ArgumentError, message: "Missing index_name for one of the multiple queries")

        params =
          query
          |> Map.delete(:index_name)
          |> Map.delete("index_name")
          |> URI.encode_query()

        %{indexName: index_name, params: params}
      end)

    %{requests: requests}
  end

  @doc """
  Search a single index
  """
  def search(index, query, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    {request_options, opts} = Keyword.pop(opts, :request_options)

    path = Paths.search(index, query, opts)

    send_request(config, :read, %{method: :get, path: path, options: request_options})
  end

  @doc """
  Search for facet values

  Enables you to search through the values of a facet attribute, selecting
  only a **subset of those values that meet a given criteria**.

  For a facet attribute to be searchable, it must have been declared in the
  `attributesForFaceting` index setting with the `searchable` modifier.

  Facet-searching only affects facet values. It does not impact the underlying
  index search.

  The results are **sorted by decreasing count**. This can be adjusted via
  `sortFacetValuesBy`.

  By default, maximum **10 results are returned**. This can be adjusted via
  `maxFacetHits`.

  ## Examples

      iex> Algolia.search_for_facet_values("species", "phylum", "dophyta")
      {
        :ok,
        %{
          "exhaustiveFacetsCount" => false,
          "faceHits" => [
            %{
              "count" => 9000,
              "highlighted" => "Pteri<em>dophyta</em>",
              "value" => "Pteridophyta"
            },
            %{
              "count" => 7000,
              "highlighted" => "Rho<em>dophyta</em>",
              "value" => "Rhodophyta"
            },
            %{
              "count" => 150,
              "highlighted" => "Cyca<em>dophyta</em>",
              "value" => "Cycadophyta"
            }
          ],
          "processingTimeMS" => 42
        }
      }
  """
  @spec search_for_facet_values(binary, binary, binary, map, [config_opt]) ::
          {:ok, map} | {:error, code :: integer, message :: binary}
  def search_for_facet_values(index, facet, text, query \\ %{}, opts \\ [])
      when is_binary(index) and is_binary(facet) and is_binary(text)
      when is_list(opts) do
    {config, _opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    path = Paths.search_facet(index, facet)

    body =
      query
      |> Map.put("facetQuery", text)
      |> Jason.encode!()

    send_request(config, :read, %{method: :post, path: path, body: body})
  end

  defp send_request(config, read_or_write, request, curr_retry \\ 0)

  defp send_request(%Config{}, _read_or_write, _request, 4) do
    {:error, "Unable to connect to Algolia"}
  end

  defp send_request(%Config{} = config, read_or_write, request, curr_retry) do
    url = request_url(config, read_or_write, curr_retry, request[:path])
    headers = request_headers(config, request[:options] || [])
    body = request[:body] || ""

    request[:method]
    |> :hackney.request(url, headers, body, [
      :with_body,
      path_encode_fun: &URI.encode/1,
      connect_timeout: 3_000 * (curr_retry + 1),
      recv_timeout: 30_000 * (curr_retry + 1),
      ssl_options: [{:versions, [:"tlsv1.2"]}]
    ])
    |> case do
      {:ok, code, _headers, response} when code in 200..299 ->
        {:ok, Jason.decode!(response)}

      {:ok, code, _, response} ->
        {:error, code, response}

      _ ->
        send_request(config, read_or_write, request, curr_retry + 1)
    end
  end

  defp request_url(config, read_or_write, retry, path) do
    base_url = config.base_url_fn.(read_or_write, config.application_id, retry)

    Path.join(base_url, path)
  end

  defp request_headers(config, request_options) do
    custom = request_options[:headers] || []

    default = [
      {"X-Algolia-API-Key", config.api_key},
      {"X-Algolia-Application-Id", config.application_id}
    ]

    custom ++ default
  end

  @doc """
  Get an object in an index by objectID
  """
  def get_object(index, object_id, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    path = Paths.object(index, object_id)

    config
    |> send_request(:read, %{method: :get, path: path, options: opts[:request_options]})
    |> inject_index_into_response(index)
  end

  @doc """
  Add an Object

  An attribute can be chosen as the objectID.
  """
  def add_object(index, object, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    if opts[:id_attribute] do
      save_object(index, object, opts)
    else
      body = Jason.encode!(object)
      path = Paths.index(index)

      config
      |> send_request(:write, %{
        method: :post,
        path: path,
        body: body,
        options: opts[:request_options]
      })
      |> inject_index_into_response(index)
    end
  end

  @doc """
  Add multiple objects

  An attribute can be chosen as the objectID.
  """
  def add_objects(index, objects, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    if opts[:id_attribute] do
      save_objects(index, objects, opts)
    else
      objects
      |> build_batch_request("addObject")
      |> send_batch_request(config, index, opts[:request_options])
    end
  end

  @doc """
  Save a single object, without objectID specified, must have objectID as
  a field
  """
  def save_object(index, object, opts \\ [])

  def save_object(index, object, id) when is_map(object) and not is_list(id) do
    save_object(index, object, id, [])
  end

  def save_object(index, object, opts) when is_map(object) do
    id = object_id_for_save!(object, opts)

    save_object(index, object, id, opts)
  end

  defp object_id_for_save!(object, opts) do
    if id_attribute = opts[:id_attribute] do
      object[id_attribute] || object[to_string(id_attribute)] ||
        raise ArgumentError,
          message: "Your object does not have a '#{id_attribute}' attribute"
    else
      object["objectID"] || object[:objectID] ||
        raise ArgumentError,
          message: "Your object must have an objectID to be saved using save_object"
    end
  end

  defp save_object(index, object, object_id, opts) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    body = Jason.encode!(object)
    path = Paths.object(index, object_id)

    config
    |> send_request(:write, %{
      method: :put,
      path: path,
      body: body,
      options: opts[:request_options]
    })
    |> inject_index_into_response(index)
  end

  @doc """
  Save multiple objects
  """
  def save_objects(index, objects, opts \\ [id_attribute: :objectID]) when is_list(objects) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    id_attribute = opts[:id_attribute] || :objectID

    objects
    |> add_object_ids(id_attribute: id_attribute)
    |> build_batch_request("updateObject")
    |> send_batch_request(config, index, opts[:request_options])
  end

  @doc """
  Partially updates an object, takes option upsert: true or false
  """
  def partial_update_object(index, object, object_id, opts \\ [upsert?: true]) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    body = Jason.encode!(object)
    path = Paths.partial_object(index, object_id, opts[:upsert?])

    config
    |> send_request(:write, %{
      method: :post,
      path: path,
      body: body,
      options: opts[:request_options]
    })
    |> inject_index_into_response(index)
  end

  @doc """
  Partially updates multiple objects
  """
  def partial_update_objects(index, objects, opts \\ [upsert?: true, id_attribute: :objectID]) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    id_attribute = opts[:id_attribute] || :objectID

    upsert =
      case opts[:upsert?] do
        false -> false
        _ -> true
      end

    action = if upsert, do: "partialUpdateObject", else: "partialUpdateObjectNoCreate"

    objects
    |> add_object_ids(id_attribute: id_attribute)
    |> build_batch_request(action)
    |> send_batch_request(config, index, opts[:request_options])
  end

  # No need to add any objectID by default
  defp add_object_ids(objects, id_attribute: :objectID), do: objects
  defp add_object_ids(objects, id_attribute: "objectID"), do: objects

  defp add_object_ids(objects, id_attribute: attribute) do
    Enum.map(objects, fn object ->
      object_id = object[attribute] || object[to_string(attribute)]

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

  defp send_batch_request(requests, config, index, request_options) do
    path = Paths.batch(index)
    body = Jason.encode!(requests)

    config
    |> send_request(:write, %{method: :post, path: path, body: body, options: request_options})
    |> inject_index_into_response(index)
  end

  defp build_batch_request(objects, action) do
    requests =
      Enum.map(objects, fn object ->
        case get_object_id(object) do
          {:ok, object_id} -> %{action: action, body: object, objectID: object_id}
          _ -> %{action: action, body: object}
        end
      end)

    %{requests: requests}
  end

  @doc """
  Delete a object by its objectID
  """
  def delete_object(index, object_id, opts \\ [])

  def delete_object(_index, "", _request_options) do
    {:error, %InvalidObjectIDError{}}
  end

  def delete_object(index, object_id, opts) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    path = Paths.object(index, object_id)

    config
    |> send_request(:write, %{method: :delete, path: path, options: opts[:request_options]})
    |> inject_index_into_response(index)
  end

  @doc """
  Delete multiple objects
  """
  def delete_objects(index, object_ids, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    object_ids
    |> Enum.map(fn id ->
      %{objectID: id}
    end)
    |> build_batch_request("deleteObject")
    |> send_batch_request(config, index, opts[:request_options])
  end

  @doc """
  Remove all objects matching a filter (including geo filters).

  Allowed filter parameters:

  * `filters`
  * `facetFilters`
  * `numericFilters`
  * `aroundLatLng` and `aroundRadius` (these two need to be used together)
  * `insideBoundingBox`
  * `insidePolygon`

  ## Examples

      iex> Algolia.delete_by("index", filters: ["score < 30"])
      {:ok, %{"indexName" => "index", "taskId" => 42, "deletedAt" => "2018-10-30T15:33:13.556Z"}}
  """
  def delete_by(index, opts) when is_list(opts) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    {request_options, opts} = Keyword.pop(opts, :request_options)

    path = Paths.delete_by(index)

    body =
      opts
      |> sanitize_delete_by_opts()
      |> validate_delete_by_opts!()
      |> Map.new()
      |> Jason.encode!()

    config
    |> send_request(:write, %{method: :post, path: path, body: body, options: request_options})
    |> inject_index_into_response(index)
  end

  defp sanitize_delete_by_opts(opts) do
    Keyword.drop(opts, [
      :hitsPerPage,
      :attributesToRetrieve,
      "hitsPerPage",
      "attributesToRetrieve"
    ])
  end

  defp validate_delete_by_opts!([]) do
    raise ArgumentError, message: "opts are required, use `clear_index/1` to wipe the index."
  end

  defp validate_delete_by_opts!(opts), do: opts

  @doc """
  List all indexes
  """
  def list_indexes(opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    send_request(config, :read, %{
      method: :get,
      path: Paths.indexes(),
      options: opts[:request_options]
    })
  end

  @doc """
  Deletes the index
  """
  def delete_index(index, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    config
    |> send_request(:write, %{
      method: :delete,
      path: Paths.index(index),
      options: opts[:request_options]
    })
    |> inject_index_into_response(index)
  end

  @doc """
  Clears all content of an index
  """
  def clear_index(index, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    config
    |> send_request(:write, %{
      method: :post,
      path: Paths.clear(index),
      options: opts[:request_options]
    })
    |> inject_index_into_response(index)
  end

  @doc """
  Set the settings of a index
  """
  def set_settings(index, settings, opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    body = Jason.encode!(settings)
    path = Paths.settings(index)

    config
    |> send_request(:write, %{
      method: :put,
      path: path,
      body: body,
      options: opts[:request_options]
    })
    |> inject_index_into_response(index)
  end

  @doc """
  Get the settings of a index
  """
  def get_settings(index, opts \\ []) do
    {config, _opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    config
    |> send_request(:read, %{method: :get, path: Paths.settings(index)})
    |> inject_index_into_response(index)
  end

  @doc """
  Moves an index to new one
  """
  def move_index(src_index, dst_index, opts \\ []) do
    {config, _opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    body = Jason.encode!(%{operation: "move", destination: dst_index})

    config
    |> send_request(:write, %{method: :post, path: Paths.operation(src_index), body: body})
    |> inject_index_into_response(src_index)
  end

  @doc """
  Copies an index to a new one
  """
  def copy_index(src_index, dst_index, opts \\ []) do
    {config, _opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    body = Jason.encode!(%{operation: "copy", destination: dst_index})

    config
    |> send_request(:write, %{method: :post, path: Paths.operation(src_index), body: body})
    |> inject_index_into_response(src_index)
  end

  ## Helps piping a response into wait_task, as it requires the index
  defp inject_index_into_response({:ok, body}, index) do
    {:ok, Map.put(body, "indexName", index)}
  end

  defp inject_index_into_response(response, _index), do: response

  @doc """
  Get the logs of the latest search and indexing operations.

  ## Options

    * `:indexName` - Index for which log entries should be retrieved. When omitted,
      log entries are retrieved across all indices.

    * `:length` - Maximum number of entries to retrieve. Maximum allowed value: 1000.

    * `:offset` - First entry to retrieve (zero-based). Log entries are sorted by
      decreasing date, therefore 0 designates the most recent log entry.

    * `:type` - Type of log to retrieve: `all` (default), `query`, `build` or `error`.
  """
  def get_logs(opts \\ []) do
    {config, opts} = Keyword.pop_lazy(opts, :config, &default_config/0)
    send_request(config, :write, %{method: :get, path: Paths.logs(opts)})
  end

  @doc """
  Wait for a task for an index to complete
  returns :ok when it's done
  """
  def wait_task(index, task_id, time_before_retry \\ 1000, opts \\ []) when is_list(opts) do
    {config, _opts} = Keyword.pop_lazy(opts, :config, &default_config/0)

    case send_request(config, :write, %{method: :get, path: Paths.task(index, task_id)}) do
      {:ok, %{"status" => "published"}} ->
        :ok

      {:ok, %{"status" => "notPublished"}} ->
        :timer.sleep(time_before_retry)
        wait_task(index, task_id, time_before_retry)

      other ->
        other
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

  defp default_config, do: Config.new()
end
