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
timeoutTime() -> 2000.

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
    if IsUsingMnesia -> visited_state;
      true -> bloom:bloom(?BLOOM_N_ENTRIES,?BLOOM_ERR_PROB)
    end.

%%----------------------------------------------------------------------
%% Function: addElemToHTAndSQReturnIsMember/4
%% Purpose : Add the element to the Mnesia persisted hash table and 
%%              state queue if not already in hash table.  Use this 
%%              when we first receive.  Writes to both atomically.
%% Args    : boolean, State, table name, table name
%% Returns : bool: was element already in HT?
%%     
%%----------------------------------------------------------------------
addElemToHTAndSQReturnIsMember(IsUsingMnesia, Element, HashTable, StateQueue) ->
    if IsUsingMnesia ->
        mnesia:activity(sync_transaction, fun(E, HT, SQ) -> 
            case mnesia:read(HT, E, write) of
              [] -> mnesia:write(SQ, {SQ, Element, 0}, write),
                mnesia:write(HT, {HT, Element, 0}, write),
                false;
              [_|_] -> true
            end
        end, [Element, HashTable, StateQueue], mnesia_frag);
      true -> Ret = bloom:member(Element, HashTable),
        if Ret -> ok;
          true -> bloom:add(Element, HashTable)
        end,
        Ret
    end.

%%----------------------------------------------------------------------
%% Function: createACKTable/1
%% Purpose : Routines to abstract away how the hash table is implemented, eg,
%%           erlang lists, ets or dict, bloom filter
%%               
%% Args    : 
%%
%% Returns : an ets table or null
%%     
%%----------------------------------------------------------------------
createACKTable(IsUsingMnesia) ->
    if IsUsingMnesia ->
        ets:new(acktable, []);
      true -> null
    end.

%%----------------------------------------------------------------------
%% Function: addElemInACKTable/5
%% Purpose : Add a state to the ACK table if its children are still 
%%           not known to be stored to disk (== state is still in SQ)
%%               
%% Args    : Element is the state that we want to add
%%           OutstandingAcks is the number of ACKs left
%%           ACKTable is the name of the ACK table returned by createACKTable
%%           StateQueue is the name of the mnesia state queue
%%
%% Returns : {bool: true if this state has not been explored, 
%%           integer: the new ACK sequence number}
%%     
%%----------------------------------------------------------------------
addElemInACKTable(IsUsingMnesia, Element, OutstandingAcks, ACKTable, StateQueue) ->
    if IsUsingMnesia ->
        ReqExplore = case mnesia:activity(sync_transaction, fun mnesia:read/3, [StateQueue, Element, read], mnesia_frag) of
          [] -> false;
          [_|_] -> true
        end,
        SeqNo = if ReqExplore ->
            case ets:lookup(ACKTable, Element) of
              [] -> ets:insert(ACKTable, {Element, OutstandingAcks, 1}),
                1;
              [{_,_,S}|_] -> ets:insert(ACKTable, {Element, OutstandingAcks, S+1}),
                S+1
            end;
          true -> 0
        end,
        {ReqExplore, SeqNo};
      true -> {true, 0}
    end.

