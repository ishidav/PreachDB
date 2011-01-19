%% @doc Contains routines for dynamically rebalancing a fragmented table.
%%
%% In order to use fragmentron you should create your table via 
%% fragmentron:create_table/2 , then add or remove nodes via
%% fragmentron:add_node/2 and fragmentron:remove_node/2 as the node 
%% pool changes.  You can change the targets n_ram_copies, n_disc_copies,
%% n_disc_only_copies, and n_external_copies via fragmentron:change_targets/2.
%% You can rebalance a table (e.g. in response to node failure) via
%% fragmentron:rebalance_table/1. Finally should you wish to delete
%% your table use fragmentron:delete_table/1.  NB: n_external_copies
%% is only supported if mnesia storage api extensions are detected at
%% compile time.

-module (fragmentron).
-export ([ add_node/2, 
           change_targets/2,
           create_table/2, 
           delete_table/1,
           rebalance_table/1,
           remove_node/2 ]).

-include_lib ("mnesia/src/mnesia.hrl").

-ifdef (MNESIA_EXT).
-define (if_mnesia_ext (X, Y), X).
-else.
-define (if_mnesia_ext (X, Y), Y).
-endif.

%-=====================================================================-
%-                                Public                               -
%-=====================================================================-

% This entire situation is made more challenging by the fact that 
% schema operations cannot occur in nested transactions.
%
% This includes:
% mnesia:create_table/2, mnesia:change_table_frag/2, 
% mnesia:add_table_copy/3, mnesia:del_table_copy/2,
% mnesia:delete_table/1
%
% So we'll need to protect these operations outside of mnesia somehow,
% to prevent simultaneous invocation.  two choices i considered where
% gen_leader and global.  i went with global because it's standard.

%% @spec add_node (atom (), node ()) -> bool () | { aborted, Reason }
%% @doc Add a node to a table.
%% Adds the specified node to the specified table, then dynamically
%% rebalances the fragments.  Returns true if this resulted in a 
%% configuration change.
%% @end

add_node (TableName, Node) ->
  try
    case foreign_table (TableName) of
      [] ->
        ensure_schema_extra_table (),
        ensure_add_node_to_table (TableName, Node),
        rebalance_table (TableName);
      { ForeignTable, Key } ->
        { aborted, { combine_error,
                    TableName,
                    "Op only allowed via foreign table",
                    { foreign_key, { ForeignTable, Key } } } }
    end
  catch
    X : Y -> 
      { aborted, { X, Y } }
  end.

%% @spec change_targets (atom (), [ { target (), integer () } ]) -> bool () | { aborted, Reason }
%%   target () = n_ram_copies | n_disc_copies | n_disc_only_copies | n_external_copies
%% @doc Change the target number of copies for a table.
%% Changes the target numbers, then dynamically rebalances the fragments
%% to achieve the new target.  Returns true if this resulted in a 
%% configuration change.  WARNING: Does not ensure that the new targets
%% are feasible. NB: n_external_copies is only support if mnesia storage
%% extensions are detected at compile time.
%% @end

change_targets (TableName, Targets) when is_list (Targets) ->
  try
    case validate_targets (TableName, Targets) of
      true ->
        { atomic, ok } = 
          mnesia:sync_transaction 
            (fun () -> 
               lists:foreach (fun ({ Target, Value }) 
                                when Target =:= n_ram_copies;
                                     %Target =:= n_disc_copies;
                                     %?if_mnesia_ext (Target =:= n_external_copies;,)
                                     ?if_mnesia_ext (Target =:= n_disc_copies; Target =:= n_external_copies;,Target =:= n_disc_copies;)
                                     Target =:= n_disc_only_copies,
                                     Value >= 0 ->
                                ok = mnesia:write ({ schema_extra, 
                                                     { TableName, Target }, 
                                                     Value })
                              end,
                              Targets)
             end),
        case foreign_table (TableName) of
          [] ->
            rebalance_table (TableName);
          { ForeignTable, _ } ->
            synchronize_placement (ForeignTable, TableName)
        end;
      false ->
        { aborted, bad_copy_spec }
    end
  catch
    X : Y ->
      { aborted, { X, Y } }
  end.

%% @spec create_table (atom (), table_definition ()) -> ok | { aborted, Reason }
%% @doc Create a fragmented table to be managed by fragmentron.
%% The table_definition is as in mnesia:create_table/2.
%% @end

