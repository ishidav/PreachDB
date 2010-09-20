%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [preach.erl]
%
%  PackageName                [preach]
%
%  Synopsis                   [Main erl module for Parallel Model Checking]
%
%  Author                     [BRAD BINGHAM, FLAVIO M DE PAULA, VALERIE ISHIDA]
%
%  Copyright                  [Copyright (C) 2009 University of British Columbia]
% 
%  This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
%--------------------------------------------------------------------------------
-include("$PREACH_PATH/DEV/SRC/preach.hrl").
-include("$PREACH_PATH/DEV/SRC/visited_state.hrl").
%
% No module/exports defn since they should be included in the bottom of the 
% gospel code
%

%% configuration-type functions
timeoutTime() -> 60000.

%% these are load balancing parameters. Still in experimental stage,
%% will eventually be moved to preach.hrl or integrated into ptest.
isLoadBalancing() -> false.

balanceFrequency() -> 10000. %10000 div 8.

% Might want to set this to be the number of threads (length(Names)?)
balanceRatio() -> 8.

balanceTolerence() -> 10000 div 8.

%%----------------------------------------------------------------------
%% Function: createHashTable/1
%% Purpose : Routines to abstract away how the hash table is implemented, eg,
%%           erlang lists, ets or dict, bloom filter
%%               
%% Args    : 
%%
%% Returns : a variable which type depends on the implementation, eg, 
%%           bloom filter will return a record type; 
%%           mnesia table will return TableName
%%     
%%----------------------------------------------------------------------
createHashTable(IsUsingMnesia) ->
  if IsUsingMnesia ->
    visited_state;
   true -> bloom:bloom(?BLOOM_N_ENTRIES,?BLOOM_ERR_PROB)
  end.

%%----------------------------------------------------------------------
%% Function: isMemberHashTable/2
%% Purpose : Checks for membership in the hash table
%%               
%% Args    : Element is the state that we want to check
%%           HashTable is the name of the hash table returned by
%%           createHashTable
%%
%% Returns : returns true or false
%%     
%%----------------------------------------------------------------------
isMemberHashTable(Element, HashTable) ->
  IsUsingMnesia = isUsingMnesia(),
  if IsUsingMnesia ->
      %case mnesia:transaction(fun() -> mnesia:read(HashTable, Element) end) of 
      %  {atomic, [_X | _]} -> true;
      %  {atomic, []} -> false;
      case mnesia:activity(sync_dirty, fun mnesia:read/1, [{HashTable, Element}], mnesia_frag) of
        [_X | _] -> true;
        [] -> false;
        _Else -> false
      end;
    true -> bloom:member(Element,HashTable)
  end.

%%----------------------------------------------------------------------
%% Function: addElemToHashTable/4
%% Purpose : Add a state to the hash table
%%               
%% Args    :  Element is the state that we want to add
%%           OutstandingAcks is the number of ACKs left
%%           HashTable is the name of the hash table returned by
%%           createHashTable
%%
%% Returns : a variable which type depends on the implementation, eg, 
%%           bloom filter will return a record type; 
%%     
%%----------------------------------------------------------------------
addElemToHashTable(Element, OutstandingAcks, SeqNo, HashTable)->
  IsUsingMnesia = isUsingMnesia(),
  if IsUsingMnesia ->
    % massage Element into correct record type (table name is first element)
    Record = #visited_state{state = Element, outstandingacks = OutstandingAcks, seqno = SeqNo},
    %case mnesia:transaction(fun() -> mnesia:write(HashTable, Record, write) end) of
        %{atomic, _} -> ok;
    case mnesia:activity(transaction, fun mnesia:write/2, [HashTable, Record], mnesia_frag) of
        ok -> ok;
        Else -> %io:format("~w@~w addElemToHashTable(~w, ~w, ~w, ~w) returned ~w~n", [getSname(), node(), Element, OutstandingAcks, SeqNo, HashTable, Else]),
                Else
    end;
   true -> bloom:add(Element,HashTable)
  end.

%%----------------------------------------------------------------------
%% Function: readHashTable/2
%% Purpose : Reads the state value (ACKs and SeqNo) in the hash table
%%               
%% Args    : Element is the state that we want to read
%%           HashTable is the name of the hash table returned by
%%           createHashTable
%%
%% Returns : integer number of ACKs or ok
%%     
%%----------------------------------------------------------------------
readHashTable(Element, HashTable) ->
  IsUsingMnesia = isUsingMnesia(),
  if IsUsingMnesia ->
    %case mnesia:transaction(fun() -> mnesia:read(HashTable, Element) end) of 
	%{atomic, [X | _]} ->
	%     {_, _, Acks, SeqNo} = X,
	%     {Acks, SeqNo};
	%{atomic, []} ->
	%    ok;
    case mnesia:activity(sync_dirty, fun mnesia:read/1, [{HashTable, Element}], mnesia_frag) of
        [X | _] -> {_, _, Acks, SeqNo} = X,
            {Acks, SeqNo};
        [] -> ok;
        _Else ->
            %io:format("~w@~w readHashTable(~w, ~w) returned ~w~n", [getSname(), node(), Element, HashTable, Else]),
            ok
    end;
   true -> 
    ok
  end.

%%----------------------------------------------------------------------
%% Function: addElemToHashTableAndStateQueue/4
%% Purpose : Add the element to the Mnesia persisted hash table and 
%%              state queue.  Use this when we first receive the state
%%              and before we expand it.  Writes to both atomically.
%% Args    : boolean, State, atom table name, atom table name
%% Returns : ok or error
%%     
%%----------------------------------------------------------------------
addElemToHashTableAndStateQueue(IsUsingMnesia, Element, HashTable, StateQueue) ->
    if IsUsingMnesia ->
        % massage Element into correct record type (table name is first element)
        HTRecord = #visited_state{state = Element, outstandingacks = false, seqno = 0},
        SQRecord = #state_queue{state = Element, order = 0},
        mnesia:activity(transaction, fun() -> 
            mnesia:write(HashTable, HTRecord, write), 
            mnesia:write(StateQueue, SQRecord, write) end, mnesia_frag);
       true -> bloom:add(Element,HashTable)
    end.

%%----------------------------------------------------------------------
%% Function: updateElemInHashTable/4
%% Purpose : Add a state to the hash table
%%               
%% Args    :  Element is the state that we want to add
%%           OutstandingAcks is the number of ACKs left
%%           HashTable is the name of the hash table returned by
%%           createHashTable
%%
%% Returns : a variable which type depends on the implementation, eg, 
%%           bloom filter will return a record type; mnesia table 
%%           returns {bool: true if this state has not been explored, 
%%           the new ACK sequence number}
%%     
%%----------------------------------------------------------------------
updateElemInHashTable(IsUsingMnesia, Element, OutstandingAcks, HashTable) ->
  if IsUsingMnesia ->
    mnesia:activity(transaction, fun() -> 
        case mnesia:read(HashTable, Element, write) of
          [] -> Record = #visited_state{state = Element, 
                         outstandingacks = OutstandingAcks, seqno = 1},
                mnesia:write(HashTable, Record, write),
                {true, 1};
          [X] -> {_, _, OA, S} = X,
                if is_number(OA) andalso OA == 0 ->
                    {false, S};
                  true ->
                    Record = #visited_state{state = Element, 
                         outstandingacks = OutstandingAcks, seqno = S+1},
                    mnesia:write(HashTable, Record, write),
                    {true, S+1}
                end
        end
    end, mnesia_frag);
    true -> bloom:add(Element,HashTable)
  end.