%%----------------------------------------------------------------------
%% Function: decACKsOnZeroDelFromSQ/7
%% Purpose : Decrements the ACKs outstanding for this element.  If ACKs
%%              outstanding is 0 after doing this, delete the element
%%              from the State Queue.
%% Args    : boolean, State, integer, integer, integer, table name, table name
%% Returns : ok or warning
%%     
%%----------------------------------------------------------------------
decACKsOnZeroDelFromSQ(IsUsingMnesia, Element, SeqNo, EpicNo, MyEpic, ACKTable, StateQueue) ->
    if IsUsingMnesia and (EpicNo == MyEpic) ->
        if Element /= null -> % TODO track ACKs for start states
            case ets:lookup(ACKTable, Element) of
              [] -> ok;
              [{_,A,S}|_] -> 
                if (S == SeqNo) and (A =< 0) -> {warning, acks_zero};
                  (S == SeqNo) and (A == 1) -> 
                    mnesia:activity(sync_transaction, fun mnesia:delete/3, [StateQueue, Element, write], mnesia_frag),
                    ets:delete(ACKTable, Element),
                    ok;
                  (S == SeqNo) -> ets:insert(ACKTable, {Element, A-1, S}), ok;
                  true -> ok
                end
            end;
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
    mnesia:create_table(epic_num, [{disc_copies, NodePool}, {local_content, true}]),
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
    if IsUsingMnesia ->
        mnesia:change_config(dc_dump_limit, 40),
        mnesia:change_config(dump_log_write_threshold, 50000),
        if MnesiaSchemaExists ->
            mnesia:start();
          true ->
            if IAmRoot -> createMnesiaTables(Names);
              true -> attachToMnesiaTables(Names)
            end
        end,
        mnesia:activity(sync_transaction, fun mnesia:wait_for_tables/2, [[visited_state, state_queue, epic_num], 10000], mnesia_frag);
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
        SQKeys = mnesia:activity(sync_transaction, fun mnesia:all_keys/1, [StateQueue], mnesia_frag),
        if length(SQKeys) == 0 -> [];
          true -> lists:sublist(SQKeys, random:uniform(length(SQKeys)), random:uniform(2000))
        end;
      true -> []
    end.

%%----------------------------------------------------------------------
%% Function: incEpicNum/2
%% Purpose : increments the epic number stored in the disc_only_copies 
%%           NodeData table
%% Args    : bool, mnesia table name
%% Returns : integer
%%     
%%----------------------------------------------------------------------
incEpicNum(IsUsingMnesia, NodeData) ->
    if IsUsingMnesia ->
        {atomic, EpicNum} = mnesia:transaction(fun(X) ->
            case mnesia:read(X, node()) of
              [] -> mnesia:write(X, {X, node(), 0}, write),
                0;
              [{_,_,E}|_] -> mnesia:write(X, {X, node(), E+1}, write),
                E+1
            end
        end, [NodeData]),
        EpicNum;
      true -> 0
    end.

%%----------------------------------------------------------------------
%% Function: stopMnesia/1
%% Purpose : Stops the Mnesia DBMS
%% Args    : boolean
%% Returns : ok
%%     
%%----------------------------------------------------------------------
stopMnesia(IsUsingMnesia) ->
    if IsUsingMnesia -> mnesia:stop(), ok;
      true -> ok
    end.

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
    %stateToInt(State).
    stateToBits(State).
    %State.

decompressState(CompressedState) ->
    %intToState(CompressedState).
    bitsToState(CompressedState).
    %CompressedState.

%hashState2Int(State) ->
%    erlang:phash2(State,round(math:pow(2,32))).

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
%% Function: updateOwners/1, updateOwners/3
%% Purpose : redo the fragment number to Owner mapping (MNESIA)
%% Args    : old dict
%% Returns : new dict
%%     
%%----------------------------------------------------------------------
updateOwners(Names) ->
    dict:from_list(updateOwners(lists:seq(1, dict:size(Names)), [], [])).

