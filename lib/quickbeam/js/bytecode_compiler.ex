defmodule QuickBEAM.JS.BytecodeCompiler do
  @moduledoc """
  Experimental JavaScript AST-to-QuickJS-bytecode compiler.

  This compiler is intentionally separate from `QuickBEAM.VM.Compiler`, which
  lowers existing QuickJS bytecode to BEAM code. This module starts from
  `QuickBEAM.JS.Parser` AST and emits `%QuickBEAM.VM.Bytecode{}` values.
  """

  alias QuickBEAM.JS.BytecodeCompiler.{
    Declarations,
    Emitter,
    Expressions,
    FunctionBuilder,
    Scope,
    Statements
  }

  alias QuickBEAM.JS.Parser
  alias QuickBEAM.JS.Parser.AST
  alias QuickBEAM.VM.Bytecode
  alias QuickBEAM.VM.Bytecode.Writer

  @ret_name {:predefined, 82}

  @type compile_error :: {:unsupported, term()} | {:parse_error, term()}

  @spec compile(binary() | struct()) :: {:ok, Bytecode.t()} | {:error, compile_error()}
  def compile(source) when is_binary(source) do
    with {:ok, ast} <- parse(source), do: compile(ast)
  end

  def compile(%AST.Program{source_type: :script} = program) do
    with {:ok, fun} <- compile_program(program) do
      atoms = FunctionBuilder.collect_atoms(fun)

      {:ok,
       %Bytecode{
         version: QuickBEAM.VM.Opcodes.bc_version(),
         atoms: atoms,
         value: FunctionBuilder.attach_atoms(fun, atoms)
       }}
    end
  end

  def compile(%AST.Program{source_type: source_type}),
    do: {:error, {:unsupported, {:source_type, source_type}}}

  def compile_to_binary(source) do
    with {:ok, bytecode} <- compile(source), do: Writer.encode(bytecode)
  end

  def compile_to_function(source) do
    with {:ok, %Bytecode{value: value}} <- compile(source), do: {:ok, value}
  end

  defp parse(source) do
    case Parser.parse(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, _program, errors} -> {:error, {:parse_error, errors}}
    end
  end

  defp compile_program(%AST.Program{body: body}) do
    scope = Scope.declare_local(Scope.new(), "<ret>")

    with {:ok, scope} <- Declarations.declare_program_locals(body, scope),
         {:ok, instructions, constants} <-
           compile_statements(body, scope, [], [], top_level_globals(scope)) do
      instructions = finish_program(instructions)

      {:ok,
       FunctionBuilder.build(
         name: nil,
         args: [],
         locals: [@ret_name | Enum.drop(scope.local_names, 1)],
         constants: Enum.reverse(constants),
         instructions: instructions,
         has_prototype: false,
         has_simple_parameter_list: false,
         new_target_allowed: false,
         source: ""
       )}
    end
  end

  defp compile_statements(statements, scope, instructions, constants, globals) do
    Statements.compile_all(
      statements,
      Emitter.new(scope, instructions, constants, callbacks(globals))
    )
  end

  defp compile_expression(expression, scope, instructions, constants, globals) do
    Expressions.compile(
      expression,
      Emitter.new(scope, instructions, constants, callbacks(globals))
    )
  end

  defp compile_function(function, name, globals) do
    {params, defaults} = normalize_params(function.params)
    scope = Scope.new(params, globals)

    with {:ok, scope} <- Declarations.declare_program_locals(function.body.body, scope),
         {:ok, instructions, constants} <-
           compile_param_defaults(defaults, scope, [], [], globals),
         {:ok, instructions, constants} <-
           compile_statements(function.body.body, scope, instructions, constants, globals) do
      instructions = ensure_function_return(instructions)

      {:ok,
       FunctionBuilder.build(
         name: name,
         args: params,
         locals: scope.local_names,
         constants: Enum.reverse(constants),
         instructions: instructions,
         has_prototype: true,
         has_simple_parameter_list: true,
         new_target_allowed: true,
         source: ""
       )}
    end
  end

  defp finish_program([]), do: [:undefined, {:set_loc, 0}, :return]
  defp finish_program(instructions), do: instructions ++ [:return]

  defp ensure_function_return([]), do: [:return_undef]

  defp ensure_function_return(instructions) do
    if List.last(instructions) in [:return, :return_undef],
      do: instructions,
      else: instructions ++ [:return_undef]
  end

  defp callbacks(globals) do
    %{
      compile_expression: fn expression, scope, instructions, constants ->
        compile_expression(expression, scope, instructions, constants, globals)
      end,
      compile_function: fn function, name -> compile_function(function, name, globals) end,
      resolve: &resolve/2,
      unique_label: &unique_label/1
    }
  end

  defp unique_label(prefix), do: {prefix, System.unique_integer([:positive])}

  defp resolve(scope, name), do: Scope.resolve(scope, name)

  defp top_level_globals(scope), do: Enum.drop(scope.local_names, 1)

  defp normalize_params(params) do
    Enum.map_reduce(params, [], fn
      %AST.Identifier{name: name}, defaults ->
        {name, defaults}

      %AST.AssignmentPattern{left: %AST.Identifier{name: name}, right: default}, defaults ->
        {name, defaults ++ [{name, default}]}

      param, _defaults ->
        raise FunctionClauseError, function: :identifier_name!, arity: 1, args: [param]
    end)
  end

  defp compile_param_defaults([], _scope, instructions, constants, _globals),
    do: {:ok, instructions, constants}

  defp compile_param_defaults([{name, default} | rest], scope, instructions, constants, globals) do
    end_label = unique_label(:default_param_end)
    slot = Scope.resolve(scope, name)

    with {:ok, instructions, constants} <-
           compile_expression(
             default,
             scope,
             instructions ++
               [
                 QuickBEAM.JS.BytecodeCompiler.Slots.read(slot),
                 :undefined,
                 :strict_eq,
                 {:jump_if_false, end_label}
               ],
             constants,
             globals
           ) do
      compile_param_defaults(
        rest,
        scope,
        instructions ++ [QuickBEAM.JS.BytecodeCompiler.Slots.put(slot), {:label, end_label}],
        constants,
        globals
      )
    end
  end
end