%%----------------------------------------------------------------------
%% Function: decrementHashTableAcksOnZeroDelElemFromStateQueue/5
%% Purpose : Decrements the ACKs outstanding for this element.  If ACKs
%%              outstanding is 0 after doing this, delete the element
%%              from the State Queue.
%% Args    : boolean, State, atom table name, atom table name
%% Returns : ok or error
%%     
%%----------------------------------------------------------------------
decrementHashTableAcksOnZeroDelElemFromStateQueue(IsUsingMnesia, Element, 
                                         SeqNo, HashTable, StateQueue) ->
    if IsUsingMnesia ->
        if Element /= null -> % TODO track ACKs for start states
            mnesia:activity(transaction, fun() -> 
                [{_, _, OutstandingAcks, CurSeqNo} | _] = mnesia:read(HashTable, Element),
                if (SeqNo == CurSeqNo) and is_number(OutstandingAcks) andalso OutstandingAcks > 0 ->
                    HTRecord = #visited_state{state = Element, outstandingacks = OutstandingAcks-1, seqno = CurSeqNo},
                    mnesia:write(HashTable, HTRecord, write),
                    if OutstandingAcks-1 == 0 -> mnesia:delete(StateQueue, Element, write);
                      true -> ok
                    end;
                  SeqNo /= CurSeqNo -> ok;
                  not is_number(OutstandingAcks) -> 
                    io:format("~w received ACK for state ~w when HT ACKs outstanding was not a number~n", [node(), Element]), 
                    ok;
                  true -> 
                    io:format("~w received ACK for state ~w when ACKs outstanding ~w <= 0, CurSeqNo = ~w SeqNo = ~w~n", [node(), Element, OutstandingAcks, CurSeqNo, SeqNo]), 
                    ok
                end  % if (SeqNo == CurSeqNo) and ...
            end, mnesia_frag);
          true -> ok
        end;
      true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: createMnesiaTables/0
%% Purpose : Create Mnesia tables, assumes schema is already created
%%          and set to disc
%% Args    : 
%% Returns : ok or {error, Reason}
%%     
%%----------------------------------------------------------------------
createMnesiaTables(Names) ->
    %ce_db:create([  {visited_state, [{disc_copies, [node()]}, 
    %{local_content, true}, {attributes, record_info(fields, visited_state)}]},
    %                {state_queue, [{disc_copies, [node()]}, 
    %{local_content, true}, {attributes, record_info(fields, state_queue)}]}]),
    %timer:sleep(1000),
    mnesia:start(),
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    Others = [OtherNodes || OtherNodes <- dictToList(Names),  OtherNodes =/= {list_to_atom(getSname()),node()}],
    barrier(Others, lists:zip(Others, lists:duplicate(length(Others), 0))),
    NodePool = [X || {_, X} <- dictToList(Names)],
    % TODO command-line override for NDiscCopies
    if size(Names) =< 1 -> NDiscCopies = 1;
       %size(Names) == 2 -> NDiscCopies = 2;
       true -> NDiscCopies = 2
    end,
    fragmentron:create_table(visited_state, [{attributes, record_info(fields, visited_state)}, {frag_properties, [{n_fragments, length(NodePool)}, {node_pool, NodePool}, {n_disc_copies, NDiscCopies}]}]),
    fragmentron:create_table(state_queue, [{attributes, record_info(fields, state_queue)}, {frag_properties, [{n_fragments, length(NodePool)}, {node_pool, NodePool}, {n_disc_copies, NDiscCopies}]}]),
    lists:foreach(fun(X) -> X ! {ready, {list_to_atom(getSname()),node()}} end, Others),
    ok.

%%----------------------------------------------------------------------
%% Function: attachToMnesiaTables/1
%% Purpose : Have slaves attach to root's Mnesia schema and tables
%% Args    : node
%% Returns : ok
%%     
%%----------------------------------------------------------------------
attachToMnesiaTables(Names) ->
    {_, RootNode} = rootPID(Names),
    %timer:sleep(2000),
    %ce_db:connect(RootNode, [], [visited_state, state_queue]).
    mnesia:start(),
    timer:sleep(500),
    spawn(RootNode, ce_db, probe_db_nodes, [{list_to_atom(getSname()),node()}]),
    receive
      {probe_db_nodes_reply, DBNodes} ->
        mnesia:change_config(extra_db_nodes, DBNodes),
        mnesia:change_table_copy_type(schema, node(), disc_copies),
        rootPID(Names) ! {ready, {list_to_atom(getSname()),node()}},
        ok
    end,
    receive 
      {ready, {pruser0, _}} -> ok
    end.

%%----------------------------------------------------------------------
%% Function: addMnesiaTables/2
%% Purpose : Will create table if root or try to connect to root's table
%% Args    : boolean, node
%% Returns : ok
%%     
%%----------------------------------------------------------------------
addMnesiaTables(IsUsingMnesia, Names) ->
    IAmRoot = amIRoot(),
    MnesiaSchemaExists = mnesia:system_info(use_dir),
    case IsUsingMnesia of 
        true ->
            case MnesiaSchemaExists of
                false ->
                    case IAmRoot of
                        true -> createMnesiaTables(Names);
                        false -> attachToMnesiaTables(Names);
                        _Else -> ok
                    end;
                true -> mnesia:start(), 
                  mnesia:activity(transaction, fun mnesia:wait_for_tables/2, [[visited_state, state_queue], 10000], mnesia_frag),
                  ok;
                _Else -> ok
            end;
        _Else -> ok
    end.

%%----------------------------------------------------------------------
%% Function: addElemToStateQueue/4
%% Purpose : add the element to the Mnesia persisted state queue
%% Args    : boolean, State, atom table name, int
%% Returns : ok
%%     
%%----------------------------------------------------------------------
addElemToStateQueue(IsUsingMnesia, Element, StateQueue, Order) ->
    if IsUsingMnesia ->
        % massage Element into correct record type (table name is first element)
        Record = #state_queue{state = Element, order = Order},
        mnesia:activity(transaction, fun mnesia:write/2, [StateQueue, Record], mnesia_frag);
      true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: delElemFromStateQueue/3
%% Purpose : remove the element to the Mnesia persisted state queue
%% Args    : boolean, State, atom table name
%% Returns : ok
%%     
%%----------------------------------------------------------------------
delElemFromStateQueue(IsUsingMnesia, Element, StateQueue) ->
    if IsUsingMnesia ->
        mnesia:activity(transaction, fun mnesia:delete/2, [StateQueue, Element, write], mnesia_frag);
      true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: firstOfStateQueue/2
%% Purpose : check if anything in the state queue, if so, return it
%% Args    : boolean, atom table name
%% Returns : State LIST or []
%%     
%%----------------------------------------------------------------------
firstOfStateQueue(IsUsingMnesia, StateQueue) ->
    if IsUsingMnesia ->
        % TODO: try getting first 1000 instead
        SQKeys = mnesia:activity(sync_dirty, fun mnesia:all_keys/1, [StateQueue], mnesia_frag),
        if length(SQKeys) == 0 -> [];
          true -> lists:sublist(SQKeys, random:uniform(length(SQKeys)), random:uniform(length(SQKeys)))
        end;

        %case mnesia:activity(transaction, fun() -> mnesia:dirty_slot(StateQueue, random:uniform(100)) end, mnesia_frag) of
        %  [X | Y] -> [X | Y]; % we get lucky and hit a full bucket
        %  _ ->
        %    case mnesia:activity(sync_dirty, fun() -> mnesia:dirty_first(StateQueue) end, mnesia_frag) of
        %      '$end_of_table' -> []; % empty state queue
        %      State -> [State]
        %    end
        %end;
       true -> []
    end.

%%----------------------------------------------------------------------
%% Function: stopMnesia/1
%% Purpose : Stops the Mnesia DBMS
%% Args    : boolean
%% Returns : ok
%%     
%%----------------------------------------------------------------------
stopMnesia(IsUsingMnesia) ->
    case IsUsingMnesia of 
	true ->
	    mnesia:stop(),
	    ok;
	false->
	    ok
    end.  

