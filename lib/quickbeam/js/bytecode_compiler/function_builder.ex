defmodule QuickBEAM.JS.BytecodeCompiler.FunctionBuilder do
  @moduledoc false

  alias QuickBEAM.JS.BytecodeCompiler.Assembler
  alias QuickBEAM.VM.Bytecode.Function
  alias QuickBEAM.VM.Bytecode.VarDef

  def build(opts) do
    instructions = Keyword.fetch!(opts, :instructions)
    args = Keyword.fetch!(opts, :args)
    locals = Keyword.fetch!(opts, :locals)
    extra_atoms = Assembler.atoms(instructions)

    function = %Function{
      name: Keyword.fetch!(opts, :name),
      filename: "<elixir-bytecode-compiler>",
      line_num: 1,
      col_num: 1,
      arg_count: length(args),
      var_count: length(locals),
      defined_arg_count: Keyword.get(opts, :defined_arg_count, length(args)),
      stack_size: Assembler.stack_size(instructions),
      locals: Keyword.get(opts, :local_defs, Enum.map(args ++ locals, &var_def/1)),
      var_ref_count: Keyword.get(opts, :var_ref_count, 0),
      closure_vars: Keyword.get(opts, :closure_vars, []),
      constants: Keyword.fetch!(opts, :constants),
      extra_atoms: extra_atoms,
      byte_code: <<>>,
      has_prototype: Keyword.fetch!(opts, :has_prototype),
      has_simple_parameter_list: Keyword.fetch!(opts, :has_simple_parameter_list),
      new_target_allowed: Keyword.fetch!(opts, :new_target_allowed),
      arguments_allowed: true,
      is_strict_mode: false,
      has_debug_info: false,
      source: Keyword.fetch!(opts, :source)
    }

    atoms = collect_atoms(function)
    resolved = to_interpreter_format(instructions, atoms)

    %{
      function
      | byte_code: Assembler.encode(instructions, atoms),
        atoms: atoms,
        instructions: resolved
    }
    |> attach_own_constant_atoms()
  end

  defp to_interpreter_format(instructions, atoms) do
    atom_map =
      atoms
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Map.new()

    {labels, _} =
      Enum.reduce(instructions, {%{}, 0}, fn
        {:label, name}, {map, pc} -> {Map.put(map, name, pc), pc}
        _, {map, pc} -> {map, pc + 1}
      end)

    instructions
    |> Enum.reject(&match?({:label, _}, &1))
    |> Enum.map(&to_op(&1, labels, atom_map))
    |> List.to_tuple()
  end

  @op QuickBEAM.VM.Opcodes.all_opcodes()

  defp to_op(true, _l, _a), do: {@op[:push_true], []}
  defp to_op(false, _l, _a), do: {@op[:push_false], []}
  defp to_op({:push_int, v}, _l, _a), do: {@op[:push_i32], [v]}
  defp to_op({:constant, idx}, _l, _a), do: {@op[:push_const], [idx]}
  defp to_op({:closure, idx}, _l, _a), do: {@op[:fclosure], [idx]}
  defp to_op({:jump, t}, l, _a), do: {@op[:goto], [l[t]]}
  defp to_op({:jump_if_false, t}, l, _a), do: {@op[:if_false], [l[t]]}
  defp to_op({:jump_if_true, t}, l, _a), do: {@op[:if_true], [l[t]]}
  defp to_op({:catch, t}, l, _a), do: {@op[:catch], [l[t]]}
  defp to_op({:gosub, t}, l, _a), do: {@op[:gosub], [l[t]]}
  defp to_op({:get_var, n}, _l, a), do: {@op[:get_var], [a[n]]}
  defp to_op({:put_var, n}, _l, a), do: {@op[:put_var], [a[n]]}
  defp to_op({:get_field, n}, _l, a), do: {@op[:get_field], [a[n]]}
  defp to_op({:get_field2, n}, _l, a), do: {@op[:get_field2], [a[n]]}
  defp to_op({:put_field, n}, _l, a), do: {@op[:put_field], [a[n]]}
  defp to_op({:define_field, n}, _l, a), do: {@op[:define_field], [a[n]]}
  defp to_op({:set_name, n}, _l, a), do: {@op[:set_name], [a[n]]}
  defp to_op({:define_method, n, f}, _l, a), do: {@op[:define_method], [a[n], f]}
  defp to_op({:define_method_computed, f}, _l, _a), do: {@op[:define_method_computed], [f]}
  defp to_op({:define_class, n, f}, _l, a), do: {@op[:define_class], [a[n], f]}
  defp to_op({:private_symbol, n}, _l, a), do: {@op[:private_symbol], [a[n]]}
  defp to_op({:throw_error, type, n}, _l, a), do: {@op[:throw_error], [a[n], type]}
  defp to_op({:with_get_var, n, t}, l, a), do: {@op[:with_get_var], [a[n], l[t], 1]}
  defp to_op({:with_put_var, n, t}, l, a), do: {@op[:with_put_var], [a[n], l[t], 1]}
  defp to_op({:with_delete_var, n, t}, l, a), do: {@op[:with_delete_var], [a[n], l[t], 1]}
  defp to_op({:eval, argc, scope}, _l, _a), do: {@op[:eval], [argc, scope]}
  defp to_op({op, arg}, _l, _a) when is_atom(op), do: {@op[op], [arg]}
  defp to_op(op, _l, _a) when is_atom(op), do: {@op[op], []}

  defp attach_own_constant_atoms(%Function{atoms: atoms, constants: constants} = function) do
    constants =
      for c <- constants do
        case c do
          %Function{atoms: nil} -> attach_atoms(c, atoms)
          %Function{} -> c
          _ -> c
        end
      end

    %{function | constants: constants}
  end

  def collect_atoms(%Function{} = function) do
    function
    |> do_collect_atoms([])
    |> Enum.reject(&(match?({:predefined, _}, &1) or is_nil(&1)))
    |> Enum.uniq()
    |> List.to_tuple()
  end

  def attach_atoms(%Function{} = function, atoms) do
    function
    |> Map.put(:atoms, atoms)
    |> Map.update!(:constants, &attach_constant_atoms(&1, atoms))
  end

  def var_def(name) do
    %VarDef{
      name: name,
      scope_level: 0,
      scope_next: 0,
      var_kind: 0,
      is_const: false,
      is_lexical: false,
      is_captured: false
    }
  end

  defp do_collect_atoms(%Function{} = function, acc) do
    acc = [function.name, function.filename | acc]
    acc = Enum.reduce(function.extra_atoms || [], acc, &[&1 | &2])
    acc = Enum.reduce(function.locals, acc, fn %VarDef{name: name}, acc -> [name | acc] end)

    Enum.reduce(function.constants, acc, fn
      %Function{} = inner, acc -> do_collect_atoms(inner, acc)
      value, acc when is_binary(value) -> [value | acc]
      _value, acc -> acc
    end)
  end

  defp attach_constant_atoms(constants, atoms) do
    for constant <- constants do
      case constant do
        %Function{atoms: own} when own != nil and own != {} -> constant
        %Function{} -> attach_atoms(constant, atoms)
        _ -> constant
      end
    end
  end
end
