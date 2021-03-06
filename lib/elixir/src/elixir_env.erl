-module(elixir_env).
-include("elixir.hrl").
-export([ex_to_env/1, env_to_scope/1, env_to_scope_with_vars/2,
         ex_to_scope/1, scope_to_ex/1]).

%% Conversion in between #elixir_env, #elixir_scope and Macro.Env

ex_to_env(Env) when element(1, Env) == 'Elixir.Macro.Env' ->
  erlang:setelement(1, Env, elixir_env).

env_to_scope(#elixir_env{module=Module,file=File,
    function=Function,aliases=Aliases,context=Context,
    requires=Requires,macros=Macros,functions=Functions,
    macro_functions=MacroFunctions,macro_macros=MacroMacros,
    context_modules=ContextModules,macro_aliases=MacroAliases,
    lexical_tracker=Lexical}) ->
  #elixir_scope{module=Module,file=File,
    function=Function,aliases=Aliases,context=Context,
    requires=Requires,macros=Macros,functions=Functions,
    macro_functions=MacroFunctions,macro_macros=MacroMacros,
    context_modules=ContextModules,macro_aliases=MacroAliases,
    lexical_tracker=Lexical}.

env_to_scope_with_vars(#elixir_env{} = Env, Vars) ->
  (env_to_scope(Env))#elixir_scope{
    vars=orddict:from_list(Vars),
    counter=[{'',length(Vars)}]
  }.

scope_to_ex({ Line, #elixir_scope{module=Module,file=File,
    function=Function,aliases=Aliases,context=Context,
    requires=Requires,macros=Macros,functions=Functions,
    context_modules=ContextModules,macro_aliases=MacroAliases,
    macro_functions=MacroFunctions, macro_macros=MacroMacros,
    vars=Vars,lexical_tracker=Lexical} }) when is_integer(Line) ->
  { 'Elixir.Macro.Env', Module, File, Line, Function, Context, Requires, Aliases,
    Functions, Macros, MacroAliases, MacroFunctions, MacroMacros, ContextModules,
    [Pair || { Pair, _ } <- Vars], Lexical }.

ex_to_scope(Env) ->
  env_to_scope(ex_to_env(Env)).