updateOwners([], _Acc, Result) -> Result;
updateOwners([FragNum|Rest], Acc, Result) -> 
    FragName = if FragNum == 1 -> visited_state; true -> list_to_atom("visited_state_frag"++integer_to_list(FragNum)) end,
    HostList = lists:sort(mnesia:table_info(FragName, where_to_write)),
    SeenBefore = lists:sort(fun({_,A},{_,B}) -> (A > B) end, lists:filter(fun({H, _}) -> lists:member(H, HostList) end, Acc)),
    if (HostList == []) -> io:format("Error: Nowhere to write ~w~n", [FragName]), halt();
      (SeenBefore == []) -> updateOwners(Rest, [{H,1} || H <- tl(HostList)] ++ Acc, Result ++ [{FragNum, {list_to_atom(string:sub_word(atom_to_list(hd(HostList)), 1, $@)), hd(HostList)}}]);
      true -> % remove the elements from Acc and add them back in with incremented count
        ExistingAcc = [{H1, C+1} || H1 <- HostList, H1 =/= element(1,hd(SeenBefore)), {H2,C} <- Acc, H1 == H2],
        NewAcc = [{H1, 1} || H1 <- HostList, H1 =/= element(1,hd(SeenBefore)), not lists:keymember(H1, 1, ExistingAcc)],
        updateOwners(Rest, ExistingAcc ++ NewAcc ++ [{H, C} || {H, C} <- Acc, H =/= element(1,hd(SeenBefore)), not lists:keymember(H, 1, ExistingAcc)], Result ++ [{FragNum, {list_to_atom(string:sub_word(atom_to_list(element(1,hd(SeenBefore))), 1, $@)), element(1,hd(SeenBefore))}}])
    end.

%%----------------------------------------------------------------------
%% Function: start/0
%% Purpose : A timing wrapper for the parallel version of 
%%				our model checker.
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
start() ->
    register(list_to_atom(getSname()), self()),
    IAmRoot = amIRoot(),
    {HostList,_Nhosts} = hosts(),
    {NamesList, P} = lists:mapfoldl(fun(X, I) -> {{list_to_atom("pruser" ++ integer_to_list(I)), list_to_atom("pruser" ++ integer_to_list(I) ++ "@" ++ atom_to_list(X))}, I+1} end, 0, HostList),
    lists:foreach(fun(X) -> io:format("~w~n", [X]) end, NamesList),
    StaticNames = dict:from_list(lists:zip(lists:seq(1, length(NamesList)), NamesList)),
    %% when sending messages, use {PID, pruserX@node} ! Message
    %% might want to register(pruserX, self()) so don't need to know PIDs
    %% Names should just be where nodes can send each other messages
    % TODO update Names when hot spare join

    %% HashTable is the set of states seen
    %% StateQueue is the set of states whose children are not all known to be stored to disk
    %% NodeData is a private table with a single record storing the epic number -- how many times this node has been restarted
    %% ACKTable is RAM only ets table storing the ACKs-remaining counter and the sequence number per state
    IsUsingMnesia = isUsingMnesia(),
    HashTable = createHashTable(IsUsingMnesia),
    StateQueue = state_queue,
    NodeData = epic_num,
    addMnesiaTables(IsUsingMnesia, StaticNames), % TODO: take names of HashTable, StateQueue, NodeData
    EpicNum = incEpicNum(IsUsingMnesia, NodeData),
    ACKTable = createACKTable(IsUsingMnesia),
    timer:sleep(4000),
    Names = if IsUsingMnesia -> updateOwners(StaticNames); true -> StaticNames end,

    {A1,A2,A3} = now(),
    random:seed(A1, A2, A3),

    if IAmRoot ->
        %% barrier here until all nodes up: wait for message from all others
        Others = [OtherNodes || OtherNodes <- dictToList(Names),  OtherNodes =/= {list_to_atom(getSname()),node()}],
        barrier(Others, lists:zip(Others, lists:duplicate(length(Others), 0))),
        T0 = now(),
        sendStates(startstates(), null, 1, EpicNum, Names),
        NumSent = length(startstates()),

        reach([], null, Names, HashTable, StateQueue, ACKTable, EpicNum, {NumSent, 0}, [], 0, 0), %should remove null param

        if IsUsingMnesia -> mnesia:info(),
            NumMnesiaUniqStates = mnesia:activity(sync_transaction, fun()->mnesia:table_info(visited_state, size) end, mnesia_frag); %TODO: this is sometimes reporting incorrect number
          true -> NumMnesiaUniqStates = 0
        end,
        io:format("~w PID ~w: waiting for workers to report termination...~n", [node(), self()]),
        {NumStates, _NumHits} = waitForTerm(dictToList(Names), 0, 0, 0),
        Dur = timer:now_diff(now(), T0)*1.0e-6,
        NumPurged = purgeRecQ(0),
        if IsUsingMnesia -> NumUniqStates = NumMnesiaUniqStates;
          true -> NumUniqStates = NumStates
        end,

        io:format("----------~n"),
        io:format("REPORT:~n"),
        io:format("\tTotal of ~w unique states visited over all runs~n", [NumUniqStates]),
        io:format("\tTotal of ~w non-unique states visited this run~n", [NumStates]),
        io:format("\t~w messages purged from the receive queue~n", [NumPurged]),
        io:format("\tExecution time [current run]: ~f seconds~n", [Dur]),
        io:format("\tNon-unique states visited per second [current run]: ~w~n", [trunc(NumStates/Dur)]),
        io:format("\tNon-unique states visited per second per thread [current run]: ~w~n", [trunc((NumStates/Dur)/P)]);
      true ->
        rootPID(Names) ! {ready, {list_to_atom(getSname()),node()}},
        reach([], null, Names, HashTable, StateQueue, ACKTable, EpicNum, {0,0}, [], 0, 0),
        io:format("~w PID ~w: Worker ~w is done~n", [node(), self(), node()]),
        mnesia:info(),
        timer:sleep(5000)
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
                "termination~n", [node(), self(), DiffPID]),
            waitForTerm(PIDs,TotalStates + NumStates, TotalHits + NumHits, Cover +1);
          {'EXIT', Pid, Reason } ->
            exitHandler(Pid,Reason),
            NumStates = 0,
            NumHits = 0,
            waitForTerm(PIDs,TotalStates + NumStates, TotalHits + NumHits, Cover)
        end;
      true -> {TotalStates, TotalHits}
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
      after 100 -> Count
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
        halt();
      true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: sendStates/5
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
sendStates(States, Parent, SeqNo, EpicNo, Names) -> 
    %io:format("~w PID ~w: sendStates ~w ~w ~w ~w~n", [node(), self(), States, Parent, SeqNo, EpicNo]),
    Me = {list_to_atom(getSname()), node()},
    sendStates(nocaching, States, Parent, SeqNo, EpicNo, Me, Names, 0).

