## Algolia [![Build Status](https://travis-ci.org/sikanhe/algolia-elixir.svg?branch=master)](https://travis-ci.org/sikanhe/algolia-elixir) ##

This is the elixir implementation of Algolia search API, it is purely functional

Add to your dependencies


```elixir
  defp deps do
    [{:algolia, "~> 0.4.0"}]
  end
```

Start the app

```elixir
  def application do
    [applications: [:logger, :algolia]]
  end
```

## Configuration

#### Using environment variables:

    ALGOLIA_APPLICATION_ID=YOUR_APPLICATION_ID
    ALGOLIA_API_KEY=YOUR_API_KEY

#### Using config:

    config :algolia,
      application_id: YOUR_APPLICATION_ID,
      api_key: YOUR_API_KEY

*NOTE: You must use ADMIN API_KEY instead of SEARCH API_KEY to enable write access*

## The Client

You don't need to initiate an index with this client unlike other OO Algolia clients.
However, Most of the client search/write functions all use the syntax

    operation(index, args....)

So you can easy emulate the index.function() syntax using piping

   "my_index" |> operation(args)


### Return values

All functions are serialized into maps before returning these responses

  - `{:ok, response}`
  - `{:error, error_code, response}`
  - `{:error, "Cannot connect to Algolia"}`: The client implements retry
      strategy on all Algolia hosts with increasing timeout, It should only
      return this error when it has tried all 4 hosts.
      [**More Details here**](https://www.algolia.com/doc/rest#quick-reference).

## Examples

### Searching

#### Searching an index

```elixir
    "my_index" |> search("some query")
```

With Options

```elixir
    "my_index" |> search("some query", %{attributesToRetrieve: "firstname", hitsPerPage: 20})
```

See all available search options [**here**](https://www.algolia.com/doc/rest#full-text-search-parameters)

#### Multiple queries at once

```elixir
    multi([%{index_name => "my_index1", query: "search query"},
            %{index_name => "my_index2", query: "another query", hitsPerPage: 3,},
            %{index_name => "my_index3", query: "3rd query", tagFilters: "promotion"}])
```

You can specify a strategy to optimize your multiple queries
- `:none`: Execute the sequence of queries until the end.
- `stop_if_enough_matches`: Execute the sequence of queries until the number of hits is reached by the sum of hits.

```elixir
    multi([query1, query2], strategy: :stop_if_enough_matches)
```

### Saving

All `save_*` operations will overrides the object at the objectID

Save a single object to index without specifying objectID, must have objectID
inside object, or use the `id_attribute` option (see below)

```elixir
    "my_index" |> save_object(%{objectID: "1"})
```

Save a single object with a given objectID

```elixir
    "my_index" |> save_object(%{title: "hello"}, "12345")
```

Save multiple objects to an index

```elixir
    "my_index" |> save_objects([%{objectID: "1"}, %{objectID: "2"}])
```

### Updating

Partially updates a single object

```elixir
    "my_index" |> partial_update_object(%{title: "hello"}, "12345")
```

Update multiple objects, must have objectID in each object, or use the `id_attribute` option (see below)


```elixir
    "my_index" |> partial_update_objects([%{objectID: "1"}, %{objectID: "2"}])
```

Partial update by default creates a new object if an object does not exist at the
objectID, you can turn this off by passing `false` to the `:upsert?` option

```elixir
    "my_index" |> partial_update_object(%{title: "hello"}, "12345", upsert?: false)
    "my_index" |> partial_update_objects([%{id: "1"}, %{id: "2"}], id_attribute: :id, upsert?: false)
```


### Bonus for this Elixir client only: `id_attribute` option

All write functions such as `save_object` and `partial_update_object` comes with an `id_attribute` option that lets the you specifying an objectID from an existing field in the object, so you do not
have to generate it yourself

```elixir
    "my_index" |> save_object(%{id: "2"}, id_attribute: :id)
```

It also works for batch operations, such as `save_objects` and `partial_update_objects`

```elixir
    "my_index" |> save_objects([%{id: "1"}, %{id: "2"}], id_attribute: :id)
```

However, this cannot be used together with an ID specifying argument together

```elixir
    "my_index" |> save_object(%{id: "1234"}, "1234", id_attribute: :id)
    > Error
```

### Wait for task

All write operations can be waited on by simply piping the response into wait/1

```elixir
    "my_index" |> save_object(%{id: "123"}) |> wait
```


Since the client polls the server to check for publishing status,
You can specify a time between each tick of the poll, the default is 100 ms

```elixir
    "my_index" |> save_object(%{id: "123"}) |> wait(2_000)
```

You can also use the underlying wait_task function explicitly


```elixir
    {:ok, %{"taskID" => task_id, "indexName" => index}}
      = "my_index" |> save_object(%{id: "123"}

    wait(index, task_id)
```

or with option

```elixir
    wait(index, task_id, 1_000)
```

### Index related operations

#### Listing all indexes

 ```elixir
    list_indexes()
 ```

#### move_index/2

Moves an index to a new one

```elixir
   move_index(source_index, destination_index)
```

#### copy_index/2

Copies an index to a new one

```elixir
    copy_index(source_index, destination_index)
```

#### Clear an index

```elixir
    clear_index(index)
```

### Settings

#### get_settings/1

```elixir
    get_settings(index)
```

Example response

```elixir
{:ok,
  %{"minWordSizefor1Typo" => 4,
    "minWordSizefor2Typos" => 8,
    "hitsPerPage" => 20,
    "attributesToIndex" => nil,
    "attributesToRetrieve" => nil,
    "attributesToSnippet" => nil,
    "attributesToHighlight" => nil,
    "ranking" => [
        "typo",
        "geo",
        "words",
        "proximity",
        "attribute",
        "exact",
        "custom"
    ],
    "customRanking" => nil,
    "separatorsToIndex" => "",
    "queryType" => "prefixAll"}
}
```

#### set_settings/2

```elixir
    set_settings(index, %{"hitsPerPage" => 20})

     > %{"updatedAt" => "2013-08-21T13:20:18.960Z",
        "taskID" => 10210332.
        "indexName" => "my_index"}
```
### TODOS:

- [x] get_object
- [x] save_object
- [x] save_objects
- [x] update_object
- [x] partial_update_object
- [x] partial_update_objects
- [x] delete_object
- [x] delete_objects
- [x] list_indexes
- [x] clear_index
- [x] wait_task
- [x] wait (convenience function for piping response into wait_task)
- [x] set_settings
- [x] get_settings
- [ ] list_user_keys
- [ ] get_user_key
- [ ] add_user_key
- [ ] update_user_key
- [ ] delete_user_key