create_table (TableName, TabDef) ->
  try
    case validate_initial_copies (TabDef) of
      false ->
        { aborted, bad_copy_spec };
      true ->
        case fast_create_table (TableName, create_tabdef (TabDef)) of
          { atomic, ok } -> 
            case lists:keysearch (frag_properties, 1, TabDef) of
              false -> 
                { atomic, ok };
              { value, { frag_properties, FragProps } } ->
                ensure_schema_extra_table (),
    
                { NRamCopies,
                  NDiscCopies,
                  NExternalCopies,
                  NDiscOnlyCopies } = 
                  case foreign_table (TableName) of
                    [] -> 
                      copies_from_fragprops (FragProps);
                    { F, _ } ->
                      copies_from_fragprops 
                        (FragProps, 
                         mnesia:async_dirty (fun () -> copies (F) end))
                  end,
    
                { atomic, ok } = 
                  mnesia:sync_transaction (
                    fun () ->
                      mnesia:write ({ schema_extra, 
                                      { TableName, n_ram_copies }, 
                                      NRamCopies }),
                      mnesia:write ({ schema_extra,
                                      { TableName, n_disc_copies }, 
                                      NDiscCopies }),
		      ?if_mnesia_ext (mnesia:write ({ schema_extra, { TableName, n_external_copies }, NExternalCopies }), ok),
                      mnesia:write ({ schema_extra,
                                      { TableName, n_disc_only_copies },
                                      NDiscOnlyCopies })
                    end),
      
                case foreign_table (TableName) of
                  [] -> 
                    rebalance_table (TableName),
                    { atomic, ok };
                  { ForeignTable, _ } ->
                    { atomic, ok } = 
                      mnesia:sync_transaction (
                        fun () ->
                          mnesia:write ({ schema_extra,
                                          { ForeignTable,
                                            foreign_ref,
                                            TableName },
                                          void })
                        end),
                    synchronize_placement (ForeignTable, 
                                           TableName,
                                           NRamCopies,
                                           NDiscCopies,
                                           NExternalCopies,
                                           NDiscOnlyCopies),
                    { atomic, ok }
                end
            end;
          R -> 
            R
        end
    end
  catch
    X : Y ->
      { aborted, { X, Y } }
  end.

%% @spec delete_table (atom ()) -> bool ()
%% @doc Delete a fragmented table managed by fragmentron.  Returns true
%% if this resulted in a configuration change.
%% @end

delete_table (TableName) ->
  LockId = { { ?MODULE, TableName }, self () },

  global:set_lock (LockId),

  try 
    { atomic, ok } = fast_delete_table (TableName),
    mnesia:sync_transaction (
      fun () -> 
        ok = mnesia:delete_object ({ schema_extra, { TableName, '_' }, '_' }),
        ok = mnesia:delete_object ({ schema_extra, 
                                     { TableName, foreign_ref, '_' },
                                     '_' }),
        % NB: technically if mnesia:delete_table/1 returned { atomic, ok }
        % then the table should not have any foreign references, however,
        % it is possible that outside fragmentron the foreign key was dropped,
        % something we don't support right now, but just to keep things from
        % getting totally f'd, do the full table scan here, since the 
        % table is small.
        ok = mnesia:delete_object ({ schema_extra, 
                                     { '_', foreign_ref, TableName },
                                     '_' })
      end),
    mnesia:report_event ({ fragmentron, delete_table, TableName })
  after
    global:del_lock (LockId)
  end.

%% @spec rebalance_table (atom ()) -> bool () | { aborted, Reason }
%% @doc Rebalance a table managed by fragmentron, without changing 
%% the targets or node pool.  This could be, for example, in response 
%% to a node going down.
%% Returns true if this resulted in a configuration change.
%% @end

rebalance_table (TableName) ->
  LockId = { { ?MODULE, TableName }, self () },

  global:set_lock (LockId),

  try
    case foreign_table (TableName) of
      [] ->
        rebalance_table_locked (TableName);
      { ForeignTable, Key } ->
        { aborted, { combine_error,
                     TableName,
                     "Op only allowed via foreign table",
                     { foreign_key, { ForeignTable, Key } } } }
    end
  catch
    X : Y ->
      { aborted, { X, Y } }
  after
    global:del_lock (LockId)
  end.

%% @spec remove_node (atom (), node ()) -> bool () | { aborted, Reason }
%% @doc Remove a node from a table.
%% Removes the specified node frome the specified table, then dynamically
%% rebalances the fragments.  WARNING: Does not ensure that the target 
%% allocation is possible after removal of the node.  Returns true
%% if this resulted in a configuration change.
%% @end

remove_node (TableName, Node) ->
  try
    case foreign_table (TableName) of
      [] ->
        ensure_schema_extra_table (),
        ensure_remove_node_from_table (TableName, Node),
      
        NFrags = num_frags (TableName),
      
        lists:foreach 
          (fun (FragNum) ->
             ensure_remove_table_copy (frag_table_name (TableName,
                                                        FragNum),
                                       Node)
           end,
           lists:seq (1, NFrags)),

        rebalance_table (TableName);
      { ForeignTable, Key } ->
        { aborted, { combine_error,
                     TableName,
                     "Op only allowed via foreign table",
                     { foreign_key, { ForeignTable, Key } } } }
    end
  catch
    X : Y ->
      { aborted, { X, Y } }
  end.

%-=====================================================================-
%-                               Private                               -
%-=====================================================================-

add_table_copies (_TableName, _CopyType, []) -> ok;
add_table_copies (TableName, CopyType, [ Node | Rest ]) ->
  ensure_table_copy (TableName, Node, CopyType),
  add_table_copies (TableName, CopyType, Rest).

base_table (TableName) ->
  FragProps = mnesia:table_info (TableName, frag_properties),
  case lists:keysearch (base_table, 1, FragProps) of
    { value, { base_table, Base } } -> Base;
    _ -> TableName
  end.

create_frag_props (Props) ->
  create_frag_props (Props, []).

%%% TODO: this only works if only one type of copy is specified > 0

create_frag_props ([], Acc) -> 
  lists:reverse (Acc);
create_frag_props ([ { X, N } | T ], Acc) when ((X =:= n_ram_copies) or 
                                                (X =:= n_disc_copies) or
                                                ?if_mnesia_ext ((X =:= n_external_copies), false) or
                                                (X =:= n_disc_only_copies)) 
                                               and (N > 0) ->
  create_frag_props (T, [ { X, 1 } | Acc ]);