%%----------------------------------------------------------------------
%% Function: sendStates/8 (NO State Caching)
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%              
%% Args    : First is the state we're currently sending
%%           Rest are the rest of the states to send
%%           Names is a list of PIDs
%%           NumSent is the number of states sent    
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendStates(nocaching, [], _Parent, _SeqNo, _EpicNo, _Me, _Names, NumSent) ->
    NumSent;

sendStates(nocaching, [First | Rest], Parent, SeqNo, EpicNo, Me, Names, NumSent) ->
    IsUsingMnesia = isUsingMnesia(),
    if IsUsingMnesia ->
        % set Owner as function of which node has local copy of frag
        {_,_,_,_,FragHash} = mnesia:table_info(visited_state, frag_hash),
        FragNum = 1+(mnesia_frag_hash:key_to_frag_number(FragHash, First) rem dict:size(Names)), % TODO: this is broken / size(Names) is a hack for # of fragments since I set them equal
        Owner = dict:fetch(FragNum, Names);
        %io:format("~w sendStates FragHash=~w FragNum=~w Owner=~w~n", [node(), FragHash, FragNum, Owner]),
        %timer:sleep(1000);
      true ->
        Owner = dict:fetch(1+erlang:phash2(First,dict:size(Names)), Names)
    end,
    Owner ! {compressState(First), Parent, SeqNo, EpicNo, Me, state},
    sendStates(nocaching, Rest, Parent, SeqNo, EpicNo, Me, Names, NumSent + 1).

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
reach([FirstState | RestStates], End, Names, HashTable, StateQueue, ACKTable, EpicNum, {NumSent, NumRecd}, _NewStateList, Count, QLen) ->
    %io:format("~w in reach(~w)~n", [node(), FirstState]),
    profiling(0, 0, NumSent, NumRecd, Count, QLen),
    CurState = decompressState(FirstState),
    NewStates = transition(CurState),
    % ACKTable.insert({S, length(S.children), seqno})
    {ReqsExplore, SeqNo} = addElemInACKTable(isUsingMnesia(), FirstState, length(NewStates), ACKTable, StateQueue),

    if ReqsExplore ->
        EndFound = stateMatch(CurState,End),
        if EndFound ->
            ThisNumSent = 0,
            io:format("=== End state ~w found by ~w PID ~w ===~n", [End, node(), self()]),
            rootPID(Names) ! end_found;
          true -> ThisNumSent = sendStates(NewStates, FirstState, SeqNo, EpicNum, Names)
        end;
      true -> ThisNumSent = 0
    end,

    Ret = checkMessageQ(false,Count, Names, {NumSent+ThisNumSent, NumRecd}, HashTable, StateQueue, ACKTable, EpicNum, [], 0, {RestStates, QLen-1} ),
    if Ret == done -> done;
      true -> {NewQ, NewNumRecd, NewQLen} = Ret,
        reach(NewQ, End, Names, HashTable, StateQueue, ACKTable, EpicNum, {NumSent+ThisNumSent, NewNumRecd},[], Count+1, NewQLen)
    end;

