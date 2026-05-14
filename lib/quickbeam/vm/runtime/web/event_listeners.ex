defmodule QuickBEAM.VM.Runtime.Web.EventListeners do
  @moduledoc "Shared listener storage and dispatch helpers for EventTarget-like Web APIs."

  alias QuickBEAM.VM.ObjectModel.Get
  alias QuickBEAM.VM.Runtime.Web.{Callback, StateRef}

  @doc "Creates a listener store reference."
  def new, do: StateRef.new(%{})

  @doc "Adds a listener entry for an event type."
  def add(listeners_ref, type, callback, opts \\ nil) do
    type = to_string(type)
    entry = %{"callback" => callback, "once" => once?(opts)}

    StateRef.update(listeners_ref, %{}, fn listeners ->
      Map.update(listeners, type, [entry], &(&1 ++ [entry]))
    end)
  end

  @doc "Removes listener entries matching callback for an event type."
  def remove(listeners_ref, type, callback) do
    type = to_string(type)

    StateRef.update(listeners_ref, %{}, fn listeners ->
      listeners
      |> Map.get(type, [])
      |> Enum.reject(&(Map.get(&1, "callback") == callback))
      |> then(&Map.put(listeners, type, &1))
    end)
  end

  @doc "Dispatches an Event object and honors stopImmediatePropagation/defaultPrevented."
  def dispatch_event(listeners_ref, event) do
    type = event |> Get.get("type") |> to_string()
    dispatch(listeners_ref, type, [event], fn -> Get.get(event, "__stop_immediate__") == true end)
    Get.get(event, "defaultPrevented") != true
  end

  @doc "Dispatches callbacks for a plain event type."
  def dispatch_type(listeners_ref, type, args \\ []) do
    dispatch(listeners_ref, type, args, fn -> false end)
    :ok
  end

  defp dispatch(listeners_ref, type, args, stopped?) do
    listeners = StateRef.get(listeners_ref, %{})
    type_listeners = Map.get(listeners, to_string(type), [])

    {survivors, _stopped?} =
      Enum.reduce(type_listeners, {[], false}, fn
        entry, {survivors, true} ->
          {[entry | survivors], true}

        entry, {survivors, false} ->
          entry
          |> Map.get("callback")
          |> Callback.safe_invoke(args)

          keep? = not Map.get(entry, "once", false)
          survivors = if keep?, do: [entry | survivors], else: survivors
          {survivors, stopped?.()}
      end)

    StateRef.put(listeners_ref, Map.put(listeners, to_string(type), Enum.reverse(survivors)))
  end

  defp once?({:obj, _} = opts), do: Get.get(opts, "once") == true
  defp once?(_), do: false
end