%%----------------------------------------------------------------------
%% Function: createStateCache/1, deleteStateCache/1
%% Purpose : Routines to abstract away how the cache is implemented, eg,
%%           erlang lists, ets or dict, etc...
%%           Note that w/ ets the table is referenced by its name,
%%          which type is an atom
%%               
%% Args    : boolean resulting from calling isCaching() 
%%
%% Returns : 
%%     
%%----------------------------------------------------------------------
createStateCache(Create) ->
    if Create ->
	    ets:new(cache,[set,private,named_table]),
	    ets:insert(cache,[{?CACHE_HIT_INDEX, 0}]);
       true ->
	    ok
    end.

deleteStateCache(Delete) ->
    if Delete ->
	    ets:delete(cache);
       true ->
	    ok
    end.

%%----------------------------------------------------------------------
%% Function: stateCacheLookup/1
%% Purpose : Routines to abstract away how the cache is implemented, eg,
%%           erlang lists, ets or dict, etc...
%%               
%% Args    : cache location 
%%
%%
%% Returns : A list containing a tuple w/ the element matching the cache 
%%          location in the following format {Index, State}
%%          
%%----------------------------------------------------------------------
stateCacheLookup(CacheIndex) ->
    ets:lookup(cache, CacheIndex).

%%----------------------------------------------------------------------
%% Function: stateCacheInsert/2
%% Purpose : Routines to abstract away how the cache is implemented, eg,
%%           erlang lists, ets or dict, etc...
%%               
%% Args    : cache location and element to be cached
%%
%%
%% Returns : true
%%          
%%----------------------------------------------------------------------
stateCacheInsert(CacheIndex, State) ->
    ets:insert(cache,[{CacheIndex, State}]).

%%----------------------------------------------------------------------
%% Function: getHitCount/0
%% Purpose : Used only when caching send states. 
%% Args    : 
%%	     
%% Returns :
%%     
%%----------------------------------------------------------------------
getHitCount() -> 
    element(2,hd(stateCacheLookup(?CACHE_HIT_INDEX))).

%%----------------------------------------------------------------------
%% Function: mynode/3
%% Purpose : Enumerate list of hosts where erlang workers are waiting for 
%%           jobs 	
%% Args    : Index is the number of workers to be used. Important Index zero
%%          must be the master from which you're spawning the jobs   
%%           HostList is the list of hosts
%%           Nhosts is the number of hosts
%%
%% Requires: a symlink to $PREACH/VER/TB,ie, ln -s $PREACH/VER/TB hosts	
%%           from the directory you're running erl
%% 
%% Returns : list of hosts
%%     
%%----------------------------------------------------------------------
mynode(Index, HostList, Nhosts) -> 
    list_to_atom(lists:append( 
		   lists:append(
		     lists:append("pruser", integer_to_list(Index)), "@"),
		   atom_to_list(lists:nth(1+((Index-1) rem Nhosts), HostList)))).
%%----------------------------------------------------------------------
%% Function: hosts/0 
%% Purpose : 
%% 	
%% Args    : 
%%
%% Returns : HostList is the list of hosts
%%           Nhosts is the number of hosts
%%     
%%----------------------------------------------------------------------
hosts() ->
    Localmode = init:get_argument(localmode),
    if (Localmode == error) ->
	    case file:open("hosts",[read]) of
		{ok, InFile} ->
		    read_inFile(InFile,[], 1);
		{error, Reason} ->
		    io:format("Could not open 'hosts'. Erlang reason: '~w'. ",[Reason]),
		    io:format("Read www/erlang.doc/man/io.html for more info...exiting~n",[]),
		    exit; % ERROR_HANDLING?
		_Other -> io:format("Error in parsing return value of file:open...exiting~n",[]),
			  exit  % ERROR_HANDLING?
	    end;
       true ->
	    {[os:getenv("PREACH_MACHINE")], 1}
    end.

%%----------------------------------------------------------------------
%% Function: read_inFile/3 
%% Purpose : Reads the erlang tokenized file 'hosts'. The syntax follows: 
%%           one machine-name per line followed by a dot 
%%
%% Args    : inFile   is the file handler for 'hosts'; 
%%           HostList -> emtpy list;
%%           SLine    -> start line (trick used to get number of hosts)
%%
%% Returns : a tuple w the list of hosts and the number of elems in the list
%%     
%%----------------------------------------------------------------------
read_inFile(InFile,HostList,SLine) ->
    case io:read(InFile, "", SLine) of
        {ok, Host, _ELine} ->
            read_inFile(InFile, lists:append(HostList, [Host]), SLine + 1);
	
        {eof, ELine} ->
	    {HostList, ELine-1};
	
        {error, ErrInfo, Err} ->
            io:format("Error in reading file ~w with status",[InFile]),
            io:format(" ~w; ~w ...exiting~n",[ErrInfo, Err]);
        Other -> Other
    end.

%%----------------------------------------------------------------------
%% Function: compressState/1, decompressState/1, hashState2Int/1 
%% Purpose : Translates state into some basic data-type 
%%            	
%% Args    : State 
%%         
%% Returns : Translated state 
%%     
%%----------------------------------------------------------------------
compressState(State) ->
%	stateToInt(State).
    stateToBits(State).
	%State.

decompressState(CompressedState) ->
%		intToState(CompressedState).
    bitsToState(CompressedState).
	%	CompressedState.

hashState2Int(State) ->
    erlang:phash2(State,round(math:pow(2,32))).

%%----------------------------------------------------------------------
%% Function: rootPID/1
%% Purpose : Find the pid associated w/ the root machine
%%           
%%            	
%% Args    : Ordered dictionary of pids, where element 1 maps to the root
%%          machine
%%         
%% Returns : pid
%%     
%%----------------------------------------------------------------------
rootPID(Names) -> dict:fetch(1,Names).