create_frag_props ([ H | T ], Acc) ->
  create_frag_props (T, [ H | Acc ]).

create_tabdef (TabDef) ->
  create_tabdef (TabDef, []).

create_tabdef ([], Acc) -> 
  lists:reverse (Acc);
create_tabdef ([ { frag_properties, Props } | T ], Acc) ->
  create_tabdef (T, [ { frag_properties, create_frag_props (Props) } | Acc ]);
create_tabdef ([ H | T ], Acc) ->
  create_tabdef (T, [ H | Acc ]).

copies (TableName) ->
  L = [ _ | _ ] = 
    [ { Key, Value } 
      || { _, { _, Key }, Value } <- mnesia:match_object ({ schema_extra, 
                                                            { TableName, '_' }, 
                                                            '_' }) ],
  copies_from_fragprops (L).

copies_from_fragprops (FragProps) ->
  copies_from_fragprops (FragProps, { 1, 0, 0, 0 }).

copies_from_fragprops (FragProps, Default) ->
  NDiscOnlyCopies = 
    case lists:keysearch (n_disc_only_copies, 1, FragProps) of
      { value, { n_disc_only_copies, A } } -> A;
      false -> 0
    end,
  NDiscCopies = 
    case lists:keysearch (n_disc_copies, 1, FragProps) of
      { value, { n_disc_copies, B } } -> B;
      false -> 0
    end,
  NExternalCopies = 
    ?if_mnesia_ext (
      case lists:keysearch (n_external_copies, 1, FragProps) of
	{ value, { n_external_copies, D } } -> D;
	false -> 0
      end,
      0),
  NRamCopies = 
    case lists:keysearch (n_ram_copies, 1, FragProps) of
      { value, { n_ram_copies, C } } -> C;
      false -> 0
    end,
  case { NRamCopies, NDiscCopies, NExternalCopies, NDiscOnlyCopies } of
    { 0, 0, 0, 0 } -> Default;
    X -> X
  end.

copy_type (TableName, Node) ->
  case { lists:member (Node, mnesia:table_info (TableName, ram_copies)),
         lists:member (Node, mnesia:table_info (TableName, disc_copies)),
	 ?if_mnesia_ext (
	   lists:member (Node, mnesia:table_info (TableName, external_copies)),
	   false),
         lists:member (Node, mnesia:table_info (TableName, disc_only_copies)) }
    of
      { true, false, false, false } -> ram_copies;
      { false, true, false, false } -> disc_copies;
      %?if_mnesia_ext ({ false, false, true, false } -> external_copies;,)
      { false, false, true, false } -> external_copies;
      { false, false, false, true } -> disc_only_copies
  end.

enforce_targets (TableName) ->
  { atomic, { NFrags, 
              { NRamCopies, 
                NDiscCopies, 
                ?if_mnesia_ext (NExternalCopies, _NExternalCopies),
                NDiscOnlyCopies } } } =
    mnesia:sync_transaction (
      fun () ->
        FragProps = mnesia:table_info (TableName, frag_properties),
        { value, { n_fragments, NFrags } } = lists:keysearch (n_fragments,
                                                              1,
                                                              FragProps),
        { NFrags, copies (TableName) }
      end),

  enforce_targets (TableName, NFrags, ram_copies, NRamCopies, false) or
  enforce_targets (TableName, NFrags, disc_copies, NDiscCopies, false) or
  ?if_mnesia_ext (enforce_targets (TableName,
				   NFrags,
				   external_copies,
				   NExternalCopies,
				   false),
		  false) or
  enforce_targets (TableName, NFrags, disc_only_copies, NDiscOnlyCopies, false).

enforce_targets (TableName, FragNum, CopyType, NCopies, DidChange) 
    when FragNum > 0,
         NCopies >= 0 ->
  FragTableName = frag_table_name (TableName, FragNum),

  NewDidChange = 
    case length (used_nodes (FragTableName, CopyType)) of
      NCopies -> 
        DidChange;
      N when N < NCopies -> 
        Candidates = unused_running_nodes (TableName, FragNum),
        Sorted = [ C || 
                   { _, C } <- 
                     lists:sort ([ { num_frags_at (TableName, C), C } 
                                   || C <- Candidates ]) ],

        add_table_copies (FragTableName, 
                          CopyType, 
                          lists:sublist (Sorted, NCopies - N)),
        true;
      N when N > NCopies -> 
        Candidates = used_running_nodes (FragTableName, CopyType),
        Sorted = [ C || 
                   { _, C } <- 
                     lists:sort ([ { -num_frags_at (TableName, C), C } 
                                   || C <- Candidates ]) ],

        remove_table_copies (FragTableName, 
                             lists:sublist (Sorted, N - NCopies)),
        true
    end,
  enforce_targets (TableName, FragNum - 1, CopyType, NCopies, NewDidChange);
enforce_targets (_TableName, _FragNum, _CopyType, _NCopies, DidChange) -> 
  DidChange.

ensure_add_node_to_table (TableName, Node) ->
  case fast_change_table_frag (TableName, { add_node, Node }) of
    { atomic, ok } -> 
      mnesia:report_event ({ fragmentron, add_node, TableName, Node }),
      true;
    { aborted, { already_exists, TableName, Node } } -> false;
    { aborted, { combine_error, 
                 TableName,
                 "Op only allowed via foreign table",
                 { foreign_key, _ } } } -> false
  end.

