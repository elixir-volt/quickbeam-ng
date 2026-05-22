defmodule QuickBEAM.VM.Semantics.DirectEval do
  @moduledoc "Direct-eval preparation helpers kept outside the interpreter dispatch loop."

  alias QuickBEAM.JS.Error, as: JSError

  alias QuickBEAM.VM.{
    BytecodeParser,
    Function,
    Heap,
    JSThrow,
    Names,
    Opcodes,
    PredefinedAtoms,
    RuntimeState,
    Value
  }

  alias QuickBEAM.VM.Semantics.Eval, as: EvalSemantics

  @op_define_var Opcodes.num(:define_var)
  @op_check_define_var Opcodes.num(:check_define_var)
  @op_define_func Opcodes.num(:define_func)

  def strict_code(ctx, code) do
    if strict_mode?(ctx), do: "\"use strict\";\n" <> code, else: code
  end

  def compile(nil, code), do: QuickBEAM.JS.Compiler.compile(code)

  def compile(runtime_pid, code) do
    case QuickBEAM.Runtime.compile(runtime_pid, code) do
      {:ok, bc} -> BytecodeParser.decode(bc)
      error -> error
    end
  end

  def reject_lexical_conflicts!(ctx, declared_names) do
    EvalSemantics.reject_lexical_conflicts!(ctx, declared_names, strict_mode?(ctx))
  end

  def declared_names(%Function{} = fun, atoms, instructions_fun)
      when is_function(instructions_fun, 1) do
    local_names =
      fun.locals
      |> Enum.map(&Names.resolve_display_name(&1.name))
      |> Enum.filter(&is_binary/1)

    instruction_names =
      case instructions_fun.(fun) do
        {:ok, insns} -> Enum.reduce(insns, [], &collect_declared_instruction_name(&1, &2, atoms))
        _ -> []
      end

    MapSet.new(local_names ++ instruction_names)
  end

  def declared_names(_, _, _), do: MapSet.new()

  def handle_compile_error({:error, {:parse_error, errors}}),
    do: JSThrow.syntax_error!(parse_error_message(errors))

  def handle_compile_error({:error, msg}) when is_binary(msg), do: JSThrow.syntax_error!(msg)

  def handle_compile_error({:error, %JSError{name: name, message: msg}}),
    do: throw({:js_throw, QuickBEAM.VM.Heap.make_error(msg, name)})

  def handle_compile_error(_), do: {:undefined, %{}}

  def merge_var_object_globals(globals, []), do: globals

  def merge_var_object_globals(globals, var_objs) do
    Enum.reduce(var_objs, globals, fn
      {:obj, ref}, acc ->
        case Heap.get_obj(ref, %{}) do
          map when is_map(map) -> Map.merge(acc, map)
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  def collect_captured_globals({:closure, captured, %Function{closure_vars: closure_vars}}) do
    Enum.reduce(closure_vars, %{}, fn closure_var, acc ->
      case Names.resolve_display_name(closure_var.name) do
        name when is_binary(name) ->
          val =
            case Map.get(captured, capture_key(closure_var), :undefined) do
              {:cell, ref} -> Heap.get_cell(ref)
              other -> other
            end

          Map.put(acc, name, val)

        _ ->
          acc
      end
    end)
  end

  def collect_captured_globals(_), do: %{}

  def collect_caller_locals(locals, %{current_func: current_func, arg_buf: arg_buf}) do
    case current_func do
      {:closure, _, %Function{locals: local_defs, arg_count: arg_count}} ->
        build_local_map(local_defs, arg_count, arg_buf, locals)

      %Function{locals: local_defs, arg_count: arg_count} ->
        build_local_map(local_defs, arg_count, arg_buf, locals)

      _ ->
        %{}
    end
  end

  def scoped_globals(ctx_globals, eval_scope_globals, declared_names, keep_declared?) do
    base_globals =
      if keep_declared?,
        do: Map.drop(ctx_globals, MapSet.to_list(declared_names)),
        else: ctx_globals

    scoped_globals =
      if keep_declared?,
        do: Map.drop(eval_scope_globals, MapSet.to_list(declared_names)),
        else: eval_scope_globals

    {base_globals, scoped_globals, Map.merge(base_globals, scoped_globals)}
  end

  def install_eval_arguments(merged_globals, ctx) do
    arguments_key = RuntimeState.arguments_object_key(ctx.current_func, ctx.arg_buf)
    {arguments_obj, created?} = eval_arguments_object(merged_globals, ctx, arguments_key)
    {Map.put(merged_globals, "arguments", arguments_obj), arguments_key, arguments_obj, created?}
  end

  def visible_declared_names(base_globals, eval_scope_globals, declared_names, assigned_names) do
    base_globals
    |> Map.merge(eval_scope_globals)
    |> Map.put("arguments", :present)
    |> Map.keys()
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
    |> MapSet.intersection(MapSet.union(declared_names, assigned_names))
  end

  def abrupt_visible_names(base_globals, eval_scope_globals) do
    base_globals
    |> Map.merge(eval_scope_globals)
    |> Map.put("arguments", :present)
    |> Map.keys()
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  def put_created_arguments(globals, true, key, arguments), do: Map.put(globals, key, arguments)
  def put_created_arguments(globals, false, _key, _arguments), do: globals

  def filter_local_transients(%{current_func: current_func}, transients) do
    case current_func do
      %Function{name: {:predefined, 81}} -> transients
      {:closure, _, %Function{name: {:predefined, 81}}} -> transients
      %Function{locals: locals} -> Map.drop(transients, local_names(locals))
      {:closure, _, %Function{locals: locals}} -> Map.drop(transients, local_names(locals))
      _ -> transients
    end
  end

  defp eval_arguments_object(merged_globals, ctx, arguments_key) do
    case Map.fetch(merged_globals, arguments_key) do
      {:ok, arguments} ->
        {arguments, false}

      :error ->
        case Map.fetch(merged_globals, "arguments") do
          {:ok, arguments} -> {arguments, false}
          :error -> cached_or_new_arguments(ctx, arguments_key)
        end
    end
  end

  defp cached_or_new_arguments(ctx, arguments_key) do
    case RuntimeState.get_arguments_object(arguments_key) do
      nil ->
        arguments =
          Heap.wrap_arguments(Tuple.to_list(ctx.arg_buf),
            strict: strict_mode?(ctx),
            callee: ctx.current_func
          )

        RuntimeState.put_arguments_object(arguments_key, arguments)
        {arguments, true}

      arguments ->
        {arguments, true}
    end
  end

  defp local_names(locals) do
    locals
    |> Enum.map(&Names.resolve_display_name(&1.name))
    |> Enum.filter(&is_binary/1)
  end

  defp build_local_map(local_defs, arg_count, arg_buf, locals) do
    local_defs
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {local, idx}, acc ->
      with name when is_binary(name) <- local.name,
           val when val != :undefined <- local_value(idx, arg_count, arg_buf, locals) do
        Map.put(acc, name, val)
      else
        _ -> acc
      end
    end)
  end

  defp local_value(idx, _arg_count, arg_buf, _locals) when idx < tuple_size(arg_buf) do
    elem(arg_buf, idx)
  end

  defp local_value(idx, _arg_count, _arg_buf, locals) do
    if idx < tuple_size(locals), do: elem(locals, idx), else: :undefined
  end

  defp capture_key(%{closure_type: type, var_idx: idx}), do: {type, idx}

  defp collect_declared_instruction_name({op, [atom_ref, _scope]}, acc, atoms)
       when op in [@op_define_var, @op_check_define_var] do
    prepend_declared_atom(atom_ref, acc, atoms)
  end

  defp collect_declared_instruction_name({@op_define_func, [atom_ref, _flags]}, acc, atoms) do
    prepend_declared_atom(atom_ref, acc, atoms)
  end

  defp collect_declared_instruction_name(_, acc, _atoms), do: acc

  defp prepend_declared_atom(atom_ref, acc, atoms) do
    case resolve_declared_atom(atom_ref, atoms) do
      name when is_binary(name) -> [name | acc]
      _ -> acc
    end
  end

  defp parse_error_message([%{message: message} | _]), do: message
  defp parse_error_message(_errors), do: "Syntax error"

  defp strict_mode?(ctx), do: Value.strict_context?(ctx)

  defp resolve_declared_atom({:predefined, idx}, _atoms), do: PredefinedAtoms.lookup(idx)

  defp resolve_declared_atom(idx, atoms)
       when is_integer(idx) and idx >= 0 and idx < tuple_size(atoms),
       do: elem(atoms, idx)

  defp resolve_declared_atom(name, _atoms) when is_binary(name), do: name
  defp resolve_declared_atom(_, _atoms), do: nil
end
