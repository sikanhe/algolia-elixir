defmodule Algolia do
  @moduledoc """
  Elixir implementation of Algolia search API, using Hackney for http requests
  """

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

  def application_id do
    System.get_env("ALGOLIA_APPLICATION_ID") || Application.get_env(:algolia, :application_id) ||
      raise MissingApplicationIDError
  end

  def api_key do
    System.get_env("ALGOLIA_API_KEY") || Application.get_env(:algolia, :api_key) ||
      raise MissingAPIKeyError
  end

  defp host(:read, 0), do: "#{application_id()}-dsn.algolia.net"
  defp host(:write, 0), do: "#{application_id()}.algolia.net"

  defp host(_read_or_write, curr_retry) when curr_retry <= 3,
    do: "#{application_id()}-#{curr_retry}.algolianet.com"

  @doc """
  Multiple queries
  """
  def multi(queries, opts \\ []) do
    path = Paths.multiple_queries(opts[:strategy])
    body = queries |> format_multi() |> Jason.encode!()

    send_request(:read, %{method: :post, path: path, body: body, options: opts[:request_options]})
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
    {request_options, opts} = Keyword.pop(opts, :request_options)

    path = Paths.search(index, query, opts)

    send_request(:read, %{method: :get, path: path, options: request_options})
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
  @spec search_for_facet_values(binary, binary, binary, map) ::
          {:ok, map} | {:error, code :: integer, message :: binary}
  def search_for_facet_values(index, facet, text, query \\ %{})
      when is_binary(index) and is_binary(facet) and is_binary(text) do
    path = Paths.search_facet(index, facet)

    body =
      query
      |> Map.put("facetQuery", text)
      |> Jason.encode!()

    send_request(:read, %{method: :post, path: path, body: body})
  end

  defp send_request(read_or_write, request, curr_retry \\ 0)

  defp send_request(_read_or_write, _request, 4) do
    {:error, "Unable to connect to Algolia"}
  end

  defp send_request(read_or_write, request, curr_retry) do
    url = request_url(read_or_write, curr_retry, request[:path])
    headers = request_headers(request[:options] || [])
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
        send_request(read_or_write, request, curr_retry + 1)
    end
  end

  defp request_url(read_or_write, retry, path) do
    "https://"
    |> Path.join(host(read_or_write, retry))
    |> Path.join(path)
  end

  defp request_headers(request_options) do
    custom = request_options[:headers] || []

    default = [
      {"X-Algolia-API-Key", api_key()},
      {"X-Algolia-Application-Id", application_id()}
    ]

    custom ++ default
  end

  @doc """
  Get an object in an index by objectID
  """
  def get_object(index, object_id, opts \\ []) do
    path = Paths.object(index, object_id)

    :read
    |> send_request(%{method: :get, path: path, options: opts[:request_options]})
    |> inject_index_into_response(index)
  end

  @doc """
  Add an Object

  An attribute can be chosen as the objectID.
  """
  def add_object(index, object, opts \\ []) do
    if opts[:id_attribute] do
      save_object(index, object, opts)
    else
      body = Jason.encode!(object)
      path = Paths.index(index)

      :write
      |> send_request(%{method: :post, path: path, body: body, options: opts[:request_options]})
      |> inject_index_into_response(index)
    end
  end

  @doc """
  Add multiple objects

  An attribute can be chosen as the objectID.
  """
  def add_objects(index, objects, opts \\ []) do
    if opts[:id_attribute] do
      save_objects(index, objects, opts)
    else
      objects
      |> build_batch_request("addObject")
      |> send_batch_request(index, opts[:request_options])
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

    save_object(index, object, id, opts[:request_options])
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

  defp save_object(index, object, object_id, request_options) do
    body = Jason.encode!(object)
    path = Paths.object(index, object_id)

    :write
    |> send_request(%{method: :put, path: path, body: body, options: request_options})
    |> inject_index_into_response(index)
  end

  @doc """
  Save multiple objects
  """
  def save_objects(index, objects, opts \\ [id_attribute: :objectID]) when is_list(objects) do
    id_attribute = opts[:id_attribute] || :objectID

    objects
    |> add_object_ids(id_attribute: id_attribute)
    |> build_batch_request("updateObject")
    |> send_batch_request(index, opts[:request_options])
  end

  @doc """
  Partially updates an object, takes option upsert: true or false
  """
  def partial_update_object(index, object, object_id, opts \\ [upsert?: true]) do
    body = Jason.encode!(object)
    path = Paths.partial_object(index, object_id, opts[:upsert?])

    :write
    |> send_request(%{method: :post, path: path, body: body, options: opts[:request_options]})
    |> inject_index_into_response(index)
  end

  @doc """
  Partially updates multiple objects
  """
  def partial_update_objects(index, objects, opts \\ [upsert?: true, id_attribute: :objectID]) do
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
    |> send_batch_request(index, opts[:request_options])
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

  defp send_batch_request(requests, index, request_options) do
    path = Paths.batch(index)
    body = Jason.encode!(requests)

    :write
    |> send_request(%{method: :post, path: path, body: body, options: request_options})
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
    path = Paths.object(index, object_id)

    :write
    |> send_request(%{method: :delete, path: path, options: opts[:request_options]})
    |> inject_index_into_response(index)
  end

  @doc """
  Delete multiple objects
  """
  def delete_objects(index, object_ids, opts \\ []) do
    object_ids
    |> Enum.map(fn id ->
      %{objectID: id}
    end)
    |> build_batch_request("deleteObject")
    |> send_batch_request(index, opts[:request_options])
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
    {request_options, opts} = Keyword.pop(opts, :request_options)

    path = Paths.delete_by(index)

    body =
      opts
      |> sanitize_delete_by_opts()
      |> validate_delete_by_opts!()
      |> Map.new()
      |> Jason.encode!()

    :write
    |> send_request(%{method: :post, path: path, body: body, options: request_options})
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
  def list_indexes do
    send_request(:read, %{method: :get, path: Paths.indexes()})
  end

  @doc """
  Deletes the index
  """
  def delete_index(index) do
    :write
    |> send_request(%{method: :delete, path: Paths.index(index)})
    |> inject_index_into_response(index)
  end

  @doc """
  Clears all content of an index
  """
  def clear_index(index) do
    :write
    |> send_request(%{method: :post, path: Paths.clear(index)})
    |> inject_index_into_response(index)
  end

  @doc """
  Set the settings of a index
  """
  def set_settings(index, settings, opts \\ []) do
    body = Jason.encode!(settings)
    path = Paths.settings(index, opts)

    :write
    |> send_request(%{method: :put, path: path, body: body})
    |> inject_index_into_response(index)
  end

  @doc """
  Get the settings of a index
  """
  def get_settings(index) do
    :read
    |> send_request(%{method: :get, path: Paths.settings(index)})
    |> inject_index_into_response(index)
  end

  @doc """
  Get all the synonyms of a index.

  Only the index is required

  ## Examples

      iex> Algolia.export_synonyms("index")
      {:ok, %{
        "indexName" => "index",
        "nbHits" => 33,
        "hits" => [%{
          "objectID" => "1539816124475_0",
          "synonyms" => ["big", "large"],
          "type" => "synonym"
          "_highlightResult" => %{...}
        }, ...]
      }}
  """
  def export_synonyms(index) do
    get_all_paginated_hits(index, &search_synonyms/3)
  end

  defp get_all_paginated_hits(index, search, hits_per_page \\ 100) do
    0
    |> Stream.iterate(&(&1 + 1))
    |> Stream.flat_map(fn page -> get_page_hits(index, page, hits_per_page, search) end)
    |> Stream.take_while(&(&1 != :stop))
  end

  defp get_page_hits(index, page, hits_per_page, search) do
    case search.(index, "", page: page, hits_per_page: hits_per_page) do
      {:ok, %{"hits" => hits, "nbPages" => pages}} when page + 1 < pages -> page_hits(hits)
      {:ok, %{"hits" => hits}} -> page_hits(hits) ++ [:stop]
      error -> [error, :stop]
    end
  end

  defp page_hits(hits) do
    Enum.map(hits, &{:ok, Map.drop(&1, ["_highlightResult"])})
  end

  @doc """
  Search for synonyms of a index matching a query

  Allowed parameters:

  * `query` Required
  * `type` Defaults to `""`(all). Allowed the types: `"synonym,oneWaySynonym,altCorrection1,altCorrection2,placeholder"`
  * `page`
  * `hitsPerPage`

  ## Examples

      iex> Algolia.search_synonyms("index", "query", hits_per_page: 20)
      {:ok, %{
        "indexName" => "index",
        "nbHits" => 33,
        "hits" => [%{
          "objectID" => "1539816124475_0",
          "synonyms" => ["big", "large"],
          "type" => "synonym"
          "_highlightResult" => %{...}
        }, ...]
      }}
  """
  def search_synonyms(index, query, opts \\ []) do
    body =
      opts
      |> Enum.into(%{})
      |> Map.put("query", query)
      |> Map.put("page", opts[:page] || 0)
      |> Map.put("hitsPerPage", opts[:hits_per_page] || 20)
      |> Map.drop([:page, :hits_per_page])
      |> Jason.encode!()

    :write
    |> send_request(%{method: :post, path: Paths.search_synonyms(index), body: body})
    |> inject_index_into_response(index)
  end

  @doc """
  Create or update an list of synonyms.

  * `synonyms` Required: With [synonyms objects](https://www.algolia.com/doc/api-reference/api-methods/save-synonym/#method-param-synonym-object).
  * - `objectID` Required: If the Id do not exist it will be created.
  * - `type` Required: Allowed the types: `"synonym,oneWaySynonym,altCorrection1,altCorrection2,placeholder"`.
  * - `synonyms` Required if type=synonym or type=oneWaySynonym: List of strings.
  * - `input` Required if type=oneWaySynonym.
  * - `word` Required if type=altCorrection1 or type=altCorrection2.
  * - `corrections` Required if type=altCorrection1 or type=altCorrection2.
  * - `placeholder` Required if type=placeholder.
  * - `replacements` Required if type=placeholder.

  Allowed params:
  * `forwardToReplicas`
  * `replaceExistingSynonyms`
  """
  def batch_synonyms(index, batch, opts \\ []) do
    body = Jason.encode!(batch)

    :write
    |> send_request(%{method: :post, path: Paths.batch_synonyms(index, opts), body: body})
    |> inject_index_into_response(index)
  end

  @doc """
  Search for query rules of a index matching a query

  Allowed parameters:

  * `query` Required
  * `page`
  * `hitsPerPage`
  """
  def search_rules(index, query, opts \\ []) do
    body =
      opts
      |> Enum.into(%{})
      |> Map.put("query", query)
      |> Map.put("page", opts[:page] || 0)
      |> Map.put("hitsPerPage", opts[:hits_per_page] || 20)
      |> Map.drop([:page, :hits_per_page])
      |> Jason.encode!()

    :write
    |> send_request(%{method: :post, path: Paths.search_rules(index), body: body})
    |> inject_index_into_response(index)
  end

  @doc """
  Get all the query rules of a index.

  Only the index is required
  """
  def export_rules(index) do
    get_all_paginated_hits(index, &search_rules/3)
  end

  @doc """
  Create or update an list of Query Rules.

  * `batch` Required: list with [Query Rules](https://www.algolia.com/doc/api-reference/api-methods/save-rule/#method-param-rule)
  * - `objectID` Required: If the Id do not exist it will be created.
  * - `description` To ease searching for rules and presenting them to human readers.
  * - `enabled` Whether the rule is enabled. Disabled rules remain in the index, but are not applied at query time.
  * - `validity` By default, rules are permanently valid. When validity periods are specified, the rule applies only during those periods.
  * - `condition` Required: [condition](https://www.algolia.com/doc/api-reference/api-methods/save-rule/?language=javascript#method-param-condition-2)
  * -- `pattern` Required: Query patterns are expressed as a string with a specific syntax.
  * -- `anchoring` Required: Enum `["is", "startsWith", "endsWith", "contains"]`.
  * -- `context`: Rule context. When specified, the rule is contextual and applies only when the same context is specified at query time.
  * - `consequence` Required at least 1 [consequence](https://www.algolia.com/doc/api-reference/api-methods/save-rule/?language=javascript#method-param-consequence-2)
  * -- `params`: Additional search parameters. Any valid search parameter is allowed.
  * -- `promote`: List with objects to promote as hits.
  * --- `objectID`
  * --- `position`
  * -- `hide`: List with objects to hide from hits.
  * --- `objectID`
  * -- `userData`: Custom JSON object that will be appended to the userData array in the response.

  Allowed params:
  * `forwardToReplicas` When true, the change is forwarded to all replicas of this index.
  * `clearExistingRules` When true, existing rules are cleared before adding this batch.
  """
  def batch_rules(index, batch, opts \\ []) do
    body = Jason.encode!(batch)

    :write
    |> send_request(%{method: :post, path: Paths.batch_rules(index, opts), body: body})
    |> inject_index_into_response(index)
  end

  @doc """
  Moves an index to new one
  """
  def move_index(src_index, dst_index) do
    body = Jason.encode!(%{operation: "move", destination: dst_index})

    :write
    |> send_request(%{method: :post, path: Paths.operation(src_index), body: body})
    |> inject_index_into_response(src_index)
  end

  @doc """
  Copies an index to a new one
  """
  def copy_index(src_index, dst_index) do
    body = Jason.encode!(%{operation: "copy", destination: dst_index})

    :write
    |> send_request(%{method: :post, path: Paths.operation(src_index), body: body})
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
    send_request(:write, %{method: :get, path: Paths.logs(opts)})
  end

  @doc """
  Wait for a task for an index to complete
  returns :ok when it's done
  """
  def wait_task(index, task_id, time_before_retry \\ 1000) do
    case send_request(:write, %{method: :get, path: Paths.task(index, task_id)}) do
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
end