%%----------------------------------------------------------------------
%% Function: start/0
%% Purpose : A timing wrapper for the parallel version of 
%%				our model checker.
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
start() ->
    %% print who I am
    io:format("Hello from ~s, my mnesia dir is ~s~n", [getSname(), getMnesiaDir()]),
    register(list_to_atom(getSname()), self()),
    IAmRoot = amIRoot(),
    if IAmRoot -> io:format("I am root~n"); true -> ok end,
    io:format("My cwd is ~s~n", [element(2, file:get_cwd())]),
    {HostList,Nhosts} = hosts(),
    {NamesList, P} = lists:mapfoldl(fun(X, I) -> {{list_to_atom("pruser" ++ integer_to_list(I)), list_to_atom("pruser" ++ integer_to_list(I) ++ "@" ++ atom_to_list(X))}, I+1} end, 0, HostList),
    lists:foreach(fun(X) -> io:format("~w~n", [X]) end, NamesList),
    Names = dict:from_list(lists:zip(lists:seq(1, length(NamesList)), NamesList)),
    %% when sending messages, use {PID, pruserX@node} ! Message
    %% might want to register(pruserX, self()) so don't need to know PIDs
    %% Names should just be where nodes can send each other messages
    % TODO update Names when hot spare join

    IsUsingMnesia = isUsingMnesia(),
    HashTable = createHashTable(IsUsingMnesia),
    addMnesiaTables(IsUsingMnesia, Names),
    timer:sleep(4000),
    %mnesia:info(),

    {A1,A2,A3} = now(),
    random:seed(A1, A2, A3),

    if IAmRoot ->
           %% barrier here until all nodes up: wait for message from all others
           Others = [OtherNodes || OtherNodes <- dictToList(Names),  OtherNodes =/= {list_to_atom(getSname()),node()}],
           barrier(Others, lists:zip(Others, lists:duplicate(length(Others), 0))),
           T0 = now(),
           sendStates(startstates(), null, 1, Names),
           NumSent = length(startstates()),

           reach([], null, Names,HashTable,{NumSent,0},[], 0,0), %should remove null param

           io:format("~w PID ~w: waiting for workers to report termination...~n", [node(), self()]),
           {NumStates, NumHits} = waitForTerm(dictToList(Names), 0, 0, 0),
           Dur = timer:now_diff(now(), T0)*1.0e-6,
           NumPurged = purgeRecQ(0),
           if IsUsingMnesia -> NumUniqStates = mnesia:activity(transaction, fun()->mnesia:table_info(visited_state, size) end, mnesia_frag);
             true -> NumUniqStates = NumStates
           end,
           deleteStateCache(isCaching()),

           io:format("----------~n"),
           io:format("REPORT:~n"),
           io:format("\tTotal of ~w unique states visited over all runs~n", [NumUniqStates]),
           io:format("\tTotal of ~w non-unique states visited this run~n", [NumStates]),
           io:format("\t~w messages purged from the receive queue~n", [NumPurged]),
           io:format("\tExecution time [current run]: ~f seconds~n", [Dur]),
           io:format("\tNon-unique states visited per second [current run]: ~w~n", [trunc(NumStates/Dur)]),
           io:format("\tNon-unique states visited per second per thread [current run]: ~w~n", [trunc((NumStates/Dur)/P)]),
           IsCaching = isCaching(),
           if IsCaching ->
               io:format("\tTotal of ~w state-cache hits (average of ~w)~n", 
		      [NumHits, trunc(NumHits/P)]);
              true -> ok
           end,
           IsLB = isLoadBalancing(),
           if IsLB ->
               io:format("\tLoad balancing enabled~n");
           true ->
               io:format("\tLoad balancing disabled~n")
           end;
       true -> rootPID(Names) ! {ready, {list_to_atom(getSname()),node()}},
           reach([], null, Names, HashTable, {0,0},[],0,0),
           io:format("~w PID ~w: Worker ~w is done~n", [node(), self(), node()])
    end,
    stopMnesia(IsUsingMnesia),
    io:format("----------~n"),
    done.

%%----------------------------------------------------------------------
%% Function: autoStart/0
%% Purpose : A wrapper for the parallel version of our model checker.
%%           To be used when called from the ptest script
%%           The main purpose is to separate basic initialization (non-algorithmic)
%%          from the rest of the compuation
%% Args    : 
%%	
%% Returns :
%%     
%%----------------------------------------------------------------------
autoStart() ->
    displayHeader(),
    displayOptions(),
    process_flag(trap_exit,true),
    {module, _} = code:load_file(ce_db),
    {module, _} = code:load_file(fragmentron),
    {module, _} = code:load_file(etable),
    start().

%%----------------------------------------------------------------------
%% Function: lateStart/0
%% Purpose : Allow us to add a hot-spare node after an existing node
%%           has died.
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
lateStart() ->
    % TODO connect to existing tables
    % TODO add table copy of any frag w/ missing replicas
    % TODO rebalance frags?
    % TODO check message Q
    % TODO reach()
    ok.

%%----------------------------------------------------------------------
%% Function: waitForTerm/4
%% Purpose : Accumulate number of states visited and cache hits 
%%           Calls exitHandler when receiving 'EXIT' 
%%
%% Args    : PIDs list of workers
%%           TotalStates is the number of unique visited state per node
%%	     TotalHits is the number of cache hits per node
%%           Cover is a simple marker to identify that we are done when
%%           all workers have reported their numbers
%%
%% Assumption: Each node only reports its numbers once (impact on Cover)
%%
%% Returns : a tuple w/ total visited states and and total hits
%%     
%%----------------------------------------------------------------------
waitForTerm(PIDs, TotalStates, TotalHits, Cover) ->
    if Cover < length(PIDs) ->
	    receive
		{DiffPID, {NumStates, NumHits}, done} -> 
		    io:format("~w PID ~w: worker thread ~w has reported " ++
			      "termination~n", [node(), self(), DiffPID]),%;
		    waitForTerm(PIDs,TotalStates + NumStates, 
				TotalHits + NumHits, Cover +1);
		{'EXIT', Pid, Reason } ->
		    exitHandler(Pid,Reason),
		    NumStates = 0, NumHits = 0,
		    waitForTerm(PIDs,TotalStates + NumStates, 
				TotalHits + NumHits, Cover)
	    end;
       true ->
	    {TotalStates, TotalHits}
    end.




%%----------------------------------------------------------------------
%% Function: purgeRecQ/1
%% Purpose : 
%% Args    : 
%%	     
%% Returns :
%%     
%%----------------------------------------------------------------------
purgeRecQ(Count) ->
    receive
	{'EXIT', Pid, Reason } ->
	    exitHandler(Pid,Reason),
	    purgeRecQ(Count);
	_Garbage ->
	    io:format("Garbage =~w~n",[_Garbage]),
	    purgeRecQ(Count+1)
    after
	100 ->
	    Count
    end.

%%----------------------------------------------------------------------
%% Function: exitHandler/2
%% Purpose : Handling dying distributed nodes. Assuming the requirements
%%           (below) are fulfilled, a dying node sends a message to the
%%           root w/ it's dying reason.
%%           If the reason is normal it means we are finishing the computation
%%	     otherwise, either the network got interrupted or the node really
%%           died. Therefore, check if the node is truly dead before killing the
%%           whole computation
%% 	
%% Args    : First is the state we're currently sending
%%		Rest are the rest of the states to send
%%		Names is a list of PIDs
%%
%% REQUIRES: process_flag(exit,trap) to be called;
%%           nodes to be linked 
%% Returns : ok
%%     
%%----------------------------------------------------------------------
exitHandler(Pid, Reason) ->
    io:format("~w ~w Received Exit @T=~w from ~w w/ Reason ~w~n",[node(), self(), now(), Pid, Reason]),
    stopMnesia(isUsingMnesia()),
    if Reason =/= normal ->
        halt();
      true -> ok
    end.

exitHandler(Pid, Reason, NumVS, MemQSize) ->
    io:format("~w ~w Received Exit @T=~w from ~w w/ Reason ~w~n",[node(), self(), now(), Pid, Reason]),
    io:format("~w ~w Non-unique states visited this run: ~w, in-memory queue size: ~w~n",[node(), self(), NumVS, MemQSize]),
    stopMnesia(isUsingMnesia()),
    if Reason =/= normal ->
	    %case net_kernel:connect(node(Pid)) of 
		%true -> ok;
		%_Other  -> 
		%    io:format("~n Exiting immediately...~n",[]),
		%    halt()
	    %end;
            halt();
       true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: sendStates/4
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%		
%% Args    : First is the state we're currently sending
%%		Rest are the rest of the states to send
%%		Parent is the parent of this set of states, and is used
%%		in ACKs back to this node
%%		SeqNo is the ACK sequence number for this sending of states
%%		Names is a list of PIDs
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendStates(States, Parent, SeqNo, Names) -> 
    %io:format("~w PID ~w: sendStates ~w ~w ~w~n", [node(), self(), States, Parent, SeqNo]),
    Me = {list_to_atom(getSname()), node()},
    StateCaching = isCaching(),
    if StateCaching  ->
	    sendStates(caching,States, Parent, SeqNo, Me, Names, 0);
       true ->
	    sendStates(nocaching, States, Parent, SeqNo, Me, Names, 0)
    end.
   

