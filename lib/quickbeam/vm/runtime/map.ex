defmodule QuickBEAM.VM.Runtime.Map do
  @moduledoc "JS `Map` and `WeakMap` built-ins: constructor, `get`/`set`/`has`/`delete`, and iteration."

  import QuickBEAM.VM.Heap.Keys

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.Runtime
  alias QuickBEAM.VM.Runtime.Collections

  alias QuickBEAM.VM.{Builtin, Invocation, JSThrow}

  @doc "Implements Map.groupBy(items, callbackfn)."
  def group_by(args) do
    items = Builtin.arg(args, 0, :undefined)
    callback = Builtin.arg(args, 1, :undefined)

    if items in [nil, :undefined] do
      JSThrow.type_error!("Cannot convert undefined or null to object")
    end

    unless Builtin.callable?(callback) do
      JSThrow.type_error!("callbackfn is not a function")
    end

    list = Heap.to_list(items)
    ref = make_ref()
    groups = %{}
    order = []

    {groups, order} =
      list
      |> Enum.with_index()
      |> Enum.reduce({groups, order}, fn {val, idx}, {g, ord} ->
        key = Invocation.invoke_with_receiver(callback, [val, idx], :undefined)
        normalized_key = if key == -0.0, do: 0, else: key

        case Map.fetch(g, normalized_key) do
          {:ok, existing} ->
            {Map.put(g, normalized_key, existing ++ [val]), ord}

          :error ->
            {Map.put(g, normalized_key, [val]), ord ++ [normalized_key]}
        end
      end)

    result_entries =
      Enum.map(order, fn key -> {key, Heap.wrap(Map.get(groups, key, []))} end)

    result_map = Enum.into(result_entries, %{})
    result_order = Enum.map(result_entries, fn {k, _} -> k end)

    Heap.put_obj(ref, %{
      map_data() => result_map,
      key_order() => Enum.reverse(result_order),
      proto() => Runtime.global_class_proto("Map")
    })

    {:obj, ref}
  end

  @doc "Builds the JavaScript constructor object for this runtime builtin."
  def constructor do
    fn args, _this ->
      ref = make_ref()

      {entries, order} =
        case args do
          [list] when is_list(list) ->
            entries_from_list(list)

          [{:obj, r}] ->
            stored = Heap.get_obj(r, [])

            if is_list(stored) or match?({:qb_arr, _}, stored) do
              entries_from_list(Heap.to_list({:obj, r}))
            else
              {%{}, []}
            end

          _ ->
            {%{}, []}
        end

      Heap.put_obj(ref, %{
        map_data() => entries,
        key_order() => order,
        "size" => map_size(entries),
        proto() => Runtime.global_class_proto("Map")
      })

      {:obj, ref}
    end
  end

  @doc "Helper for js `map` and `weakmap` built-ins: constructor, `get`/`set`/`has`/`delete`, and iteration."
  def weak_constructor do
    fn args, _this ->
      ref = make_ref()

      init =
        case args do
          [{:obj, _} = entries | _] ->
            Heap.to_list(entries)
            |> Enum.reduce(%{}, fn
              {:obj, eref}, acc ->
                case Heap.get_obj(eref, []) do
                  [k, v | _] ->
                    Collections.validate_weak_key!(k, "WeakMap")
                    Map.put(acc, k, v)

                  _ ->
                    acc
                end

              _, acc ->
                acc
            end)

          _ ->
            %{}
        end

      Heap.put_obj(ref, %{map_data() => init, "size" => map_size(init), :weak => true})
      {:obj, ref}
    end
  end

  @doc "Returns the MapData size for Map.prototype.size."
  def size(this), do: this |> require_strong_map_ref!() |> data() |> map_size()

  @doc "Returns a prototype property value for the given JavaScript property key."
  def proto_property("get"), do: {:builtin, "get", &get/2}
  def proto_property("set"), do: {:builtin, "set", &set/2}
  def proto_property("has"), do: {:builtin, "has", &has/2}
  def proto_property("delete"), do: {:builtin, "delete", &delete/2}
  def proto_property("clear"), do: {:builtin, "clear", &clear/2}
  def proto_property("keys"), do: {:builtin, "keys", &keys/2}
  def proto_property("values"), do: {:builtin, "values", &values/2}
  def proto_property("entries"), do: {:builtin, "entries", &entries/2}
  def proto_property({:symbol, "Symbol.iterator"}), do: proto_property("entries")
  def proto_property("forEach"), do: {:builtin, "forEach", &for_each/2}
  def proto_property("getOrInsert"), do: {:builtin, "getOrInsert", &get_or_insert/2}

  def proto_property("getOrInsertComputed"),
    do: {:builtin, "getOrInsertComputed", &get_or_insert_computed/2}

  def proto_property("size") do
    {:builtin, "size",
     fn _, {:obj, ref} ->
       Heap.get_obj(ref, %{})
       |> Map.get(map_data(), %{})
       |> map_size()
     end}
  end

  def proto_property(_), do: :undefined

  def weak_proto_property("get"), do: {:builtin, "get", &weak_get/2}
  def weak_proto_property("set"), do: {:builtin, "set", &weak_set/2}
  def weak_proto_property("has"), do: {:builtin, "has", &weak_has/2}
  def weak_proto_property("delete"), do: {:builtin, "delete", &weak_delete/2}
  def weak_proto_property(_), do: :undefined

  defp require_map_ref!({:obj, ref}) do
    case Heap.get_obj(ref, %{}) do
      map when is_map(map) and is_map_key(map, map_data()) -> ref
      _ -> JSThrow.type_error!("Method requires a Map")
    end
  end

  defp require_map_ref!(_), do: JSThrow.type_error!("Method requires a Map")

  defp require_strong_map_ref!({:obj, ref}) do
    case Heap.get_obj(ref, %{}) do
      map when is_map(map) and is_map_key(map, map_data()) and not is_map_key(map, :weak) ->
        ref

      _ ->
        JSThrow.type_error!("Method requires a Map")
    end
  end

  defp require_strong_map_ref!(_), do: JSThrow.type_error!("Method requires a Map")

  defp data(ref), do: Heap.get_obj(ref, %{}) |> Map.get(map_data(), %{})

  defp normalize_key(k) when is_float(k) and k == trunc(k), do: trunc(k)
  defp normalize_key(k), do: k

  defp entries_from_list(entries) do
    pairs =
      Enum.map(entries, fn entry ->
        {key, value} = entry_to_kv(entry)
        {normalize_key(key), value}
      end)

    order =
      pairs
      |> Enum.map(fn {key, _value} -> key end)
      |> Enum.uniq()
      |> Enum.reverse()

    {Map.new(pairs), order}
  end

  defp get([key | _], this) do
    ref = require_strong_map_ref!(this)
    data = Heap.get_obj(ref, %{}) |> Map.get(map_data(), %{})
    Map.get(data, normalize_key(key), :undefined)
  end

  defp get(_, this), do: require_strong_map_ref!(this)

  defp get_or_insert([key, value | _], this) do
    ref = require_strong_map_ref!(this)
    key = normalize_key(key)
    obj = Heap.get_obj(ref, %{})
    data = Map.get(obj, map_data(), %{})

    case Map.fetch(data, key) do
      {:ok, existing} ->
        existing

      :error ->
        insert_map_entry(ref, obj, key, value)
        value
    end
  end

  defp get_or_insert(_, this), do: require_strong_map_ref!(this)

  defp get_or_insert_computed([key, callback | _], this) do
    ref = require_strong_map_ref!(this)

    unless Builtin.callable?(callback) do
      JSThrow.type_error!("callbackfn is not a function")
    end

    key = normalize_key(key)
    obj = Heap.get_obj(ref, %{})
    data = Map.get(obj, map_data(), %{})

    case Map.fetch(data, key) do
      {:ok, existing} ->
        existing

      :error ->
        value = Invocation.invoke_with_receiver(callback, [key], :undefined)
        obj = Heap.get_obj(ref, %{})
        insert_map_entry(ref, obj, key, value)
        value
    end
  end

  defp get_or_insert_computed(_, this), do: require_strong_map_ref!(this)

  defp insert_map_entry(ref, obj, key, value) do
    data = Map.get(obj, map_data(), %{})
    order = Map.get(obj, key_order(), [])
    order = if Map.has_key?(data, key), do: order, else: [key | order]
    new_data = Map.put(data, key, value)

    Heap.put_obj(
      ref,
      Map.merge(obj, %{map_data() => new_data, "size" => map_size(new_data), key_order() => order})
    )
  end

  defp set([key, val | _], this) do
    ref = require_strong_map_ref!(this)
    obj = Heap.get_obj(ref, %{})
    key = normalize_key(key)
    data = Map.get(obj, map_data(), %{})
    order = Map.get(obj, key_order(), [])
    order = if Map.has_key?(data, key), do: order, else: [key | order]
    new_data = Map.put(data, key, val)

    Heap.put_obj(
      ref,
      Map.merge(obj, %{
        map_data() => new_data,
        "size" => map_size(new_data),
        key_order() => order
      })
    )

    {:obj, ref}
  end

  defp set(_, this), do: require_strong_map_ref!(this)

  defp has([key | _], this) do
    ref = require_strong_map_ref!(this)
    data = Heap.get_obj(ref, %{}) |> Map.get(map_data(), %{})
    Map.has_key?(data, normalize_key(key))
  end

  defp has(_, this), do: require_strong_map_ref!(this)

  defp delete([key | _], this) do
    ref = require_strong_map_ref!(this)
    key = normalize_key(key)
    obj = Heap.get_obj(ref, %{})
    data = Map.get(obj, map_data(), %{})
    new_data = Map.delete(data, key)
    order = Map.get(obj, key_order(), []) |> List.delete(key)

    Heap.put_obj(
      ref,
      Map.merge(obj, %{
        map_data() => new_data,
        "size" => map_size(new_data),
        key_order() => order
      })
    )

    Map.has_key?(data, key)
  end

  defp delete(_, this), do: require_strong_map_ref!(this)

  defp weak_get([key | _], this) do
    ref = require_map_ref!(this)
    data = Heap.get_obj(ref, %{}) |> Map.get(map_data(), %{})
    Map.get(data, key, :undefined)
  end

  defp weak_get(_, this), do: require_map_ref!(this)

  defp weak_set([key, value | _], this) do
    ref = require_map_ref!(this)
    obj = Heap.get_obj(ref, %{})
    if Map.get(obj, :weak), do: Collections.validate_weak_key!(key, "WeakMap")
    data = Map.get(obj, map_data(), %{})
    new_data = Map.put(data, key, value)
    Heap.put_obj(ref, Map.merge(obj, %{map_data() => new_data, "size" => map_size(new_data)}))
    {:obj, ref}
  end

  defp weak_set(_, this), do: require_map_ref!(this)

  defp weak_has([key | _], this) do
    ref = require_map_ref!(this)
    data = Heap.get_obj(ref, %{}) |> Map.get(map_data(), %{})
    Map.has_key?(data, key)
  end

  defp weak_has(_, this), do: require_map_ref!(this)

  defp weak_delete([key | _], this) do
    ref = require_map_ref!(this)
    obj = Heap.get_obj(ref, %{})
    data = Map.get(obj, map_data(), %{})
    new_data = Map.delete(data, key)
    Heap.put_obj(ref, Map.merge(obj, %{map_data() => new_data, "size" => map_size(new_data)}))
    Map.has_key?(data, key)
  end

  defp weak_delete(_, this), do: require_map_ref!(this)

  defp clear(_, this) do
    ref = require_strong_map_ref!(this)
    obj = Heap.get_obj(ref, %{})
    Heap.put_obj(ref, %{obj | map_data() => %{}, "size" => 0, key_order() => []})
    :undefined
  end

  defp keys(_, this) do
    ref = require_strong_map_ref!(this)
    order = Heap.get_obj(ref, %{}) |> Map.get(key_order(), []) |> Enum.reverse()
    Heap.wrap_iterator(order)
  end

  defp values(_, this) do
    ref = require_strong_map_ref!(this)
    obj = Heap.get_obj(ref, %{})
    data = Map.get(obj, map_data(), %{})
    order = Map.get(obj, key_order(), []) |> Enum.reverse()
    Heap.wrap_iterator(Enum.map(order, &Map.get(data, &1)))
  end

  defp entries(_, this) do
    ref = require_strong_map_ref!(this)
    obj = Heap.get_obj(ref, %{})
    data = Map.get(obj, map_data(), %{})
    order = Map.get(obj, key_order(), []) |> Enum.reverse()
    items = Enum.map(order, fn key -> Heap.wrap([key, Map.get(data, key)]) end)
    Heap.wrap_iterator(items)
  end

  defp entry_to_kv([k, v | _]), do: {k, v}
  defp entry_to_kv([k]), do: {k, :undefined}

  defp entry_to_kv({:obj, eref}) do
    case Heap.get_obj(eref, []) do
      [k, v | _] ->
        {k, v}

      [k] ->
        {k, :undefined}

      {:qb_arr, arr} ->
        list = :array.to_list(arr)

        case list do
          [k, v | _] -> {k, v}
          [k] -> {k, :undefined}
          _ -> {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end

  defp entry_to_kv({:qb_arr, arr}) do
    list = :array.to_list(arr)

    case list do
      [k, v | _] -> {k, v}
      [k] -> {k, :undefined}
      _ -> {nil, nil}
    end
  end

  defp entry_to_kv(_), do: {nil, nil}

  defp for_each([callback | rest], this) do
    ref = require_strong_map_ref!(this)

    unless Builtin.callable?(callback) do
      JSThrow.type_error!("callbackfn is not a function")
    end

    this_arg = List.first(rest) || :undefined
    for_each_live(ref, callback, this_arg, ordered_keys(ref))
  end

  defp for_each(_, this) do
    require_strong_map_ref!(this)
    JSThrow.type_error!("callbackfn is not a function")
  end

  defp for_each_live(_ref, _callback, _this_arg, []), do: :undefined

  defp for_each_live(ref, callback, this_arg, [key | _]) do
    data = Heap.get_obj(ref, %{}) |> Map.get(map_data(), %{})

    case Map.fetch(data, key) do
      {:ok, value} ->
        Invocation.invoke_with_receiver(callback, [value, key, {:obj, ref}], this_arg)

      :error ->
        :ok
    end

    for_each_live(ref, callback, this_arg, keys_after_current(ref, key))
  end

  defp ordered_keys(ref), do: Heap.get_obj(ref, %{}) |> Map.get(key_order(), []) |> Enum.reverse()

  defp keys_after_current(ref, key) do
    keys = ordered_keys(ref)

    case Enum.find_index(keys, &(&1 == key)) do
      nil -> keys
      index -> Enum.drop(keys, index + 1)
    end
  end
end
