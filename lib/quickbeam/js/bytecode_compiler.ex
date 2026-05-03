defmodule QuickBEAM.JS.BytecodeCompiler do
  @moduledoc """
  Experimental JavaScript AST-to-QuickJS-bytecode compiler.

  This compiler is intentionally separate from `QuickBEAM.VM.Compiler`, which
  lowers existing QuickJS bytecode to BEAM code. This module starts from
  `QuickBEAM.JS.Parser` AST and emits `%QuickBEAM.VM.Bytecode{}` values.
  """

  alias QuickBEAM.JS.BytecodeCompiler.{Declarations, Expressions, FunctionBuilder, Scope}
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

  defp compile_statements([], _scope, instructions, constants), do: {:ok, instructions, constants}

  defp compile_statements([statement], scope, instructions, constants) do
    compile_statement(statement, scope, instructions, constants, tail?: true)
  end

  defp compile_statements([statement | rest], scope, instructions, constants) do
    with {:ok, instructions, constants} <-
           compile_statement(statement, scope, instructions, constants, tail?: false) do
      compile_statements(rest, scope, instructions, constants)
    end
  end

  defp compile_non_tail_statements([], _scope, instructions, constants, _opts),
    do: {:ok, instructions, constants}

  defp compile_non_tail_statements([statement | rest], scope, instructions, constants, opts) do
    opts = Keyword.put(opts, :tail?, false)

    with {:ok, instructions, constants} <-
           compile_statement(statement, scope, instructions, constants, opts) do
      compile_non_tail_statements(rest, scope, instructions, constants, opts)
    end
  end

  defp compile_statement(
         %AST.ExpressionStatement{
           expression: %AST.AssignmentExpression{
             operator: "=",
             left: %AST.MemberExpression{
               object: object,
               property: %AST.Identifier{name: property},
               computed: false
             },
             right: right
           }
         },
         scope,
         instructions,
         constants,
         opts
       ) do
    with {:ok, instructions, constants} <-
           compile_expression(object, scope, instructions, constants),
         {:ok, instructions, constants} <-
           compile_expression(right, scope, instructions, constants) do
      if Keyword.fetch!(opts, :tail?) do
        {:ok, instructions ++ [:insert2, {:put_field, property}, {:set_loc, 0}], constants}
      else
        {:ok, instructions ++ property_assignment_statement_suffix(scope, property), constants}
      end
    end
  end

  defp compile_statement(
         %AST.ExpressionStatement{
           expression: %AST.AssignmentExpression{
             operator: "=",
             left: %AST.Identifier{name: name},
             right: right
           }
         },
         scope,
         instructions,
         constants,
         opts
       ) do
    with slot when slot != :error <- resolve(scope, name),
         {:ok, instructions, constants} <-
           compile_expression(right, scope, instructions, constants) do
      if Keyword.fetch!(opts, :tail?) do
        {:ok, instructions ++ [write_slot(slot), {:set_loc, 0}], constants}
      else
        {:ok, instructions ++ [put_slot(slot)], constants}
      end
    else
      :error -> {:error, {:unsupported, {:unresolved_identifier, name}}}
      {:error, _} = error -> error
    end
  end

  defp compile_statement(
         %AST.ExpressionStatement{expression: expression},
         scope,
         instructions,
         constants,
         opts
       ) do
    with {:ok, instructions, constants} <-
           compile_expression(expression, scope, instructions, constants) do
      if Keyword.fetch!(opts, :tail?) do
        {:ok, instructions ++ [{:set_loc, 0}], constants}
      else
        {:ok, instructions ++ [{:put_loc, 0}], constants}
      end
    end
  end

  defp compile_statement(
         %AST.VariableDeclaration{declarations: declarations},
         scope,
         instructions,
         constants,
         _opts
       ) do
    Enum.reduce_while(declarations, {:ok, instructions, constants}, fn declaration,
                                                                       {:ok, ins, consts} ->
      case compile_declarator(declaration, scope, ins, consts) do
        {:ok, ins, consts} -> {:cont, {:ok, ins, consts}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp compile_statement(
         %AST.FunctionDeclaration{id: %AST.Identifier{name: name}} = declaration,
         scope,
         instructions,
         constants,
         _opts
       ) do
    with {:ok, function} <- compile_function(declaration, name) do
      case resolve(scope, name) do
        {:loc, loc} ->
          {:ok, instructions ++ [{:closure, length(constants)}, {:put_loc, loc}],
           [function | constants]}

        :error ->
          {:error, {:unsupported, {:unresolved_identifier, name}}}
      end
    end
  end

  defp compile_statement(
         %AST.ReturnStatement{} = statement,
         scope,
         instructions,
         constants,
         _opts
       ) do
    compile_return(statement, scope, instructions, constants)
  end

  defp compile_statement(
         %AST.IfStatement{test: test, consequent: consequent, alternate: alternate},
         scope,
         instructions,
         constants,
         opts
       ) do
    else_label = unique_label(:else)
    end_label = unique_label(:endif)

    with {:ok, instructions, constants} <-
           compile_expression(test, scope, instructions, constants),
         {:ok, instructions, constants} <-
           compile_statement(
             consequent,
             scope,
             instructions ++ [{:jump_if_false, else_label}],
             constants,
             opts
           ),
         {:ok, instructions, constants} <-
           compile_if_alternate(
             alternate,
             scope,
             instructions ++ [{:jump, end_label}, {:label, else_label}],
             constants,
             opts
           ) do
      {:ok, instructions ++ [{:label, end_label}], constants}
    end
  end

  defp compile_statement(
         %AST.WhileStatement{test: test, body: body},
         scope,
         instructions,
         constants,
         _opts
       ) do
    start_label = unique_label(:while_start)
    end_label = unique_label(:while_end)

    with {:ok, instructions, constants} <-
           compile_expression(test, scope, instructions ++ [{:label, start_label}], constants),
         {:ok, instructions, constants} <-
           compile_statement(
             body,
             scope,
             instructions ++ [{:jump_if_false, end_label}],
             constants,
             tail?: false,
             break_label: end_label,
             continue_label: start_label
           ) do
      {:ok, instructions ++ [{:jump, start_label}, {:label, end_label}], constants}
    end
  end

  defp compile_statement(%AST.ForStatement{} = statement, scope, instructions, constants, _opts) do
    test_label = unique_label(:for_test)
    update_label = unique_label(:for_update)
    end_label = unique_label(:for_end)

    with {:ok, instructions, constants} <-
           compile_for_init(statement.init, scope, instructions, constants),
         {:ok, instructions, constants} <-
           compile_for_test(
             statement.test,
             scope,
             instructions ++ [{:label, test_label}],
             constants,
             end_label
           ),
         {:ok, instructions, constants} <-
           compile_statement(
             statement.body,
             scope,
             instructions,
             constants,
             tail?: false,
             break_label: end_label,
             continue_label: update_label
           ),
         {:ok, instructions, constants} <-
           compile_for_update(
             statement.update,
             scope,
             instructions ++ [{:label, update_label}],
             constants
           ) do
      {:ok, instructions ++ [{:jump, test_label}, {:label, end_label}], constants}
    end
  end

  defp compile_statement(%AST.BreakStatement{}, _scope, instructions, constants, opts) do
    case Keyword.fetch(opts, :break_label) do
      {:ok, label} -> {:ok, instructions ++ [{:jump, label}], constants}
      :error -> {:error, {:unsupported, :break_outside_loop}}
    end
  end

  defp compile_statement(%AST.ContinueStatement{}, _scope, instructions, constants, opts) do
    case Keyword.fetch(opts, :continue_label) do
      {:ok, label} -> {:ok, instructions ++ [{:jump, label}], constants}
      :error -> {:error, {:unsupported, :continue_outside_loop}}
    end
  end

  defp compile_statement(%AST.BlockStatement{body: body}, scope, instructions, constants, opts) do
    if Keyword.fetch!(opts, :tail?) do
      compile_statements(body, scope, instructions, constants)
    else
      compile_non_tail_statements(body, scope, instructions, constants, opts)
    end
  end

  defp compile_statement(%AST.EmptyStatement{}, _scope, instructions, constants, _opts),
    do: {:ok, instructions, constants}

  defp compile_statement(statement, _scope, _instructions, _constants, _opts),
    do: {:error, {:unsupported, statement.type}}

  defp compile_if_alternate(nil, _scope, instructions, constants, tail?: true),
    do: {:ok, instructions ++ [:undefined, {:set_loc, 0}], constants}

  defp compile_if_alternate(nil, _scope, instructions, constants, _opts),
    do: {:ok, instructions, constants}

  defp compile_if_alternate(alternate, scope, instructions, constants, opts),
    do: compile_statement(alternate, scope, instructions, constants, opts)

  defp compile_for_init(nil, _scope, instructions, constants), do: {:ok, instructions, constants}

  defp compile_for_init(%AST.VariableDeclaration{} = declaration, scope, instructions, constants),
    do: compile_statement(declaration, scope, instructions, constants, tail?: false)

  defp compile_for_init(expression, scope, instructions, constants) do
    with {:ok, instructions, constants} <-
           compile_expression(expression, scope, instructions, constants) do
      {:ok, instructions ++ [{:put_loc, 0}], constants}
    end
  end

  defp compile_for_test(nil, _scope, instructions, constants, _end_label),
    do: {:ok, instructions, constants}

  defp compile_for_test(test, scope, instructions, constants, end_label) do
    with {:ok, instructions, constants} <-
           compile_expression(test, scope, instructions, constants) do
      {:ok, instructions ++ [{:jump_if_false, end_label}], constants}
    end
  end

  defp compile_for_update(nil, _scope, instructions, constants),
    do: {:ok, instructions, constants}

  defp compile_for_update(update, scope, instructions, constants) do
    with {:ok, instructions, constants} <-
           compile_expression(update, scope, instructions, constants) do
      {:ok, instructions ++ [{:put_loc, 0}], constants}
    end
  end

  defp compile_declarator(
         %AST.VariableDeclarator{id: %AST.Identifier{name: name}, init: nil},
         scope,
         instructions,
         constants
       ) do
    case resolve(scope, name) do
      {:loc, loc} -> {:ok, instructions ++ [:undefined, {:put_loc, loc}], constants}
      :error -> {:error, {:unsupported, {:unresolved_identifier, name}}}
    end
  end

  defp compile_declarator(
         %AST.VariableDeclarator{id: %AST.Identifier{name: name}, init: init},
         scope,
         instructions,
         constants
       ) do
    with {:loc, loc} <- resolve(scope, name),
         {:ok, instructions, constants} <-
           compile_expression(init, scope, instructions, constants) do
      {:ok, instructions ++ [{:put_loc, loc}], constants}
    else
      :error -> {:error, {:unsupported, {:unresolved_identifier, name}}}
      {:error, _} = error -> error
    end
  end

  defp compile_return(%AST.ReturnStatement{argument: nil}, _scope, instructions, constants),
    do: {:ok, instructions ++ [:undefined, :return], constants}

  defp compile_return(%AST.ReturnStatement{argument: argument}, scope, instructions, constants) do
    with {:ok, instructions, constants} <-
           compile_expression(argument, scope, instructions, constants) do
      {:ok, instructions ++ [:return], constants}
    end
  end

  defp compile_expression(expression, scope, instructions, constants) do
    callbacks = %{
      compile_expression: &compile_expression/4,
      compile_function: &compile_function/2,
      resolve: &resolve/2,
      unique_label: &unique_label/1
    }

    Expressions.compile(expression, scope, instructions, constants, callbacks)
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

  defp write_slot({:loc, index}), do: {:set_loc, index}
  defp write_slot({:arg, index}), do: {:set_arg, index}

  defp put_slot({:loc, index}), do: {:put_loc, index}
  defp put_slot({:arg, index}), do: {:put_arg, index}

  defp property_assignment_statement_suffix(scope, property) do
    case resolve(scope, "<ret>") do
      {:loc, 0} -> [:insert2, {:put_field, property}, {:put_loc, 0}]
      _ -> [{:put_field, property}]
    end
  end

  defp unique_label(prefix), do: {prefix, System.unique_integer([:positive])}

  defp resolve(scope, name), do: Scope.resolve(scope, name)

  defp identifier_name!(%AST.Identifier{name: name}), do: name
end