%%----------------------------------------------------------------------
%% Function: sendStates/7 (State Caching)
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%           DOCUMENT: Explain how state caching works		
%%
%% Args    : First is the state we're currently sending
%%	     Rest are the rest of the states to send
%%	     Names is a list of PIDs
%%           NumSent is the number of states sent    
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendStates(caching, [], _Parent, _SeqNo, _Me, _Names, NumSent) ->
    NumSent;

sendStates(caching, [First | Rest], Parent, SeqNo, Me, Names, NumSent) ->
    % TODO set Owner as function of which node has local copy of frag
    Owner = dict:fetch(1+erlang:phash2(First,dict:size(Names)), Names),
    CacheIndex = erlang:phash2(First, ?CACHE_SIZE)+1, % range is [1,2048]
    CacheLookup = stateCacheLookup(CacheIndex),
    CompactedState = hashState2Int(First),
    WasSent = if Owner == Me -> % my state - send, do not cache
		      Owner ! {compressState(First), Parent, SeqNo, Me, state},
		      1;
		 length(CacheLookup) > 0, element(2,hd(CacheLookup)) == CompactedState -> %First -> 
			% not my state, in cache - do not send
		      stateCacheInsert(?CACHE_HIT_INDEX, getHitCount()+1),
		      0;
		 true -> % not my state, not in cache - send and cache
		      stateCacheInsert(CacheIndex, hashState2Int(First)),
		      Owner ! {compressState(First), Parent, SeqNo, Me, state},
		      1
	      end,
    sendStates(caching, Rest, Parent, SeqNo, Me, Names, NumSent + WasSent);


%%----------------------------------------------------------------------
%% Function: sendStates/7 (NO State Caching)
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%              
%% Args    : First is the state we're currently sending
%%           Rest are the rest of the states to send
%%           Names is a list of PIDs
%%           NumSent is the number of states sent    
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendStates(nocaching, [], _Parent, _SeqNo, _Me, _Names, NumSent) ->
    NumSent;

sendStates(nocaching, [First | Rest], Parent, SeqNo, Me, Names, NumSent) ->
    % TODO set Owner as function of which node has local copy of frag
    Owner = dict:fetch(1+erlang:phash2(First,dict:size(Names)), Names),
    Owner ! {compressState(First), Parent, SeqNo, Me, state},
    sendStates(nocaching, Rest, Parent, SeqNo, Me, Names, NumSent + 1).

%%----------------------------------------------------------------------
%% Function: sendExtraStates/3 
%% Purpose : Redirects owned states to other threads for expansion.
%%				Used for load balancing. Such states are reffered to
%%				as "extra states".
%%              
%% Args    : OtherPID is the PID of the thread to send states to
%%			 First is the current state to send
%%           Rest are the rest of the states to send
%%           NumToSend is the length of Rest 
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendExtraStates(_OtherPID, Rest, 0) ->
	Rest;

sendExtraStates(OtherPID, [First|Rest], NumToSend) ->
	OtherPID ! {First, extraState},
	sendExtraStates(OtherPID, Rest, NumToSend-1).

