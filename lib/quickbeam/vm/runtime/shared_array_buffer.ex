defmodule QuickBEAM.VM.Runtime.SharedArrayBuffer do
  @moduledoc "JS `SharedArrayBuffer` builtin prototype operations."

  import QuickBEAM.VM.Heap.Keys
  use QuickBEAM.VM.Builtin

  alias QuickBEAM.VM.Heap
  alias QuickBEAM.VM.JSThrow
  alias QuickBEAM.VM.Runtime
  alias QuickBEAM.VM.Runtime.ArrayBuffer
  alias QuickBEAM.VM.Runtime.TypedArrayCoercion

  @max_array_buffer_length 4_294_967_295

  defintrinsic "SharedArrayBuffer" do
    constructor length: 1, phase: :fundamental do
      construct(args, this)
    end

    prototype extends: :object do
      getter "byteLength" do
        byte_length(this)
      end

      getter "maxByteLength" do
        max_byte_length(this)
      end

      getter "growable" do
        growable(this)
      end

      method "grow", length: 1 do
        grow(this, args)
      end

      method "slice", length: 2 do
        slice(this, args)
      end

      to_string_tag("SharedArrayBuffer")
    end
  end

  def construct(args, {:obj, ref} = this) do
    result = ArrayBuffer.constructor(args, this)
    object = Heap.get_obj(ref, %{})

    Heap.put_obj(
      ref,
      Map.merge(object, %{
        "__array_buffer_kind__" => :shared_array_buffer,
        :__internal_proto__ => Runtime.global_class_proto("SharedArrayBuffer")
      })
    )

    result
  end

  def construct(_args, _this),
    do: JSThrow.type_error!("SharedArrayBuffer constructor requires 'new'")

  static_methods do
    symbol :species do
      get do
        this
      end
    end
  end

  def byte_length(this) do
    this
    |> shared_array_buffer_map!()
    |> Map.get("byteLength", 0)
  end

  def max_byte_length(this) do
    map = shared_array_buffer_map!(this)

    if Map.get(map, "resizable"),
      do: Map.get(map, "maxByteLength", Map.get(map, "byteLength", 0)),
      else: Map.get(map, "byteLength", 0)
  end

  def growable(this) do
    this
    |> shared_array_buffer_map!()
    |> Map.get("resizable")
    |> Kernel.||(false)
  end

  def grow({:obj, ref} = this, args) do
    map = shared_array_buffer_map!(this)

    unless Map.get(map, "resizable") do
      JSThrow.type_error!("SharedArrayBuffer is not growable")
    end

    new_size = args |> arg(0, :undefined) |> array_buffer_index!()
    old_size = Map.get(map, "byteLength", 0)

    cond do
      new_size < old_size ->
        JSThrow.range_error!("new length is smaller than byteLength")

      new_size > Map.get(map, "maxByteLength", old_size) ->
        JSThrow.range_error!("new length exceeds maxByteLength")

      true ->
        old_buf = Map.get(map, buffer(), <<>>)

        Heap.put_obj(
          ref,
          Map.merge(map, %{
            buffer() => resized_buffer(old_buf, new_size),
            "byteLength" => new_size
          })
        )

        :undefined
    end
  end

  def grow(_this, _args), do: JSThrow.type_error!("receiver is not a SharedArrayBuffer")

  def slice({:obj, _ref} = this, args) do
    map = shared_array_buffer_map!(this)
    buf = Map.get(map, buffer(), <<>>)
    len = byte_size(buf)

    start =
      case args do
        [value | _] -> normalize_index(TypedArrayCoercion.integer_or_infinity(value), len)
        _ -> 0
      end

    finish =
      case args do
        [_, :undefined | _] -> len
        [_, value | _] -> normalize_index(TypedArrayCoercion.integer_or_infinity(value), len)
        _ -> len
      end

    new_len = max(0, finish - start)
    copy = if new_len > 0, do: binary_part(buf, start, new_len), else: <<>>

    Heap.wrap(%{
      buffer() => copy,
      "byteLength" => new_len,
      "resizable" => false,
      "__array_buffer_kind__" => :shared_array_buffer,
      proto() => Runtime.global_class_proto("SharedArrayBuffer")
    })
  end

  def slice(_this, _args), do: JSThrow.type_error!("receiver is not a SharedArrayBuffer")

  defp shared_array_buffer_map!({:obj, ref}) do
    case Heap.get_obj(ref, %{}) do
      map when is_map(map) and is_map_key(map, buffer()) and not is_map_key(map, typed_array()) ->
        if Map.get(map, "__array_buffer_kind__") == :shared_array_buffer do
          map
        else
          JSThrow.type_error!("receiver is not a SharedArrayBuffer")
        end

      _ ->
        JSThrow.type_error!("receiver is not a SharedArrayBuffer")
    end
  end

  defp shared_array_buffer_map!(_), do: JSThrow.type_error!("receiver is not a SharedArrayBuffer")

  defp array_buffer_index!(value) do
    index = TypedArrayCoercion.index(value)

    if index > @max_array_buffer_length do
      JSThrow.range_error!("Invalid SharedArrayBuffer length")
    end

    index
  end

  defp resized_buffer(buffer, new_size) do
    old_size = byte_size(buffer)

    cond do
      new_size == old_size -> buffer
      new_size < old_size -> binary_part(buffer, 0, new_size)
      true -> buffer <> :binary.copy(<<0>>, new_size - old_size)
    end
  end

  defp normalize_index(:infinity, length), do: length
  defp normalize_index(:neg_infinity, _length), do: 0
  defp normalize_index(index, length) when index < 0, do: max(0, length + index)
  defp normalize_index(index, length), do: min(index, length)
end
