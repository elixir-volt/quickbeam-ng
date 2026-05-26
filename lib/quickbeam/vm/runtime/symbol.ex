defmodule QuickBEAM.VM.Runtime.Symbol do
  @moduledoc "JS `Symbol` built-in: constructor, global symbol registry (`Symbol.for`/`keyFor`), and well-known symbol constants."

  use QuickBEAM.VM.Builtin

  alias QuickBEAM.VM.{Heap, JSThrow}

  alias QuickBEAM.VM.Semantics.Values

  defintrinsic "Symbol" do
    constructor(constructor(), length: 0, phase: :fundamental)

    prototype extends: :object do
      method "toString", receiver: :symbol do
        Values.stringify(this)
      end

      method "valueOf", receiver: :symbol do
        this
      end

      getter "description" do
        symbol_description(this)
      end

      symbol :toPrimitive do
        method length: 1, writable: false, configurable: false do
          symbol_value(this)
        end
      end

      to_string_tag("Symbol")
    end
  end

  def constructor do
    fn
      _args, {:obj, _} ->
        JSThrow.type_error!("Symbol is not a constructor")

      args, _this ->
        desc =
          case args do
            [] ->
              :undefined

            [:undefined | _] ->
              :undefined

            [s | _] when is_binary(s) ->
              s

            [{:symbol, _} | _] ->
              JSThrow.type_error!("Cannot convert a Symbol value to a string")

            [{:symbol, _, _} | _] ->
              JSThrow.type_error!("Cannot convert a Symbol value to a string")

            [value | _] ->
              QuickBEAM.VM.Semantics.Values.stringify(value)
          end

        {:symbol, desc, make_ref()}
    end
  end

  constant("iterator", {:symbol, "Symbol.iterator"})
  constant("toPrimitive", {:symbol, "Symbol.toPrimitive"})
  constant("hasInstance", {:symbol, "Symbol.hasInstance"})
  constant("toStringTag", {:symbol, "Symbol.toStringTag"})
  constant("asyncIterator", {:symbol, "Symbol.asyncIterator"})
  constant("asyncDispose", {:symbol, "Symbol.asyncDispose"})
  constant("dispose", {:symbol, "Symbol.dispose"})
  constant("isConcatSpreadable", {:symbol, "Symbol.isConcatSpreadable"})
  constant("species", {:symbol, "Symbol.species"})
  constant("match", {:symbol, "Symbol.match"})
  constant("matchAll", {:symbol, "Symbol.matchAll"})
  constant("replace", {:symbol, "Symbol.replace"})
  constant("search", {:symbol, "Symbol.search"})
  constant("split", {:symbol, "Symbol.split"})
  constant("unscopables", {:symbol, "Symbol.unscopables"})

  def well_known_symbol_names, do: static_property_names()

  defp symbol_value(symbol) do
    QuickBEAM.VM.Builtin.require_receiver!(:symbol, symbol)
  end

  defp symbol_description(this) do
    case symbol_value(this) do
      {:symbol, :undefined} -> :undefined
      {:symbol, :undefined, _} -> :undefined
      {:symbol, description} -> description
      {:symbol, description, _} -> description
    end
  end

  static "for", length: 1 do
    value = arg(args, 0, :undefined)

    key =
      case value do
        {:symbol, _} -> JSThrow.type_error!("Cannot convert a Symbol value to a string")
        {:symbol, _, _} -> JSThrow.type_error!("Cannot convert a Symbol value to a string")
        other -> QuickBEAM.VM.Semantics.Values.stringify(other)
      end

    case Heap.get_symbol(key) do
      nil ->
        sym = {:symbol, key}
        Heap.put_symbol(key, sym)
        sym

      existing ->
        existing
    end
  end

  static "keyFor", length: 1 do
    case arg(args, 0, :undefined) do
      {:symbol, key} = symbol ->
        if Heap.get_symbol(key) == symbol, do: key, else: :undefined

      {:symbol, _, _} ->
        :undefined

      _ ->
        JSThrow.type_error!("Symbol.keyFor requires a symbol")
    end
  end
end