%%----------------------------------------------------------------------
%% Function: reach/8
%% Purpose : Removes the first state from the list, 
%%		generates new states returned by the call to transition that
%%		are immedetely sent to their owners. Then the input queue
%%		is checked for new states that are eppended to the list of states. 
%%		Recurses until there are no further states to process. 
%% Args    : FirstState is the state to remove from the state queue
%%	     RestStates is the remainder of the state queue
%%	     End is the state we seek - currently ignored
%%		 Names is the list of thread PIDs 
%%	     HashTable is a set of states that have been visited by this 
%%		thread, which are necessarily also owned by this thread. 
%%	     {NumSent, NumRecd} is the running total of the number of states
%%	     sent and received, respectively
%%		 NewStatesList is an artifact that is currently ignored
%%		 Count is the number of visited states
%%		 QLen is the length of RestStates
%%
%% Returns : done
%%     
%%----------------------------------------------------------------------
reach([FirstState | RestStates], End, Names, HashTable, {NumSent, NumRecd},_NewStateList, Count, QLen) ->
            %io:format("~w in reach(~w)~n", [node(), FirstState]),
	    BalFreq = balanceFrequency(),
		IsLB = isLoadBalancing(),
		if IsLB and ((Count rem BalFreq) == 4000)  ->
			sendQSize(Names, dict:size(Names), QLen, RestStates, {NumSent,NumRecd});
		true -> do_nothing
		end, 

		profiling(0, 0, NumSent, NumRecd, Count, QLen),
	    CurState = decompressState(FirstState),
	    NewStates = transition(CurState),
	    % add to HT (and # children as ACKs)
	    {ReqsExplore, SeqNo} = updateElemInHashTable(isUsingMnesia(), FirstState, length(NewStates), HashTable),

            if ReqsExplore ->
                EndFound = stateMatch(CurState,End),
                if EndFound ->
                    ThisNumSent = 0,
                    io:format("=== End state ~w found by ~w PID ~w ===~n", [End, node(), self()]),
                    rootPID(Names) ! end_found;
    	       true -> ThisNumSent = sendStates(NewStates, FirstState, SeqNo, Names)
    	    end;
          true -> ThisNumSent = 0
        end,

		Ret = checkMessageQ(false,Count, Names, {NumSent+ThisNumSent, NumRecd}, 
								HashTable, [],0, {RestStates, QLen-1} ),
 	    if Ret == done ->
			done;
		true -> {NewQ, NewNumRecd, NewQLen} = Ret,
			reach(NewQ, End, Names, HashTable, 
			{NumSent+ThisNumSent, NewNumRecd},[], Count+1, NewQLen)
		end;

% StateQ is empty, so check for messages. If none are found, we die
reach([], End, Names, HashTable, {NumSent, NumRecd}, _NewStates,Count, _QLen) ->
    RandSleep = random:uniform(2000),
    if (Count > 3) -> timer:sleep(RandSleep); % delay to slow spamming the slow nodes
      true -> ok
    end,
    % check messages
    Ret = checkMessageQ(true, Count, Names, {NumSent, NumRecd}, HashTable, [],0, {[],0}),
    if Ret == done -> done;
      true -> {Q, NewNumRecd, NumStates} = Ret,
        % if mnesia, check if anything in state queue
        case firstOfStateQueue(isUsingMnesia(), state_queue) of
          [] -> NewQ = Q;
          NewStates -> io:format("~w in reach([],...) and read state ~w from Mnesia work queue~n", [node(), lists:nth(1, NewStates)]),
            NewQ = lists:append(NewStates, Q) %[State | Q]
        end,
        %NewQ = lists:append(firstOfStateQueue(isUsingMnesia(), state_queue), Q),
        reach(NewQ, End, Names, HashTable, {NumSent, NewNumRecd},[], Count, length(NewQ))
    end.

sendQSize(_Names, 0, _QSize, _StateQ, _NumMess) -> done;

sendQSize(Names, Index, QSize, StateQ, {NumSent, NumRecd}) ->
	Owner = dict:fetch(Index, Names),
        Me = {list_to_atom(getSname()), node()},
	if Owner /= Me ->
	%	io:format("~w PID ~w: Reporting a QSize of ~w~n",[node(), self(),NewQSize]),
		Owner ! {QSize, Me, myQSize},
		sendQSize(Names, Index-1, QSize,StateQ,{NumSent,NumRecd});
	true -> do_nothing
	end,
	sendQSize(Names, Index-1, QSize,StateQ,{NumSent,NumRecd}).

%%----------------------------------------------------------------------
%% Function: dictToList/1
%% Purpose : 
%%		
%% Args    : 
%%	     
%%	     
%% Returns : 
%%     
%%----------------------------------------------------------------------
dictToList(Names) -> element(2,lists:unzip(lists:sort(dict:to_list(Names)))).


%%----------------------------------------------------------------------
%% Function: profile/5
%% Purpose : Provide some progress feedback. For now, WQsize and 
%%           SendQsize are commented out because counting element in list
%%           is expensive. We may change this in the future depending on
%%           how we encode the workQueue
%%		
%% Args    : WQsize is the actual workQueue size
%%           SendQsize is the actual SendList size
%%	     NumSent is the number of states sent so far
%%	     NumRecd is the number of states received so far
%%           Count is the number of visited states
%%
%% Returns : 
%%     
%%---------------------------------------------------------------------
profiling(_WQsize, _SendQsize, NumSent, NumRecd, Count, QLen) ->
    if (Count rem 10000)  == 0 -> 
	    io:format("VS=~w,  NS=~w, NR=~w" ++ 
		      " |MemSys|=~.2f MB, |MemProc|=~.2f MB, |InQ|=~w, |StateQ|=~w, Time=~w-> ~w PID ~w~n", 
		      [Count, NumSent, NumRecd,
		       erlang:memory(system)/1048576, 
		       erlang:memory(processes)/1048576,  	
		       element(2,process_info(self(),message_queue_len)), 
				QLen,
				element(2,now())+element(3,now())*1.0e-6,
		       node(),
		       self()]);

       true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: checkMessageQ/8
%% Purpose : Polls for incoming messages
%%
%% Args    : IsTimeout is boolean indicator of blocking/nonblocking receive;
%%			 only block if it's a non-recursive call or if I'm the root.
%%		BigListSize is used only to report the number of visited states upon termination
%%		Names is the list of PIDs
%%	     {NumSent, NumRecd} is the running total of the number of states
%%	     sent and received, respectively. This does not include 
%%		 ANY load balancing messages (extraStates)
%%	     NewStates is a list accumulating the new received states
%%	     NumStates is the size of NewStates, to avoid calling length(NewStates)
%%		 {CurQ, CurQLen}: 
%%			CurQ is the current state queue before checking for incoming states;
%%		    CurQLen is the length of CurQ. Note that we could easily avoid the parameter
%%			{CurQ,CurQLen} if we perform list concatenation of CurQ and NewStates in 
%%			the calling code.
%% Returns : EITHER List of received states with some bookkeeping in the form of
%%		{NewStateQ, NewNumRecd, NewStateQLen}: 
%%				NewStateQ is NewStates ++ CurQ, NewNumRecd is the running total of
%%					recieved messages,
%%				NewStateQLen is the length of NewStateQ 
%%			OR the atom 'done' to indicate we are finished visiting states
%%     
%%----------------------------------------------------------------------
checkMessageQ(IsTimeout, BigListSize, Names, {NumSent, NumRecd}, HashTable, NewStates, NumStates, {CurQ, CurQLen}) ->
    IsRoot = amIRoot(),
    IsUsingMnesia = isUsingMnesia(),
    if IsRoot and IsUsingMnesia ->
        DiscSQSize = mnesia:activity(sync_dirty, fun mnesia:table_info/2, [state_queue, size], mnesia_frag);
      true -> DiscSQSize = 0
    end,
    Timeout = if (DiscSQSize == 0) and IsTimeout-> 
        if IsRoot -> timeoutTime();
          true -> infinity
        end;
      true -> 0
    end,

	receive
	{State, Parent, SeqNo, Sender, state} ->
            %io:format("~w PID ~w: Received state ~w ~w ~w ~w~n", [node(), self(), State, Parent, SeqNo, Sender]),
	    case isMemberHashTable(State, HashTable) of 
		true ->
                    Sender ! {Parent, SeqNo, ack},
		    checkMessageQ(false,BigListSize,Names,{NumSent, NumRecd+1},HashTable,
				  NewStates, NumStates,{CurQ, CurQLen});
		false ->
	            addElemToHashTableAndStateQueue(isUsingMnesia(), State, HashTable, state_queue),
	            %addElemToHashTable(State, false, 0, HashTable),
                    %addElemToStateQueue(isUsingMnesia(), State, state_queue, 0), % this step and previous should be atomic
                    Sender ! {Parent, SeqNo, ack},
                    % TODO cap in-memory queue size
		    checkMessageQ(false,BigListSize,Names,{NumSent, NumRecd+1},HashTable,
				  [State|NewStates], NumStates+1,{CurQ, CurQLen})
	    end;

	{Parent, SeqNo, ack} ->  % received an ACK for Parent; requires Parent/SeqNo to be send along with State in sendStates()
            %io:format("~w PID ~w: Received ack ~w ~w~n", [node(), self(), Parent, SeqNo]),
	    decrementHashTableAcksOnZeroDelElemFromStateQueue(isUsingMnesia(), Parent, SeqNo, HashTable, state_queue),
	    checkMessageQ(IsTimeout, BigListSize, Names, {NumSent, NumRecd}, HashTable, NewStates, NumStates, {CurQ, CurQLen});

	{State, extraState} ->
			checkMessageQ(false,BigListSize,Names,{NumSent, NumRecd},HashTable,
				  [State|NewStates], NumStates+1,{CurQ,CurQLen});

	{OtherSize, OtherPID, myQSize} ->
		LB = OtherSize + balanceTolerence(),
		{NewQ, NewQLen} = if CurQLen > LB ->
			io:format("~w PID ~w: My Q: ~w, Other Q: ~w, sending ~w extra states to PID ~w~n", 
						[node(), self(),CurQLen,OtherSize, 
						(CurQLen-OtherSize) div balanceRatio(), 
						OtherPID]),
			T1 = sendExtraStates(OtherPID, CurQ, (CurQLen - OtherSize) div balanceRatio()),
			T2 = CurQLen - ((CurQLen - OtherSize) div balanceRatio()),
			{T1,T2};
		true -> {CurQ,CurQLen}
		end,
				checkMessageQ(false,BigListSize,Names,{NumSent, NumRecd},HashTable,
				  NewStates, NumStates, {NewQ,NewQLen});
	
	pause -> % report # messages sent/received
	    rootPID(Names) ! {NumSent, NumRecd, poll},
	    receive     
		{'EXIT', Pid, Reason } ->
		    exitHandler(Pid, Reason, BigListSize, CurQLen+NumStates);

		resume -> % TODO write user scripts to send pause and resume to all nodes
		    checkMessageQ(true, BigListSize, Names, {NumSent, NumRecd},
				  HashTable, NewStates, NumStates,{CurQ,CurQLen});
		die ->
		    terminateMe(BigListSize, rootPID(Names))
	    end;

	die -> 
	    terminateMe(BigListSize, rootPID(Names));

	{'EXIT', Pid, Reason } ->
	    exitHandler(Pid, Reason, BigListSize, CurQLen+NumStates);

	end_found -> 
	    terminateAll(tl(dictToList(Names))),
	    terminateMe(BigListSize, rootPID(Names))

    after Timeout -> % wait for timeoutTime() ms if root
        %if IsUsingMnesia and Timeout /= 0 ->
        %    DiscSQSize = mnesia:activity(sync_dirty, fun mnesia:table_info/2, [state_queue, size], mnesia_frag);
        %  true -> DiscSQSize = 0
        %end,
        if Timeout == 0 ->  % non-blocking case, return 
            {NewStates ++ CurQ, NumRecd, CurQLen+NumStates};
        %  IsUsingMnesia andalso DiscSQSize > 0 ->
            % TODO: Don't terminate if Mnesia state queue is not empty!
        %    {NewStates ++ CurQ, NumRecd, CurQLen+NumStates};
          true -> % otherwise, root polls for termination
            io:format("~w PID ~w: Root has timed out, polling workers now...~n", [node(), self()]),
            CommAcc = pollWorkers(dictToList(Names), {NumSent, NumRecd}),
            CheckSum = element(1,CommAcc) - element(2,CommAcc),
            if CheckSum == 0 ->  % time to die
                io:format("=== No End states were found ===~n"),
                terminateAll(tl(dictToList(Names))),
                terminateMe(BigListSize, rootPID(Names));
              true ->    % resume other processes and wait again for new states or timeout
                io:format("~w PID ~w: unusual, checksum is ~w, will wait " ++ 
                          "again for timeout...~n", [node(), self(),CheckSum]),
                resumeWorkers(tl(dictToList(Names))),
                checkMessageQ(true, BigListSize, Names, {NumSent,NumRecd}, 
                HashTable, NewStates,NumStates, {CurQ,CurQLen})
            end
        end
    end.


%%----------------------------------------------------------------------
%% Function: pollWorkers/2 
%% Purpose :  
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
pollWorkers([], _) ->
    {0,0};

pollWorkers([ThisPID | Rest], {RootSent, RootRecd}) when ThisPID == {pruser0, node()} ->
    {S, R} = pollWorkers(Rest, {RootSent, RootRecd}),
    io:format("~w PID ~w: root CommAcc is {~w,~w}~n", [node(), self(),RootSent,RootRecd]),
    {S+RootSent, R+RootRecd};

pollWorkers([ThisPID | Rest], {RootSent, RootRecd}) ->
    io:format("~w PID ~w: sending pause signal to PID ~w~n", [node(), self(),ThisPID]),
    ThisPID ! pause,
    {S, R} = pollWorkers(Rest, {RootSent, RootRecd}),
    receive
	{'EXIT', Pid, Reason } ->
	    exitHandler(Pid,Reason);

	{ThisSent, ThisRecd, poll} ->
	    io:format("~w PID ~w: Got a worker CommAcc of {~w,~w}~n", 
		      [node(), self(),ThisSent,ThisRecd]),
	    {S+ThisSent, R+ThisRecd}
    end.
%%----------------------------------------------------------------------
%% Function: resumeWorkers/1
%% Purpose :  
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
resumeWorkers(PIDs) ->
    lists:map(fun(PID) -> PID ! resume end, PIDs),
    ok.

%%----------------------------------------------------------------------
%% Function: terminateMe/2
%% Purpose : Terminates "this" node
%% Args    : The number of states visited by this node
%%           The root pid
%% Returns : 
%%     
%%----------------------------------------------------------------------
terminateMe(NumStatesVisited, RootPID) ->
    IsCaching = isCaching(),
    if IsCaching ->
	    io:format("~w PID ~w: was told to die; visited ~w unique states; ~w " ++ 
		      "state-cache hits~n", [node(), self(), NumStatesVisited, getHitCount()]),
	    RootPID ! {{list_to_atom(getSname()), node()}, {NumStatesVisited, getHitCount()}, done};
       true ->
	    io:format("~w PID ~w: was told to die; visited ~w unique states; ~n", 
		      [node(), self(), NumStatesVisited]),
	    RootPID ! {{list_to_atom(getSname()), node()}, {NumStatesVisited, 0}, done}
    end, 
    done.

%%----------------------------------------------------------------------
%% Function: terminateAll/1
%% Purpose : Terminates all processes if the end state is found
%% Args    : A list of the PIDs to send die signals to
%% Returns :
%%     
%%----------------------------------------------------------------------
terminateAll(PIDs) ->
    lists:map(fun(PID) -> PID ! die end, PIDs),
    done.

%%----------------------------------------------------------------------
%% Function: killMsg/1, killMsg/0
%% Purpose : Send an 'EXIT' msg to a node
%% Args    : which node
%% Returns :
%%     
%%----------------------------------------------------------------------
killMsg(Node) ->
    Node ! {'EXIT', 'User', 'User killMsg()'},
    ok.

killMsg() ->
    {HostList,_} = hosts(),
    {NamesList, _} = lists:mapfoldl(fun(X, I) -> {{list_to_atom("pruser" ++ integer_to_list(I)), list_to_atom("pruser" ++ integer_to_list(I) ++ "@" ++ atom_to_list(X))}, I+1} end, 0, HostList),
    lists:foreach(fun(Node) -> Node ! {'EXIT', 'User', 'User killMsg()'} end, NamesList),
    ok.

%%----------------------------------------------------------------------
%% Function: pauseMsg/1, pauseMsg/0
%% Purpose : Send a pause msg to a node
%% Args    : which node
%% Returns :
%%     
%%----------------------------------------------------------------------
pauseMsg(Node) ->
    Node ! pause,
    ok.

pauseMsg() ->
    {HostList,_} = hosts(),
    {NamesList, _} = lists:mapfoldl(fun(X, I) -> {{list_to_atom("pruser" ++ integer_to_list(I)), list_to_atom("pruser" ++ integer_to_list(I) ++ "@" ++ atom_to_list(X))}, I+1} end, 0, HostList),
    lists:foreach(fun(Node) -> Node ! pause end, NamesList),
    ok.

%%----------------------------------------------------------------------
%% Function: resumeMsg/1, resumeMsg/0
%% Purpose : Send a resume msg to a node
%% Args    : which node
%% Returns :
%%     
%%----------------------------------------------------------------------
resumeMsg(Node) ->
    Node ! resume,
    ok.

resumeMsg() ->
    {HostList,_} = hosts(),
    {NamesList, _} = lists:mapfoldl(fun(X, I) -> {{list_to_atom("pruser" ++ integer_to_list(I)), list_to_atom("pruser" ++ integer_to_list(I) ++ "@" ++ atom_to_list(X))}, I+1} end, 0, HostList),
    lists:foreach(fun(Node) -> Node ! resume end, NamesList),
    ok.

%%----------------------------------------------------------------------
%% Function: barrier/2
%% Purpose : It implements a simple barrier to synchronize all threads.
%%           The caller iterates over a set of PIDs check-marking 
%%          their corresponding entry in the Table
%%           1 in the table means 'ready has been received; 0, otherwise
%%           All threads are in sync once all entries are marked w/ 1 
%% Args    : PIDs is a list of pids to be synchonized
%%	     Table is a scoreboard to check-mark thread 'ready' signals
%% Returns : ok or it timesout because it could not synchronize
%%     
%%----------------------------------------------------------------------
barrier([], _Table) -> ok; % hack by Brad to handle the case where P=1

barrier(PIDs, Table) ->
receive
    {ready, Pid} ->
        io:format("barrier: Rx ready from ~w~n",[Pid]),
        NewTable = lists:keyreplace(Pid,1,Table,{Pid,1}),
        NewCount = lists:foldl(fun(X,Acc) -> Acc + element(2,X) end, 0, NewTable),
        if NewCount < length(PIDs) ->
                barrier(PIDs,NewTable);
           true -> ok
        end;

    _Other ->

        barrier(PIDs, Table)
after 60000 ->
        io:format("barrier: ERROR: Haven't got all ack after 60s... sending die"
                  ++ " to ~w~n",[PIDs]),
        lists:map(fun(X) -> X ! die end, PIDs)    ,
        io:format("checkAck: ~w ~w halting for now",[node(), self()]),
        halt()
end.


%%----------------------------------------------------------------------
%% Function: startExternalProfiling/1
%% Purpose : Implements a simple communication w/ ptest
%%          to start the external profiling tools
%% Args    : boolean
%% Returns :
%%     
%%----------------------------------------------------------------------
startExternalProfiling(IsExtProfiling) ->
    case IsExtProfiling of 
	true ->
	    os:cmd("touch /tmp/.preach");
	false->
	    ok
    end.  

%--------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: preach.erl,v $
% Revision 1.36  2009/10/02 01:24:24  binghamb
% Comments and fixed some ugly formatting.
%
% Revision 1.35  2009/09/24 02:21:47  binghamb
% Merged two implementations of checkMessageQ into one. Makes changing the code easier, very slightly changes the algrithm to accept 'pause' messages with each call to checkMessageQ rather than only non-recursive calls. Does not affect correctness. Also fixed a bug related to barrier where deadlock occurs when running a single thread.
%
% Revision 1.34  2009/09/24 00:29:02  binghamb
% Implemented Kumar and Mercer-esq load balancing scheme. Enable/Disable by setting function isLoadBalancing() true or false, and other load balancing parameters. Also changed the model checking algorithm to a tighter recurrence of expand/send/receive to facilitate load balancing and a strong sense of what an iteration is.
%
% Revision 1.33  2009/09/19 03:23:28  depaulfm
% Implemented a barrier for PReach's initialization; Added hooks for the network profiling
%
% Revision 1.32  2009/08/24 18:22:28  depaulfm
% Moved hash table membership and insertion to checkMessageQ to reflect Stern and Dill's algorithm
%
% Revision 1.31  2009/08/22 19:52:00  depaulfm
% By adding the exit handler I introduced a bug in waitForTerm; I re-wrote waitForTerm so that it properly handles EXIT messages from workers
%
% Revision 1.30  2009/08/22 18:17:20  depaulfm
% Abstracted away how the hash table is implemented
%
% Revision 1.29  2009/08/22 17:34:14  depaulfm
% Finished abstracting state caching; Modified state caching to store only the 32-bit hashed value of states; added EXIT handler routine together w/ process_flag to trap on exit; code cleanup
%
% Revision 1.28  2009/08/19 05:08:20  depaulfm
% Fixed start/autoStart funs by reverting prior intent of defining number of threads on a subset of names in the hosts file; added a profiling function; tested n5_peterson and n6_peterson on 8 threads
%
% Revision 1.27  2009/08/18 22:03:00  depaulfm
% Added setup fun to cleanly handle localmode vs distributed mode; replaced spawn w/ spawn_link so that when a worker dies the root gets notified; fixed path the hrl file
%
% Revision 1.26  2009/07/23 16:28:35  depaulfm
% Added header call to preach.hrl
%
% Revision 1.25  2009/07/23 16:15:59  depaulfm
% DEV/SRC/preach.erl:
%
% Partially abstracted away how caching is handled. Still need to abstract away cache ets:lookups and ets:insert;
% Made two versions of sendStates: caching, nocaching for easy readability;
% Created preach.erl to contain macros and some util functions;
% Changed the spawn call from 'test' to '?MODULE'. Now, each file and module should follow the standard of having the same name
% Continue code clean up
%
%
% DEV/TB/hosts:
%
% Added 'main' hosts which should contain all hosts from which preach can choose;
%
% DEV/TB/dek/Emakefile,
% DEV/TB/german/Emakefile,
% DEV/TB/peterson/Emakefile,
% DEV/TB/stress/Emakefile:
%
% Added makefile for every example. Can be called from erl prompt by issuing make:all().
%
%
% DEV/TB/dek/dek_modified.erl,
% DEV/TB/german/german2.erl,
% DEV/TB/german/german3.erl,
% DEV/TB/german/german4.erl,
% DEV/TB/peterson/n5_peterson_modified.erl,
% DEV/TB/peterson/n6_peterson_modified.erl,
% DEV/TB/peterson/n7_peterson_modified.erl:
%
% Modified all examples adding autoStart, which is called from ptest;
% Changed module names to be the same as the file name
%
%
% SCRIPTS/ptest:
%
% Added script to automatically compile and run the desired tests;
% Requires $PREACH_PATH/SCRIPTS to be in the $PATH
%
% Revision 1.24  2009/07/16 21:19:29  depaulfm
% Made state caching an option to be passed to erl as -statecaching; more code clean-up
%
% Revision 1.23  2009/07/15 00:26:36  depaulfm
% First cut at clean up
%
% Revision 1.22  2009/06/24 00:24:09  binghamb
% New caching scheme; changed from calling startstate() in gospel code to startstates(), which returns a list instead of a single state.
%
% Revision 1.21  2009/06/22 21:16:46  binghamb
% Implemented a first shot at state-caching.
%
% Revision 1.20  2009/06/03 16:36:23  depaulfm
% Removed ets references and unwanted commented lines; **FIXED** slaves traversal of list hostlist; **REPLACED** ets w/ bloom filter w/ fixed-sized, left commented out scalable bloom filters; The fixed-size of the bloom-filter HAS to become a parameter eventually (it is hardcoded right now); **MODIFIED** interface of reach to count visited states
%
% Revision 1.19  2009/05/25 01:47:05  depaulfm
% Generalized mynode; Modified start to read a file containing a list of hosts; Added slaves which starts each node; Modified initThreads to take into account the generalized mynode. It requires a file called host in the directory from which you launch erl. Erlang should be launched w/ the following erl -sname pruser1 -rsh ssh
%
% Revision 1.18  2009/05/14 23:14:17  binghamb
% Changed the way we send states. Now using John's idea of sending all generated states at once after the state-queue has been consumed, rather than interleaving the consumption of a state and the sending of it's sucessors. Improve performance on a couple small tests.
%
% Revision 1.17  2009/05/09 01:53:12  jbingham
% sneding to brad
%
% Revision 1.16  2009/05/02 00:37:12  jbingham
% made a few minor tweaks to make preach work with the current german2nodes.erl.
% brad told me to check them in, so if this annoys you blame him
%
% Revision 1.15  2009/04/23 07:53:48  binghamb
% Testing the German protocol.
%
% Revision 1.14  2009/04/22 05:11:00  binghamb
% Working to get preach and german to work together. Currently not reaching all the states we should be.
%
% Revision 1.13  2009/04/15 16:25:17  depaulfm
% Changed interface; removed module/export definitions; Gospel code should include preach.erl and export its called functions; Requires PREACH_PATH env variable set
%
% Revision 1.12  2009/04/14 18:31:50  binghamb
% Fixed incorrect module name in previous commit
%
% Revision 1.11  2009/04/13 18:15:37  binghamb
% List of PIDs now implemented with a dict instead of an erlang list
%
% Revision 1.10  2009/03/28 00:59:35  binghamb
% Using ets table instead of dict; fixed a bug related to not tagging the PID lis with an atom when sending.
%
% Revision 1.9  2009/03/25 23:54:44  binghamb
% Fixed the deadlock bug; now all termination signals come from the root only. Cleaned up some code and moved the default model to tiny.erl.
%
% Revision 1.8  2009/03/22 23:52:50  binghamb
% Substantial changes to communication. Implemented a termination scheme similar to Stern and Dill's. This has introduced a rarely occuring deadlock bug which is easily fixable. Also more verbose output.
%
% Revision 1.7  2009/03/18 23:28:20  binghamb
% Enabled distributed threads for testing purposes. Also allowing bit packing with stress test, and some code cleanup stuff.
%
% Revision 1.6  2009/03/14 00:47:21  binghamb
% Changed from using sets to dict for storing states.
%
% Revision 1.5  2009/03/14 00:20:44  binghamb
% No longer caching ALL states generated. Instead, store all states OWNED by a given processor. This change increases the number of messages but decreases the upper bound on memory per process.
%
% Revision 1.4  2009/03/10 20:25:02  binghamb
% One line change: dek:transition -> transition
%
% Revision 1.3  2009/03/10 20:22:37  binghamb
% Compatable with dek.m. Changed main function start, now preach:start(Start,End,P).
%
% Revision 1.2  2009/02/23 02:43:40  binghamb
% Deleted some commented out code and filled in details in function/module headers
%
% Revision 1.1  2009/02/14 00:53:47  depaulfm
% Continue Bootstrapping repository
%
