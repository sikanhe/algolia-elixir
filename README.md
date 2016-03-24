# Algolia

This is the elixir implementation of Algolia search API

# TODOS:

- [x] get_object
- [x] save_object
- [x] save_objects
- [x] update_object
- [x] partial_update_object
- [ ] partial_update_objects
- [x] delete_object
- [x] delete_objects
- [ ] list_indexes
- [x] clear_index
- [x] wait_task
- [x] wait (convenience function for piping response into wait_task)
- [x] set_settings
- [ ] get_settings
- [ ] list_user_keys
- [ ] get_user_key
- [ ] add_user_key
- [ ] update_user_key
- [ ] delete_user_key



## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add algolia to your list of dependencies in `mix.exs`:

        def deps do
          [{:algolia, "~> 0.0.1"}]
        end

  2. Ensure algolia is started before your application:

        def application do
          [applications: [:algolia]]
        end
