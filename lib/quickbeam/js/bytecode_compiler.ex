defmodule QuickBEAM.JS.BytecodeCompiler do
  @moduledoc """
  Experimental JavaScript AST-to-QuickJS-bytecode compiler.

  This compiler is intentionally separate from `QuickBEAM.VM.Compiler`, which
  lowers existing QuickJS bytecode to BEAM code. This module starts from
  `QuickBEAM.JS.Parser` AST and emits `%QuickBEAM.VM.Bytecode{}` values.
  """

  alias QuickBEAM.JS.BytecodeCompiler.{
    Declarations,
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
         {:ok, instructions, constants} <- compile_statements(body, scope, [], []) do
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

  defp compile_statements(statements, scope, instructions, constants) do
    Statements.compile_all(statements, scope, instructions, constants, callbacks())
  end

  defp compile_expression(expression, scope, instructions, constants) do
    Expressions.compile(expression, scope, instructions, constants, callbacks())
  end

  defp compile_function(function, name) do
    params = Enum.map(function.params, &identifier_name!/1)
    scope = Scope.new(params)

    with {:ok, scope} <- Declarations.declare_program_locals(function.body.body, scope),
         {:ok, instructions, constants} <- compile_statements(function.body.body, scope, [], []) do
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

  defp callbacks do
    %{
      compile_expression: &compile_expression/4,
      compile_function: &compile_function/2,
      resolve: &resolve/2,
      unique_label: &unique_label/1
    }
  end

  defp unique_label(prefix), do: {prefix, System.unique_integer([:positive])}

  defp resolve(scope, name), do: Scope.resolve(scope, name)

  defp identifier_name!(%AST.Identifier{name: name}), do: name
end
