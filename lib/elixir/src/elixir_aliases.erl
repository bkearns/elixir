-module(elixir_aliases).
-export([last/1, concat/1, safe_concat/1, format_error/1,
         ensure_loaded/3, ensure_loaded/4, expand/4, store/7]).
-include("elixir.hrl").

%% Store an alias in the given scope
store(_Meta, New, New, _TKV, Aliases, MacroAliases, _Lexical) ->
  { Aliases, MacroAliases };
store(Meta, New, Old, TKV, Aliases, MacroAliases, Lexical) ->
  record_warn(Meta, New, TKV, Lexical),
  NewAliases = orddict:store(New, Old, Aliases),

  case lists:keymember(context, 1, Meta) of
    true  -> { NewAliases, orddict:store(New, Old, MacroAliases) };
    false -> { NewAliases, MacroAliases }
  end.

record_warn(Meta, Ref, Opts, Lexical) ->
  Warn =
    case lists:keyfind(warn, 1, Opts) of
      { warn, false } -> false;
      { warn, true } -> true;
      false -> not lists:keymember(context, 1, Meta)
    end,
  elixir_lexical:record_alias(Ref, ?line(Meta), Warn, Lexical).

%% Expand an alias. It returns an atom (meaning that there
%% was an expansion) or a list of atoms.

expand({ '__aliases__', Meta, _ } = Alias, Aliases, MacroAliases, LexicalTracker) ->
  case lists:keyfind(alias, 1, Meta) of
    { alias, false } ->
      expand(Alias, MacroAliases, LexicalTracker);
    { alias, Atom } when is_atom(Atom) ->
      case expand(Alias, MacroAliases, LexicalTracker) of
        OtherAtom when is_atom(OtherAtom) -> OtherAtom;
        OtherAliases when is_list(OtherAliases) -> Atom
      end;
    false ->
      expand(Alias, Aliases, LexicalTracker)
  end.

expand({ '__aliases__', _Meta, [H] }, Aliases, LexicalTracker) when H /= 'Elixir' ->
  case expand_one(H, Aliases, LexicalTracker) of
    false -> [H];
    Atom  -> Atom
  end;

expand({ '__aliases__', _Meta, [H|T] }, Aliases, LexicalTracker) when is_atom(H) ->
  case H of
    'Elixir' ->
      concat(T);
    _ ->
      case expand_one(H, Aliases, LexicalTracker) of
        false -> [H|T];
        Atom  -> concat([Atom|T])
      end
  end;

expand({ '__aliases__', _Meta, List }, _Aliases, _LexicalTracker) ->
  List.

expand_one(H, Aliases, LexicalTracker) ->
  Lookup = list_to_atom("Elixir." ++ atom_to_list(H)),
  case lookup(Lookup, Aliases) of
    Lookup -> false;
    Else ->
      elixir_lexical:record_alias(Lookup, LexicalTracker),
      Else
  end.

%% Ensure a module is loaded before its usage.

ensure_loaded(Line, Ref, S) ->
  ensure_loaded(Line, S#elixir_scope.file, Ref, S#elixir_scope.context_modules).

ensure_loaded(_Line, _File, 'Elixir.Kernel', _FileModules) ->
  ok;

ensure_loaded(Line, File, Ref, FileModules) ->
  try
    Ref:module_info(compile)
  catch
    error:undef ->
      Kind = case lists:member(Ref, FileModules) of
        true  -> scheduled_module;
        false -> unloaded_module
      end,
      elixir_errors:form_error(Line, File, ?MODULE, { Kind, Ref })
  end.

%% Receives an atom and returns the last bit as an alias.

last(Atom) ->
  Last = last(lists:reverse(atom_to_list(Atom)), []),
  list_to_atom("Elixir." ++ Last).

last([$.|_], Acc) -> Acc;
last([H|T], Acc) -> last(T, [H|Acc]);
last([], Acc) -> Acc.

%% Receives a list of atoms, binaries or lists
%% representing modules and concatenates them.

concat(Args)      -> binary_to_atom(do_concat(Args), utf8).
safe_concat(Args) -> binary_to_existing_atom(do_concat(Args), utf8).

do_concat([H|T]) when is_atom(H), H /= nil ->
  do_concat([atom_to_binary(H, utf8)|T]);
do_concat([<<"Elixir.", _/binary>>=H|T]) ->
  do_concat(T, H);
do_concat([<<"Elixir">>=H|T]) ->
  do_concat(T, H);
do_concat(T) ->
  do_concat(T, <<"Elixir">>).

do_concat([nil|T], Acc) ->
  do_concat(T, Acc);
do_concat([H|T], Acc) when is_atom(H) ->
  do_concat(T, <<Acc/binary, $., (to_partial(atom_to_binary(H, utf8)))/binary>>);
do_concat([H|T], Acc) when is_binary(H) ->
  do_concat(T, <<Acc/binary, $., (to_partial(H))/binary>>);
do_concat([], Acc) ->
  Acc.

to_partial(<<"Elixir.", Arg/binary>>) -> Arg;
to_partial(<<".", Arg/binary>>)       -> Arg;
to_partial(Arg) when is_binary(Arg)   -> Arg.

%% Lookup an alias in the current scope.

lookup(Else, Dict) ->
  case orddict:find(Else, Dict) of
    { ok, Value } when Value /= Else -> lookup(Value, Dict);
    _ -> Else
  end.

%% Errors

format_error({unloaded_module, Module}) ->
  io_lib:format("module ~ts is not loaded and could not be found", [elixir_errors:inspect(Module)]);

format_error({scheduled_module, Module}) ->
  io_lib:format("module ~ts is not loaded but was defined. This happens because you are trying to use a module in the same context it is defined. Try defining the module outside the context that requires it.",
    [elixir_errors:inspect(Module)]).