ensure_remove_node_from_table (TableName, Node) ->
  case fast_change_table_frag (TableName, { del_node, Node }) of
    { atomic, ok } -> 
      mnesia:report_event ({ fragmentron, del_node, TableName, Node }),
      true;
    { aborted, { no_exists, TableName, Node } } -> false;
    { aborted, { combine_error, 
                 TableName,
                 "Op only allowed via foreign table",
                 { foreign_key, _ } } } -> false
  end.

ensure_remove_table_copy (TableName, Node) ->
  case fast_del_table_copy (TableName, Node) of
    { atomic, ok } -> 
      mnesia:report_event ({ fragmentron, del_table_copy, TableName, Node }),
      true;
    { aborted, { badarg, TableName, unknown } } -> 
      false
  end.

ensure_table (TableName, TabDef) ->
  case fast_create_table (TableName, TabDef) of
    { atomic, ok } -> 
      mnesia:report_event ({ fragmentron, create_table, TableName }),
      true;
    { aborted, { already_exists, TableName } } -> false
  end,
  ok = mnesia:wait_for_tables ([ TableName ], infinity).

ensure_table_copy (TableName, Node, external_copies) ->
  % TODO: does this require the table to be local (?)
  Cs = mnesia:table_info (TableName, cstruct),
  { external, _, Mod } = Cs#cstruct.type,
  ensure_table_copy (TableName, Node, { external_copies, Mod });
ensure_table_copy (TableName, Node, CopyType) ->
  case fast_add_table_copy (TableName, Node, CopyType) of
    { atomic, ok } -> 
      mnesia:report_event ({ fragmentron, add_table_copy, TableName, Node }),
      true;
    { aborted, { already_exists, TableName, Node } } -> 
      false
  end.

ensure_schema_extra_table () ->
  ensure_table (schema_extra, 
                [ { type, ordered_set },
                  { disc_copies, mnesia:system_info (running_db_nodes) } ]),
  ensure_table_copy (schema_extra, node (), disc_copies).

fast_change_table_frag (TableName, What = { add_node, Node }) ->
  try mnesia:table_info (TableName, frag_properties) of
    [] ->
      { aborted, { no_exists, TableName, frag_properties, frag_hash } };
    Props ->
      { value, { node_pool, Pool } } = lists:keysearch (node_pool, 1, Props),
      case lists:member (Node, Pool) of
        true -> { aborted, { already_exists, TableName, Node } };
        false -> mnesia:change_table_frag (TableName, What)
      end
  catch
    _ : _ ->
      { aborted, { no_exists, TableName, frag_properties, frag_hash } }
  end;
fast_change_table_frag (TableName, What = { del_node, Node }) ->
  try mnesia:table_info (TableName, frag_properties) of
    [] ->
      { aborted, { no_exists, TableName, frag_properties, frag_hash } };
    Props ->
      { value, { node_pool, Pool } } = lists:keysearch (node_pool, 1, Props),
      case lists:member (Node, Pool) of
        true -> mnesia:change_table_frag (TableName, What);
        false -> { aborted, { no_exists, TableName, Node } }
      end
  catch
    _ : _ ->
      { aborted, { no_exists, TableName, frag_properties, frag_hash } }
  end.

fast_create_table (TableName, TabDef) ->
  try mnesia:table_info (TableName, type),
      { aborted, { already_exists, TableName } }
  catch
    _ : _ ->
      mnesia:create_table (TableName, TabDef)
  end.

fast_add_table_copy (TableName, Node, CopyType) ->
  try lists:member (Node, used_nodes (TableName)) of
    true -> { aborted, { already_exists, TableName, Node } };
    false -> mnesia:add_table_copy (TableName, Node, CopyType)
  catch
    _ : _ ->
      { aborted, { no_exists, TableName } }
  end.

fast_change_table_copy_type (TableName, Node, CopyType) ->
  try { lists:member (Node, used_nodes (TableName)),
        lists:member (Node, used_nodes (TableName, CopyType)) } of
    { true, true } ->
      { aborted, { already_exists, TableName, Node, CopyType } };
    { true, false } ->
      mnesia:change_table_copy_type (TableName, Node, CopyType);
    { false, _ } ->
      { aborted, { no_exists, TableName, Node } }
  catch 
    _ : _ ->
      { aborted, { no_exists, TableName } }
  end.

fast_del_table_copy (TableName, Node) ->
  try lists:member (Node, used_nodes (TableName)) of
    true -> mnesia:del_table_copy (TableName, Node);
    false -> { aborted, { badarg, TableName, unknown } }
  catch
    _ : _ ->
      { aborted, { badarg, TableName, unknown } }
  end.

fast_delete_table (TableName) ->
  try mnesia:table_info (TableName, type),
      mnesia:delete_table (TableName)
  catch
    _ : _ ->
      { aborted, { no_exists, TableName } }
  end.

foreign_table (TableName) ->
  foreign_table (base_table (TableName), frag_number (TableName)).

foreign_table (BaseTable, FragNum) ->
  FragProps = mnesia:table_info (BaseTable, frag_properties),
  case lists:keysearch (foreign_key, 1, FragProps) of
    false -> 
      [];
    { value, { foreign_key, undefined } } -> 
      [];
    { value, { foreign_key, { Table, Key } } } -> 
      { frag_table_name (Table, FragNum), Key }
  end.