% StateQ is empty, so check for messages. If none are found, we die
reach([], End, Names, HashTable, StateQueue, ACKTable, EpicNum, {NumSent, NumRecd}, _NewStates, Count, _QLen) ->
    RandSleep = random:uniform(2000),
    if (Count > 3) -> timer:sleep(RandSleep); % delay to slow spamming the slow nodes
      true -> ok
    end,
    % check messages
    Ret = checkMessageQ(true, Count, Names, {NumSent, NumRecd}, HashTable, StateQueue, ACKTable, EpicNum, [], 0, {[], 0}),
    if Ret == done -> done;
      true -> {Q, NewNumRecd, _NumStates} = Ret,
        % if mnesia, check if anything in state queue
        case firstOfStateQueue(isUsingMnesia(), StateQueue) of
          [] -> NewQ = Q;
          NewStates -> io:format("~w in reach([],...) and read states [~w, ...] from Mnesia work queue~n", [node(), lists:nth(1, NewStates)]),
            NewQ = lists:append(NewStates, Q) %[State | Q]
        end,
        %NewQ = lists:append(firstOfStateQueue(isUsingMnesia(), StateQueue), Q),
        reach(NewQ, End, Names, HashTable, StateQueue, ACKTable, EpicNum, {NumSent, NewNumRecd}, [], Count, length(NewQ))
    end.

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
%% Function: checkMessageQ/11
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
checkMessageQ(IsTimeout, BigListSize, Names, {NumSent, NumRecd}, HashTable, StateQueue, ACKTable, MyEpicNum, NewStates, NumStates, {CurQ, CurQLen}) ->
    IsRoot = amIRoot(),
    IsUsingMnesia = isUsingMnesia(),
    if IsUsingMnesia -> %(IsRoot and IsUsingMnesia)
        DiscSQSize = mnesia:activity(sync_transaction, fun mnesia:table_info/2, [StateQueue, size], mnesia_frag);
      true -> DiscSQSize = 0
    end,
    Timeout = if ((DiscSQSize == 0) and IsTimeout) ->
        if IsRoot -> timeoutTime();
          true -> infinity
        end;
      true -> 0
    end,

    receive
    {State, Parent, SeqNo, EpicNo, Sender, state} ->
        %io:format("~w PID ~w: Received state ~w ~w ~w ~w ~w~n", [node(), self(), State, Parent, SeqNo, EpicNo, Sender]),
        IsMember = addElemToHTAndSQReturnIsMember(IsUsingMnesia, State, HashTable, StateQueue),
        Sender ! {Parent, SeqNo, EpicNo, ack},
        if IsMember or (IsUsingMnesia and ((NumStates + CurQLen) >= 5000)) ->  % cap in-memory queue size
            checkMessageQ(false, BigListSize, Names, {NumSent, NumRecd+1}, HashTable, StateQueue, ACKTable, MyEpicNum, NewStates, NumStates,{CurQ, CurQLen});
          true ->
            checkMessageQ(false, BigListSize, Names, {NumSent, NumRecd+1}, HashTable, StateQueue, ACKTable, MyEpicNum, [State|NewStates], NumStates+1,{CurQ, CurQLen})
        end;

    {Parent, SeqNo, EpicNo, ack} ->  % received an ACK for Parent; requires Parent/SeqNo to be send along with State in sendStates()
        %io:format("~w PID ~w: Received ack ~w ~w ~w~n", [node(), self(), Parent, SeqNo EpicNo]),
        AckResult = decACKsOnZeroDelFromSQ(IsUsingMnesia, Parent, SeqNo, EpicNo, MyEpicNum, ACKTable, StateQueue),
        if AckResult == {warning, acks_zero} ->
            io:format("~w received ACK for state ~w when ACKs outstanding <= 0, SeqNo = ~w EpicNo = ~w~n", [node(), Parent, SeqNo, EpicNo]);
          true -> ok
        end,
        checkMessageQ(IsTimeout, BigListSize, Names, {NumSent, NumRecd}, HashTable, StateQueue, ACKTable, MyEpicNum, NewStates, NumStates, {CurQ, CurQLen});

    pause -> % report # messages sent/received
        rootPID(Names) ! {NumSent, NumRecd, poll},
        receive     
          {'EXIT', Pid, Reason } ->
            exitHandler(Pid, Reason, BigListSize, CurQLen+NumStates);
          resume -> % TODO write user scripts to send pause and resume to all nodes
            checkMessageQ(true, BigListSize, Names, {NumSent, NumRecd}, HashTable, StateQueue, ACKTable, MyEpicNum, NewStates, NumStates,{CurQ,CurQLen});
          die -> terminateMe(BigListSize, rootPID(Names))
        end;

    die -> 
        terminateMe(BigListSize, rootPID(Names));

    {'EXIT', Pid, Reason } ->
        exitHandler(Pid, Reason, BigListSize, CurQLen+NumStates);

    end_found -> 
        terminateAll(tl(dictToList(Names))),
        terminateMe(BigListSize, rootPID(Names))

    after Timeout -> % wait for timeoutTime() ms if root
        if Timeout == 0 ->  % non-blocking case, return 
            {NewStates ++ CurQ, NumRecd, CurQLen+NumStates};
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
                checkMessageQ(true, BigListSize, Names, {NumSent,NumRecd}, HashTable, StateQueue, ACKTable, MyEpicNum, NewStates, NumStates, {CurQ, CurQLen})
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
      {'EXIT', Pid, Reason } -> exitHandler(Pid,Reason);
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
    io:format("~w PID ~w: was told to die; visited ~w non-unique states; ~n", 
        [node(), self(), NumStatesVisited]),
    RootPID ! {{list_to_atom(getSname()), node()}, {NumStatesVisited, 0}, done},
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
      _Other -> barrier(PIDs, Table)
    after 60000 ->
        io:format("barrier: ERROR: Haven't got all ack after 60s... sending die"
            ++ " to ~w~n",[PIDs]),
        lists:map(fun(X) -> X ! die end, PIDs),
        io:format("checkAck: ~w ~w halting for now",[node(), self()]),
        halt()
    end.
