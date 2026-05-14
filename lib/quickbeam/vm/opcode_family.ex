defmodule QuickBEAM.VM.OpcodeFamily do
  @moduledoc "Canonical opcode-family metadata shared by lowering and interpreter adapters."

  @call [:call, :call0, :call1, :call2, :call3]
  @get_slot [
    :get_arg,
    :get_arg0,
    :get_arg1,
    :get_arg2,
    :get_arg3,
    :get_loc,
    :get_loc0,
    :get_loc1,
    :get_loc2,
    :get_loc3,
    :get_loc8
  ]
  @put_slot [
    :put_loc,
    :put_loc0,
    :put_loc1,
    :put_loc2,
    :put_loc3,
    :put_loc8,
    :put_arg,
    :put_arg0,
    :put_arg1,
    :put_arg2,
    :put_arg3
  ]
  @set_slot [
    :set_loc,
    :set_loc0,
    :set_loc1,
    :set_loc2,
    :set_loc3,
    :set_loc8,
    :set_arg,
    :set_arg0,
    :set_arg1,
    :set_arg2,
    :set_arg3
  ]
  @small_int_push %{
    push_minus1: -1,
    push_0: 0,
    push_1: 1,
    push_2: 2,
    push_3: 3,
    push_4: 4,
    push_5: 5,
    push_6: 6,
    push_7: 7
  }

  defguard is_call(name) when name in @call
  defguard is_get_slot(name) when name in @get_slot
  defguard is_put_slot(name) when name in @put_slot
  defguard is_set_slot(name) when name in @set_slot
  defguard is_small_int_push(name) when is_map_key(@small_int_push, name)

  def call?(name), do: name in @call
  def get_slot?(name), do: name in @get_slot
  def put_slot?(name), do: name in @put_slot
  def set_slot?(name), do: name in @set_slot

  def small_int_push(name), do: Map.fetch(@small_int_push, name)
end