frag_number (TableName) when is_atom (TableName) -> 
  FragProps = mnesia:table_info (TableName, frag_properties),
  case lists:keysearch (base_table, 1, FragProps) of
    { value, { base_table, TableName } } ->
      1;
    { value, { base_table, Base } } -> 
      list_to_integer (string:substr (atom_to_list (TableName),
                                      length (atom_to_list (Base)) +
                                      length ("_frag") +
                                      1));
    _ -> 
      1
  end.

frag_table_name (TableName, 1) -> TableName;
frag_table_name (TableName, FragNum) when FragNum > 1 ->
  list_to_atom (atom_to_list (TableName) ++ 
                "_frag" ++ 
                integer_to_list (FragNum)).

fragments_by_node (TableName, NFrags) ->
  fragments_by_node 
    (TableName, 
     NFrags, 
     gb_trees:from_orddict ([ { Node, gb_sets:empty () } 
                              || Node <- lists:sort (node_pool (TableName)) ])).

fragments_by_node (TableName, FragNum, Map) when FragNum > 0 ->
  FragTableName = frag_table_name (TableName, FragNum),
  try_sanitize_table_copy (FragTableName),

  NewMap = 
    lists:foldl (fun (Node, M) -> 
                  case gb_trees:lookup (Node, M) of
                    { value, Value } ->
                      gb_trees:update (Node, gb_sets:add (FragNum, Value), M)
                  end
                 end,
                 Map,
                 intersect (used_nodes (FragTableName),
                            mnesia:system_info (db_nodes))),

  fragments_by_node (TableName, FragNum - 1, NewMap);
fragments_by_node (_TableName, _FragNum, Map) -> Map.

intersect (L, M) ->
  gb_sets:to_list (gb_sets:intersection (gb_sets:from_list (L), 
                                         gb_sets:from_list (M))).

inverse_foreign_tables (TableName) ->
  inverse_foreign_tables (base_table (TableName), frag_number (TableName)).

inverse_foreign_tables (BaseTable, FragNum) ->
  { atomic, L } =
    mnesia:sync_transaction (
      fun () ->
        [ frag_table_name (ForeignTable, FragNum) || 
          { _, { _, foreign_ref, ForeignTable }, void } 
            <- mnesia:match_object ({ schema_extra,
                                      { BaseTable, foreign_ref, '_' },
                                  void }) ]
    end),
  L.

least_overloaded (Map) ->
  lists:foldl (fun (Cur={ Node, Fragments }, Min={ MinNode, MinFragments }) ->
                case gb_sets:size (Fragments) - gb_sets:size (MinFragments) of
                  N when N > 0 -> Min;
                  N when N < 0 -> Cur;
                  0 -> if Node < MinNode -> Cur; 
                          true -> Min
                       end
                end
               end,
               gb_trees:smallest (Map),
               gb_trees:to_list (Map)).

most_overloaded (Map) ->
  lists:foldl (fun (Cur={ Node, Fragments }, Max={ MaxNode, MaxFragments }) ->
                case gb_sets:size (Fragments) - gb_sets:size (MaxFragments) of
                  N when N > 0 -> Cur;
                  N when N < 0 -> Max;
                  0 -> if Node > MaxNode -> Cur;
                          true -> Max
                       end
                end
               end,
               gb_trees:smallest (Map),
               gb_trees:to_list (Map)).

move_fragment (TableName, FragNum, From, To) ->
  FragTableName = frag_table_name (TableName, FragNum),
  CopyType = copy_type (FragTableName, From),

  true = ensure_table_copy (FragTableName, To, CopyType),
  true = ensure_remove_table_copy (FragTableName, From).

node_pool (TableName) ->
  { value, { node_pool, NodePool } } = 
    lists:keysearch (node_pool, 
                     1,
                     mnesia:table_info (TableName, frag_properties)),
  NodePool.

num_frags (TableName) ->
  FragProps = mnesia:table_info (TableName, frag_properties),
  { value, { n_fragments, NFrags } } = lists:keysearch (n_fragments,
                                                        1,
                                                        FragProps),
  NFrags.

num_frags_at (TableName, Node) ->
  lists:foldl (fun (N, Acc) ->
                FragTableName = frag_table_name (TableName, N),
                case lists:member (Node, used_nodes (FragTableName)) of
                  true -> Acc + 1;
                  false -> Acc
                end
               end,
               0,
               lists:seq (1, num_frags (TableName))).

rebalance (TableName) -> 
  rebalance (TableName, num_frags (TableName), false).

rebalance (TableName, NFrags, DidRebalance) ->
  Map = fragments_by_node (TableName, NFrags),

  { OverNode, OverFragments } = most_overloaded (Map),
  { UnderNode, UnderFragments } = least_overloaded (Map),

  CandidateFragments = gb_sets:difference (OverFragments, UnderFragments),

  case gb_trees:size (CandidateFragments) of
    N when N > 0 ->
      case gb_trees:size (OverFragments) > 1 + gb_trees:size (UnderFragments) of
        true ->
          move_fragment (TableName, 
                         gb_sets:smallest (CandidateFragments),
                         OverNode, 
                         UnderNode),

          rebalance (TableName, NFrags, true);
        false ->
          DidRebalance
      end;
    0 ->
      % Most and least overloaded node have same fragments assigned.
      % This means everybody has the same number of fragments, so
      % nothing to do.
      DidRebalance
  end.

