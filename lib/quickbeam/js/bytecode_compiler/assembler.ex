defmodule QuickBEAM.JS.BytecodeCompiler.Assembler do
  @moduledoc false

  alias QuickBEAM.VM.Opcodes

  def encode(instructions) when is_list(instructions) do
    instructions
    |> Enum.map(&encode_instruction/1)
    |> IO.iodata_to_binary()
  end

  def stack_size(instructions) when is_list(instructions) do
    instructions
    |> Enum.reduce({0, 0}, fn instruction, {depth, max_depth} ->
      {pops, pushes} = stack_effect(instruction)
      depth = max(depth - pops, 0) + pushes
      {depth, max(max_depth, depth)}
    end)
    |> elem(1)
  end

  defp encode_instruction({:push_int, value}) when value in 0..7 do
    <<Opcodes.num(String.to_atom("push_#{value}"))>>
  end

  defp encode_instruction({:push_int, value}) when value in -128..127 do
    <<Opcodes.num(:push_i8), value::signed-8>>
  end

  defp encode_instruction({:push_int, value}) when value in -32_768..32_767 do
    <<Opcodes.num(:push_i16), value::signed-little-16>>
  end

  defp encode_instruction({:constant, index}) when index in 0..255,
    do: <<Opcodes.num(:push_const8), index>>

  defp encode_instruction({:closure, index}) when index in 0..255,
    do: <<Opcodes.num(:fclosure8), index>>

  defp encode_instruction({:get_arg, index}) when index in 0..3 do
    <<Opcodes.num(String.to_atom("get_arg#{index}"))>>
  end

  defp encode_instruction({:get_loc, index}) when index in 0..3 do
    <<Opcodes.num(String.to_atom("get_loc#{index}"))>>
  end

  defp encode_instruction({:get_loc, index}) when index in 0..255,
    do: <<Opcodes.num(:get_loc8), index>>

  defp encode_instruction({:put_loc, index}) when index in 0..3 do
    <<Opcodes.num(String.to_atom("put_loc#{index}"))>>
  end

  defp encode_instruction({:put_loc, index}) when index in 0..255,
    do: <<Opcodes.num(:put_loc8), index>>

  defp encode_instruction({:set_loc, index}) when index in 0..3 do
    <<Opcodes.num(String.to_atom("set_loc#{index}"))>>
  end

  defp encode_instruction({:set_loc, index}) when index in 0..255,
    do: <<Opcodes.num(:set_loc8), index>>

  defp encode_instruction({:call, argc}) when argc in 0..3 do
    <<Opcodes.num(String.to_atom("call#{argc}"))>>
  end

  defp encode_instruction(:undefined), do: <<Opcodes.num(:undefined)>>
  defp encode_instruction(:null), do: <<Opcodes.num(:null)>>
  defp encode_instruction(true), do: <<Opcodes.num(:push_true)>>
  defp encode_instruction(false), do: <<Opcodes.num(:push_false)>>
  defp encode_instruction(:add), do: <<Opcodes.num(:add)>>
  defp encode_instruction(:sub), do: <<Opcodes.num(:sub)>>
  defp encode_instruction(:mul), do: <<Opcodes.num(:mul)>>
  defp encode_instruction(:div), do: <<Opcodes.num(:div)>>
  defp encode_instruction(:mod), do: <<Opcodes.num(:mod)>>
  defp encode_instruction(:return), do: <<Opcodes.num(:return)>>
  defp encode_instruction(:return_undef), do: <<Opcodes.num(:return_undef)>>

  defp stack_effect({:call, argc}), do: {1 + argc, 1}

  defp stack_effect({_op, _arg} = instruction),
    do: instruction |> encode_instruction() |> opcode_stack_effect()

  defp stack_effect(instruction), do: instruction |> encode_instruction() |> opcode_stack_effect()

  defp opcode_stack_effect(<<op, _rest::binary>>) do
    {_name, _size, pops, pushes, _format} = Opcodes.info(op)
    {pops, pushes}
  end
end