rebalance_table_locked (TableName) ->
  ok = mnesia:wait_for_tables ([ TableName ], infinity),
  sanitize_node_pool (TableName),
  Enforce = enforce_targets (TableName),
  Rebalance = rebalance (TableName),
  lists:foldl (fun (T, Acc) -> 
                 Acc or synchronize_placement_locked (TableName, T) 
               end,
               Enforce or Rebalance,
               inverse_foreign_tables (TableName)).

remove_table_copies (_TableName, []) -> ok;
remove_table_copies (TableName, [ Node | Rest ]) ->
  ensure_remove_table_copy (TableName, Node),
  remove_table_copies (TableName, Rest).

sanitize_node_pool (TableName) ->
  NodePool = node_pool (TableName),
  DbNodes = mnesia:system_info (db_nodes),

  lists:foreach (fun (N) -> ensure_remove_node_from_table (TableName, N) end,
                 NodePool -- DbNodes).

try_ensure_remove_table_copies (_Table, []) ->
  true;
try_ensure_remove_table_copies (Table, NodeList) ->
  case erlang:function_exported (mnesia_schema, del_table_copies, 2) of
    true ->
      case mnesia_schema:del_table_copies (Table, NodeList) of
        { atomic, ok } -> true;
        _ -> false
      end;
    false ->
      false
  end.

try_sanitize_table_copy (FragTableName) ->
  UsedNodes = used_nodes (FragTableName),
  DbNodes = mnesia:system_info (db_nodes),

  try_ensure_remove_table_copies (FragTableName, UsedNodes -- DbNodes).

synchronize_placement_frag (ForeignTableFrag, 
                            TableFrag,
                            NRamCopies,
                            NDiscCopies,
                            NExternalCopies,
                            NDiscOnlyCopies) ->
  ForeignNodes = mnesia:table_info (ForeignTableFrag, ram_copies) ++
                 mnesia:table_info (ForeignTableFrag, disc_copies) ++
		 ?if_mnesia_ext (
		   mnesia:table_info (ForeignTableFrag, external_copies),
		   []) ++
                 mnesia:table_info (ForeignTableFrag, disc_only_copies),

  TableNodes = mnesia:table_info (TableFrag, ram_copies) ++
               mnesia:table_info (TableFrag, disc_copies) ++
               ?if_mnesia_ext (
		 mnesia:table_info (TableFrag, external_copies), 
		 []) ++
               mnesia:table_info (TableFrag, disc_only_copies),

  AddNodes = ForeignNodes -- TableNodes,
  DelNodes = TableNodes -- ForeignNodes,

  WillHaveRamCopies = 
    erlang:length (mnesia:table_info (TableFrag, ram_copies) -- DelNodes),
  WillHaveDiscCopies = 
    erlang:length (mnesia:table_info (TableFrag, disc_copies) -- DelNodes),
  ?if_mnesia_ext (
    WillHaveExternalCopies = 
      erlang:length 
        (mnesia:table_info (TableFrag, external_copies) -- DelNodes),
  ok),
  WillHaveDiscOnlyCopies = 
    erlang:length (mnesia:table_info (TableFrag, disc_only_copies) -- DelNodes),

  NeedRamCopies = NRamCopies - WillHaveRamCopies,
  NeedDiscCopies = NDiscCopies - WillHaveDiscCopies,
  NeedExternalCopies = ?if_mnesia_ext (NExternalCopies - WillHaveExternalCopies,
				       0),
  NeedDiscOnlyCopies = NDiscOnlyCopies - WillHaveDiscOnlyCopies,

  AddNodeChange = synchronize_add_nodes (TableFrag,
                                         AddNodes,
                                         NeedRamCopies,
                                         NeedDiscCopies,
                                         NeedExternalCopies,
                                         NeedDiscOnlyCopies,
                                         (DelNodes =/= [])),

  lists:foreach (fun (N) -> ensure_remove_table_copy (TableFrag, N) end,
                 DelNodes),

  HaveRamCopies = erlang:length (mnesia:table_info (TableFrag, ram_copies)),
  HaveDiscCopies = erlang:length (mnesia:table_info (TableFrag, disc_copies)),
  HaveExternalCopies = 
    ?if_mnesia_ext (erlang:length (mnesia:table_info (TableFrag, external_copies)),
		    0),
  HaveDiscOnlyCopies = 
    erlang:length (mnesia:table_info (TableFrag, disc_only_copies)),

  synchronize_change_nodes (TableFrag,
                            ForeignNodes,
                            HaveRamCopies,
                            NRamCopies,
                            HaveDiscCopies,
                            NDiscCopies,
                            HaveExternalCopies,
                            NExternalCopies,
                            HaveDiscOnlyCopies,
                            NDiscOnlyCopies,
                            AddNodeChange).

synchronize_add_nodes (_TableFrag, [], _Ram, _Disc, _External, _DiscOnly, Change) -> 
  Change;
synchronize_add_nodes (TableFrag, [ Node | Rest ], Ram, Disc, External, DiscOnly, Acc) ->
  if 
    Ram > 0 -> 
      Change = ensure_table_copy (TableFrag, Node, ram_copies),
      synchronize_add_nodes (TableFrag,
                             Rest,
                             Ram - 1,
                             Disc,
                             External,
                             DiscOnly,
                             Acc or Change);
    Disc > 0 ->
      Change = ensure_table_copy (TableFrag, Node, disc_copies),
      synchronize_add_nodes (TableFrag,
                             Rest,
                             Ram, 
                             Disc - 1,
                             External,
                             DiscOnly,
                             Acc or Change);
    ?if_mnesia_ext (External > 0, false) ->
      Change = ensure_table_copy (TableFrag, Node, external_copies),
      synchronize_add_nodes (TableFrag,
                             Rest,
                             Ram, 
                             Disc,
                             External - 1,
                             DiscOnly,
                             Acc or Change);
    true ->
      Change = ensure_table_copy (TableFrag, Node, disc_only_copies),
      synchronize_add_nodes (TableFrag,
                             Rest,
                             Ram,
                             Disc,
                             External,
                             DiscOnly - 1,
                             Acc or Change)
  end.

synchronize_change_nodes (_, [], _, _, _, _, _, _, _, _, Change) -> 
  Change;
synchronize_change_nodes (TableFrag, 
                          [ Node | Rest ],
                          HaveRamCopies,
                          NRamCopies,
                          HaveDiscCopies,
                          NDiscCopies,
                          HaveExternalCopies,
                          NExternalCopies,
                          HaveDiscOnlyCopies,
                          NDiscOnlyCopies,
                          Change) ->
  ThisType = copy_type (TableFrag, Node),

  if 
    (HaveRamCopies < NRamCopies) and (ThisType =/= ram_copies) ->
      { atomic, ok } = fast_change_table_copy_type (TableFrag,
                                                    Node,
                                                    ram_copies),
      synchronize_change_nodes (TableFrag, 
                                Rest,
                                HaveRamCopies + 1,
                                NRamCopies,
                                HaveDiscCopies,
                                NDiscCopies,
                                HaveExternalCopies,
                                NExternalCopies,
                                HaveDiscOnlyCopies,
                                NDiscOnlyCopies,
                                true);
    (HaveDiscCopies < NDiscCopies) and (ThisType =/= disc_copies) ->
      { atomic, ok } = fast_change_table_copy_type (TableFrag,
                                                    Node,
                                                    disc_copies),
      synchronize_change_nodes (TableFrag, 
                                Rest,
                                HaveRamCopies,
                                NRamCopies,
                                HaveDiscCopies + 1,
                                NDiscCopies,
                                HaveExternalCopies,
                                NExternalCopies,
                                HaveDiscOnlyCopies,
                                NDiscOnlyCopies,
                                true);
    ?if_mnesia_ext (
      (HaveExternalCopies < NExternalCopies) and (ThisType =/= external_copies),
      false) ->
      { atomic, ok } = fast_change_table_copy_type (TableFrag,
                                                    Node,
                                                    external_copies),
      synchronize_change_nodes (TableFrag, 
                                Rest,
                                HaveRamCopies,
                                NRamCopies,
                                HaveDiscCopies,
                                NDiscCopies,
                                HaveExternalCopies + 1,
                                NExternalCopies,
                                HaveDiscOnlyCopies,
                                NDiscOnlyCopies,
                                true);
    (HaveDiscOnlyCopies < NDiscOnlyCopies) and (ThisType =/= disc_only_copies) ->
      { atomic, ok } = fast_change_table_copy_type (TableFrag,
                                                    Node,
                                                    disc_only_copies),
      synchronize_change_nodes (TableFrag, 
                                Rest,
                                HaveRamCopies,
                                NRamCopies,
                                HaveDiscCopies,
                                NDiscCopies,
                                HaveExternalCopies,
                                NExternalCopies,
                                HaveDiscOnlyCopies + 1,
                                NDiscOnlyCopies,
                                true);
    true ->
      synchronize_change_nodes (TableFrag, 
                                Rest,
                                HaveRamCopies,
                                NRamCopies,
                                HaveDiscCopies,
                                NDiscCopies,
                                HaveExternalCopies,
                                NExternalCopies,
                                HaveDiscOnlyCopies,
                                NDiscOnlyCopies,
                                Change)
  end.

synchronize_placement (ForeignTable, TableName) ->
  LockId = { { ?MODULE, TableName }, self () },

  global:set_lock (LockId),

  try 
    try
      synchronize_placement_locked (ForeignTable, TableName)
    catch
      X : Y ->
        { aborted, { X, Y } }
    end
  after
    global:del_lock (LockId)
  end.

synchronize_placement (ForeignTable,
                       TableName,
                       NRamCopies,
                       NDiscCopies,
                       NExternalCopies,
                       NDiscOnlyCopies) ->
  LockId = { { ?MODULE, TableName }, self () },

  global:set_lock (LockId),

  try 
    try
      synchronize_placement_locked (ForeignTable,
                                    TableName,
                                    NRamCopies,
                                    NDiscCopies,
                                    NExternalCopies,
                                    NDiscOnlyCopies)
    catch
      X : Y ->
        { aborted, { X, Y } }
    end
  after
    global:del_lock (LockId)
  end.

synchronize_placement_locked (ForeignTable, Table) ->
  { NRamCopies, NDiscCopies, NExternalCopies, NDiscOnlyCopies } = 
    mnesia:async_dirty (fun () -> copies (Table) end),

  synchronize_placement_locked (ForeignTable,
                                Table,
                                NRamCopies,
                                NDiscCopies,
                                NExternalCopies,
                                NDiscOnlyCopies).

synchronize_placement_locked (ForeignTable,
                              Table,
                              NRamCopies,
                              NDiscCopies,
                              NExternalCopies,
                              NDiscOnlyCopies) ->
  synchronize_placement_locked (ForeignTable,
                                Table,
                                NRamCopies,
                                NDiscCopies,
                                NExternalCopies,
                                NDiscOnlyCopies,
                                1,
                                num_frags (ForeignTable),
                                false).

synchronize_placement_locked (_ForeignTable, 
			      _TableName, 
			      _NRamCopies, 
			      _NDiscCopies, 
			      _NExternalCopies,
			      _NDiscOnlyCopies,
			      K, 
			      N, 
			      Change) when K > N -> 
  Change;
synchronize_placement_locked (ForeignTable, 
                              TableName, 
                              NRamCopies,
                              NDiscCopies,
                              NExternalCopies,
                              NDiscOnlyCopies,
                              Frag,
                              NumFrags,
                              Change) ->
  ForeignTableFrag = frag_table_name (ForeignTable, Frag),
  TableFrag = frag_table_name (TableName, Frag),
  FragChange = synchronize_placement_frag (ForeignTableFrag, 
                                           TableFrag,
                                           NRamCopies,
                                           NDiscCopies,
                                           NExternalCopies,
                                           NDiscOnlyCopies),
  synchronize_placement_locked (ForeignTable, 
                                TableName, 
                                NRamCopies,
                                NDiscCopies,
                                NExternalCopies,
                                NDiscOnlyCopies,
                                Frag + 1, 
                                NumFrags,
                                Change or FragChange).

unused_nodes (TableName, FragNum) ->
  FragTableName = frag_table_name (TableName, FragNum),
  NodePool = node_pool (TableName),
  UsedNodes = used_nodes (FragTableName),

  NodePool -- UsedNodes.

unused_running_nodes (TableName, FragNum) ->
  UnusedNodes = unused_nodes (TableName, FragNum),
  RunningNodes = mnesia:system_info (running_db_nodes),

  intersect (UnusedNodes, RunningNodes).

used_nodes (TableName) ->
  lists:usort (used_nodes (TableName, ram_copies) ++
               used_nodes (TableName, disc_copies) ++
               ?if_mnesia_ext (used_nodes (TableName, external_copies),
			       []) ++
               used_nodes (TableName, disc_only_copies)).

used_nodes (TableName, CopyType) ->
  mnesia:table_info (TableName, CopyType).

used_running_nodes (TableName, CopyType) ->
  UsedNodes = used_nodes (TableName, CopyType),
  RunningNodes = mnesia:system_info (running_db_nodes),

  intersect (UsedNodes, RunningNodes).

validate_initial_copies (TabDef) ->
  case lists:keysearch (frag_properties, 1, TabDef) of
    false ->
      true;
    { value, { frag_properties, FragProps } } ->
      case lists:keysearch (foreign_key, 1, FragProps) of
        false ->
          true;
        { value, { foreign_key, undefined } } ->
          true;
        { value, { foreign_key, { ForeignTable, _ } } } ->
          { ForeignRamCopies, ForeignDiscCopies, ForeignExternalCopies, ForeignDiscOnlyCopies } = 
              mnesia:async_dirty (fun () -> copies (ForeignTable) end),
          { ThisRamCopies, ThisDiscCopies, ThisExternalCopies, ThisDiscOnlyCopies } =
              copies_from_fragprops (FragProps,
                                     { ForeignRamCopies,
                                       ForeignDiscCopies,
                                       ForeignExternalCopies,
                                       ForeignDiscOnlyCopies }),
          (ForeignRamCopies + ForeignDiscCopies + ForeignExternalCopies + ForeignDiscOnlyCopies) =:=
          (ThisRamCopies + ThisDiscCopies + ThisExternalCopies + ThisDiscOnlyCopies)
      end
  end.

validate_targets (Table, Targets) ->
  case mnesia:table_info (Table, frag_properties) of
    [] ->
      true;
    FragProps ->
      case lists:keysearch (foreign_key, 1, FragProps) of
        false ->
          true;
        { value, { foreign_key, undefined } } ->
          true;
        { value, { foreign_key, { ForeignTable, _ } } } ->
          { ForeignRamCopies, ForeignDiscCopies, ForeignExternalCopies, ForeignDiscOnlyCopies } = 
              mnesia:async_dirty (fun () -> copies (ForeignTable) end),
          { ThisRamCopies, ThisDiscCopies, ThisExternalCopies, ThisDiscOnlyCopies } =
              mnesia:async_dirty (fun () -> copies (Table) end),
          { TargetRamCopies, TargetDiscCopies, TargetExternalCopies, TargetDiscOnlyCopies } =
              copies_from_fragprops (Targets,
                                     { ThisRamCopies,
                                       ThisDiscCopies,
                                       ThisExternalCopies,
                                       ThisDiscOnlyCopies }),

          (ForeignRamCopies + ForeignDiscCopies + ForeignExternalCopies + ForeignDiscOnlyCopies) =:=
          (TargetRamCopies + TargetDiscCopies + TargetExternalCopies + TargetDiscOnlyCopies)
      end
  end.
