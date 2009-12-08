%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [preach.erl]
%
%  PackageName                [preach]
%
%  Synopsis                   [Main erl module for Parallel Model Checking]
%
%  Author                     [BRAD BINGHAM, FLAVIO M DE PAULA]
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
createHashTable() ->
  IsUsingMnesia = isUsingMnesia(),
  if IsUsingMnesia ->

    %TableName = visited_state,
    %io:format("~w creating hash table ~w~n", [node(), TableName]),
    %Status = mnesia:create_table(TableName, [{disc_copies, [node()]}, {local_content, true}, {attributes, record_info(fields, visited_state)}]),
    %io:format("~w creating hash table ~w status ~w~n", [node(), TableName, Status]),
    %mnesia:info(),
    %lists:map(fun(Node) -> 
    %              SlaveStatus = mnesia:add_table_copy(visited_state, Node, disc_copies),
    %              io:format("add ~w to visited_state table status = ~w~n", [Node, SlaveStatus])
    %          end, nodes()),
    %TableName;
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
    case mnesia:transaction(fun() -> mnesia:read(HashTable, Element) end) of 
	{atomic, [_X | _Y]} ->
	     true;
	{atomic, []} ->
	    false;
        _Else ->
            %io:format("~w isMemberHashTable(~w, ~w) returned ~w~n", [node(), Element, HashTable, Else]),
            false
    end;
   true -> 
    case bloom:member(Element,HashTable) of
        true ->
             true;
        false ->
            false
    end
  end.

%%----------------------------------------------------------------------
%% Function: addElemToHashTable/2
%% Purpose : Add a state to the hash table
%%           
%%               
%% Args    :  Element is the state that we want to add
%%           HashTable is the name of the hash table returned by
%%           createHashTable
%%
%% Returns : a variable which type depends on the implementation, eg, 
%%           bloom filter will return a record type; 
%%     
%%----------------------------------------------------------------------
addElemToHashTable(Element, HashTable)->
  IsUsingMnesia = isUsingMnesia(),
  if IsUsingMnesia ->
    % massage Element into correct record type (table name is first element)
    Record = #visited_state{state = Element, processed = false},
    case mnesia:transaction(fun() -> mnesia:write(HashTable, Record, write) end) of
        {atomic, _} -> ok;
        Else -> %io:format("~w addElemToHashTable(~w, ~w) returned ~w~n", [node(), Element, HashTable, Else]),
                Else
    end;
   true -> bloom:add(Element,HashTable)
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
%% Function: slaves/2 
%% Purpose : Iterates over hosts and starts them as slaves (erlang terminology). 
%%           
%%
%% Args    : Hosts is the list of hosts 
%%           CWD is the current directory of the master node 
%%           NHosts is the number of hosts 
%%
%% Returns : 
%%     
%%----------------------------------------------------------------------
slaves(_HostList, _CWD, 1) -> 
    [node()];
slaves([Host|Hosts], CWD, NHosts) ->
    io:format("slaves Host = ~w~n", [Host]),
    Args = "+h 100000 -setcookie " ++ atom_to_list(erlang:get_cookie()) ++
	" -pa " ++ CWD ++ " -pa " ++ CWD ++ "/ebin " ++  "-smp enable",
    NodeName = string:concat("pruser", integer_to_list(NHosts)),
    
    % Pass cache option to workers 
    IsCaching = isCaching(),
    if IsCaching -> 
	    Args0 = Args ++ " -statecaching"; 
       true -> 
	    Args0 = Args 
    end,
    % Pass external profile option to workers
    IsExtProfile = isExtProfiling(),
    if IsExtProfile -> 
	    Args1 = Args0 ++ " -nprofile"; 
       true -> 
	    Args1 = Args0 
    end,
    % Pass mnesia dir option to workers
    IsUsingMnesia = isUsingMnesia(),
    if IsUsingMnesia -> 
            MyHost = list_to_atom(lists:nth(2, string:tokens(atom_to_list(node()), "@"))),
            if MyHost == Host ->
	        MyMnesiaDir = "'\"" ++ string:sub_string(getMnesiaDir(), 2, string:len(getMnesiaDir())-1) ++ integer_to_list(NHosts) ++ "\"'";
               true ->
	        MyMnesiaDir = "\\'\\\"" ++ string:sub_string(getMnesiaDir(), 2, string:len(getMnesiaDir())-1) ++ integer_to_list(NHosts) ++ "\\\"\\'"
            end,
	    io:format("~s@~s Starting Mnesia in dir ~s.~n",[NodeName, Host, MyMnesiaDir]),  %% comment this out when done
	    Args2 = Args1 ++ " -mnesia dir " ++ MyMnesiaDir; 
       true -> 
	    Args2 = Args1 
    end,

    SchemaNames = case slave:start_link(Host, NodeName, Args2) of
	{ok, Node} ->
	    io:format("Erlang node started = [~p]~n", [Node]),
	    slaves(Hosts, CWD, NHosts - 1);
	{error,timeout} ->
	    io:format("Could not connect to host ~w...Exiting~n",[Host]),
	    halt();
	{error,Reason} ->
	    io:format("Could not start workers: Reason= ~w...Exiting~n",[Reason]),
	    halt()
    end,

    [list_to_atom(NodeName ++ "@" ++ atom_to_list(Host) ) | SchemaNames].


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
%% Function: setup/0
%% Purpose : Automatically start the distributed erts, or statrt locally
%%           if in local mode
%%           
%%            	
%% Args    : Ordered dictionary of pids, where element 1 maps to the root
%%          machine
%%         
%% Returns : pid
%%     
%%----------------------------------------------------------------------
setup() ->
    LocalMode = isLocalMode(),
    if LocalMode  ->
	    %% FMP should remove null param
	    Names = initThreads([], 1, null, [], 0),
	    Nhosts = 1;
       true ->
	    {HostList,Nhosts} = hosts(),
	    {Status, CWD} = file:get_cwd(),
	    if Status == error ->
                    Names = null,
		    Nhosts = 0,
		    io:format("setup: Error Could not read current directory." ++"
                               Erlang reason: '~w'. ",[CWD]),
                       halt();
	       true ->  
		    SchemaNames = slaves(lists:reverse(tl(HostList)), CWD, Nhosts),
		    %FMP should remove null param
		    Names = initThreads([], Nhosts, null,HostList, Nhosts)
	    end
    end,
    {Names, Nhosts}.

%%----------------------------------------------------------------------
%% Function: start/3
%% Purpose : A timing wrapper for the parallel version of 
%%				our model checker.
%% Args    : P is the number of Erlang threads to use;
%%			Start is a list of states to initialize the state queue;
%% Returns :
%%     
%%----------------------------------------------------------------------
start() ->
    {Names, P} = setup(), 
    startExternalProfiling(isExtProfiling()),
    createStateCache(isCaching()),

    startMnesia(isUsingMnesia()),
    HashTable = createHashTable(),

    Others = [OtherNodes || OtherNodes <- dictToList(Names),  OtherNodes =/= self()],
    % wait for others to add to schema
    barrier(Others, lists:zip(Others, 
			       lists:map(fun(X) -> 0*X end,lists:seq(1,length(Others))))),

    IsUsingMnesia = isUsingMnesia(),
    if IsUsingMnesia ->
        DBNodes = nodes(),
        lists:map(fun(X) ->
                      ExtraNodesStatus = mnesia:add_table_copy(schema, X, ram_copies),
                      io:format("~w setting ram schema for ~w status = ~w~n", [node(), X, ExtraNodesStatus])
                  end, DBNodes),
        mnesia:change_table_copy_type (schema, node (), disc_copies),
        mnesia:wait_for_tables([schema], 20000),
        createMnesiaTables(isUsingMnesia()),
        mnesia:wait_for_tables([schema, visited_state, state_queue], 20000);
       true -> ok
    end,

    lists:map(fun(X) -> X ! {ready, self()} end, Others),

    barrier(Others, lists:zip(Others, 
			       lists:map(fun(X) -> 0*X end,lists:seq(1,length(Others))))),

    T0 = now(),      

    sendStates(startstates(),Names),
    NumSent = length(startstates()),
    %HashTable = createHashTable(),

    reach([], null, Names,HashTable,{NumSent,0},[], 0,0), %should remove null param
    
    io:format("PID ~w: waiting for workers to report termination...~n", [self()]),
    %{NumStates, NumHits} = waitForTerm(dictToList(Names), 0),
    {NumStates, NumHits} = waitForTerm(dictToList(Names), 0, 0, 0),
    Dur = timer:now_diff(now(), T0)*1.0e-6,
    NumPurged = purgeRecQ(0),
    deleteStateCache(isCaching()),
    stopMnesia(isUsingMnesia()),
    
    io:format("----------~n"),
    io:format("REPORT:~n"),
    io:format("\tTotal of ~w states visited~n", [NumStates]),
    io:format("\t~w messages purged from the receive queue~n", [NumPurged]),
    io:format("\tExecution time: ~f seconds~n", [Dur]),
    io:format("\tStates visited per second: ~w~n", [trunc(NumStates/Dur)]),
    io:format("\tStates visited per second per thread: ~w~n", [trunc((NumStates/Dur)/P)]),
    IsCaching = isCaching(),
    if IsCaching ->
	    io:format("\tTotal of ~w state-cache hits (average of ~w)~n", 
		      [NumHits, trunc(NumHits/P)]);
       true ->
	    ok
    end,
    IsLB = isLoadBalancing(),
    if IsLB ->
	    io:format("\tLoad balancing enabled~n");
       true ->
	    io:format("\tLoad balancing disabled~n")
    end,
    io:format("----------~n"),
    done.	


%%----------------------------------------------------------------------
%% Function: autoStart/1
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
    start().

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
		    io:format("PID ~w: worker thread ~w has reported " ++
			      "termination~n", [self(), DiffPID]),%;
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
exitHandler(Pid,Reason) ->
    io:format("~w Received Exit from ~w w/ Reason ~w~n",[self(), Pid,Reason]),
    if Reason =/= normal ->
	    case net_kernel:connect(node(Pid)) of 
		true -> ok;
		_Other  -> 
		    io:format("~n Exiting immediately...~n",[]),
		    halt()
	    end;
       true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: sendStates/2
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%		
%% Args    : First is the state we're currently sending
%%		Rest are the rest of the states to send
%%		Names is a list of PIDs
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendStates(States, Names) -> 
    StateCaching = isCaching(),
    if StateCaching  ->
	    sendStates(caching,States, Names, 0);
       true ->
	    sendStates(nocaching, States, Names, 0)
    end.
   

%%----------------------------------------------------------------------
%% Function: sendStates/4 (State Caching)
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
sendStates(caching, [], _Names, NumSent) ->
    NumSent;

sendStates(caching, [First | Rest], Names, NumSent) ->
    Owner = dict:fetch(1+erlang:phash2(First,dict:size(Names)), Names),
    CacheIndex = erlang:phash2(First, ?CACHE_SIZE)+1, % range is [1,2048]
    CacheLookup = stateCacheLookup(CacheIndex),
    CompactedState = hashState2Int(First),
    WasSent = if Owner == self() -> % my state - send, do not cache
		      Owner ! {compressState(First), state},
		      1;
		 length(CacheLookup) > 0, element(2,hd(CacheLookup)) == CompactedState -> %First -> 
			% not my state, in cache - do not send
		      stateCacheInsert(?CACHE_HIT_INDEX, getHitCount()+1),
		      0;
		 true -> % not my state, not in cache - send and cache
		      stateCacheInsert(CacheIndex, hashState2Int(First)),
		      Owner ! {compressState(First), state},
		      1
	      end,
    sendStates(caching, Rest, Names, NumSent + WasSent);


%%----------------------------------------------------------------------
%% Function: sendStates/4 (NO State Caching)
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%              
%% Args    : First is the state we're currently sending
%%           Rest are the rest of the states to send
%%           Names is a list of PIDs
%%           NumSent is the number of states sent    
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendStates(nocaching, [], _Names, NumSent) ->
    NumSent;

sendStates(nocaching, [First | Rest], Names, NumSent) ->
    Owner = dict:fetch(1+erlang:phash2(First,dict:size(Names)), Names),
    Owner ! {compressState(First), state},
    sendStates(nocaching, Rest, Names, NumSent + 1).

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
%% Function: initThreads/5
%% Purpose : Spawns worker threads. Passes the command-line input to each thread.
%%		Sends the list of all PIDs to each thread once they've all been spawned.
%% Args    : Names is a list of PIDs of threads spawned so far.
%%	     NumThreads is the number of threads left to spawn.
%%	     Data is the command-line input.
%%           HostList is the list of hosts read from file 'hosts'
%%           NHost is the number of hosts 
%% Returns :
%%     
%%----------------------------------------------------------------------
initThreads(Names, 1, _Data, _HostList, _NHost) ->	
    NamesList = [self() | Names],
    NamesDict = dict:from_list(lists:zip(lists:seq(1,length(NamesList)), 
					 NamesList)),
    NamesDict;

% Data is just End right now
initThreads(Names, NumThreads, Data, HostList, NHost) ->
    ID = spawn_link(mynode(NumThreads, HostList, NHost),?MODULE,startWorker,[Data]),
   io:format("Starting worker thread on ~w with PID ~w~n", 
	      [mynode(NumThreads, HostList, NHost), ID]),
    FullNames = initThreads([ID | Names], NumThreads-1, Data, HostList, NHost),
    ID ! {FullNames, names},
    FullNames. % send each worker the PID list

%%----------------------------------------------------------------------
%% Function: startWorker/1
%% Purpose : Initializes a worker thread by receiving the list of PIDs and 
%%		calling reach/4.
%% Args    : Trans is the list of transitions
%%	     End is the state we're looking for
%% Returns : ok
%%     
%%----------------------------------------------------------------------
startWorker(End) ->
    receive
        {Names, names} -> do_nothing % dummy RHS
    end,
    {module, _} = code:load_file(ce_db),
    startExternalProfiling(isExtProfiling()),
    createStateCache(isCaching()),
    startMnesia(isUsingMnesia()),

    % tell root to add me to schema
    rootPID(Names) ! {ready, self()},

    receive
        {ready, _} -> ok
    end,
    HashTable = createHashTable(),

    IsUsingMnesia = isUsingMnesia(),
    if IsUsingMnesia ->
        ok = ce_db:connect(node(rootPID(Names)), [], [visited_state, state_queue]),
        mnesia:wait_for_tables([schema, visited_state, state_queue], 20000);
       true -> ok
    end,

    % synchronizes w/ the root
    rootPID(Names) ! {ready, self()},

    reach([], End, Names, HashTable, {0,0},[],0,0),

    io:format("PID ~w: Worker is done~n", [self()]),
    
    deleteStateCache(isCaching()),
    stopMnesia(isUsingMnesia()),
    ok.

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

		ThisNumSent = sendStates(NewStates, Names),
	%	io:format("An out-degree of::~w~n", [ThisNumSent]),
		%ThisNumSent = 0,

	    EndFound = stateMatch(CurState,End),
	    if EndFound ->
		    io:format("=== End state ~w found by PID ~w ===~n", [End,self()]),
		    rootPID(Names) ! end_found;
	       true -> do_nothing
	    end,

            % remove the state from the Mnesia state queue
            delElemFromStateQueue(isUsingMnesia(), FirstState, state_queue),

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
    % if mnesia check if anything in state queue, otherwise do rest of function
    case firstOfStateQueue(isUsingMnesia(), state_queue) of
        ok ->
            NewNumSent = NumSent, % + sendStates(NewStates,Names),
            TableSize = Count,
            Ret = checkMessageQ(true, TableSize, Names, {NewNumSent, NumRecd}, 
							HashTable, [],0, {[],0}),
            if Ret == done ->
	        done;
               true ->
	        {NewQ, NewNumRecd, NumStates} = Ret,
	        reach(NewQ, End, Names, HashTable, {NewNumSent, NewNumRecd},[], Count, NumStates)
            end;
        State -> reach([State], End, Names, HashTable, {NumSent, NumRecd}, [], Count, 1)
    end.


sendQSize(_Names, 0, _QSize, _StateQ, _NumMess) -> done;

sendQSize(Names, Index, QSize, StateQ, {NumSent, NumRecd}) ->
	Owner = dict:fetch(Index, Names),
	if Owner /= self() ->
	%	io:format("PID ~w: Reporting a QSize of ~w~n",[self(),NewQSize]),
		Owner ! {QSize, self(), myQSize},
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
		      " |MemSys|=~.2f MB, |MemProc|=~.2f MB, |InQ|=~w, |StateQ|=~w, Time=~w->~w~n", 
		      [Count, NumSent, NumRecd,
		       erlang:memory(system)/1048576, 
		       erlang:memory(processes)/1048576,  	
		       element(2,process_info(self(),message_queue_len)), 
				QLen,
				element(2,now())+element(3,now())*1.0e-6,
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
checkMessageQ(IsTimeout, BigListSize, Names, {NumSent, NumRecd}, HashTable, NewStates,NumStates, {CurQ, CurQLen}) ->
    IsRoot = rootPID(Names) == self(),
    Timeout = if IsTimeout-> if IsRoot -> timeoutTime(); true -> infinity end;
				 true -> 0 end,
    
	receive
	{State, state} ->
	    case isMemberHashTable(State,HashTable) of 
		true ->
		    checkMessageQ(false,BigListSize,Names,{NumSent, NumRecd+1},HashTable,
				  NewStates, NumStates,{CurQ, CurQLen});
		false ->
		    addElemToHashTable(State, HashTable),
                    addElemToStateQueue(isUsingMnesia(), State, state_queue, 0),
		    checkMessageQ(false,BigListSize,Names,{NumSent, NumRecd+1},HashTable,
				  [State|NewStates], NumStates+1,{CurQ, CurQLen})
	    end;

	{State, extraState} ->
			checkMessageQ(false,BigListSize,Names,{NumSent, NumRecd},HashTable,
				  [State|NewStates], NumStates+1,{CurQ,CurQLen});

	{OtherSize, OtherPID, myQSize} ->
		LB = OtherSize + balanceTolerence(),
		{NewQ, NewQLen} = if CurQLen > LB ->
			io:format("PID ~w: My Q: ~w, Other Q: ~w, sending ~w extra states to PID ~w~n", 
						[self(),CurQLen,OtherSize, 
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
		    exitHandler(Pid,Reason);

		resume ->
		    checkMessageQ(true, BigListSize, Names, {NumSent, NumRecd},
				  HashTable, NewStates, NumStates,{CurQ,CurQLen});
		die ->
		    terminateMe(BigListSize, rootPID(Names))
	    end;

	die -> 
	    terminateMe(BigListSize, rootPID(Names));

	{'EXIT', Pid, Reason } ->
	    exitHandler(Pid,Reason);

	end_found -> 
	    terminateAll(tl(dictToList(Names))),
	    terminateMe(BigListSize, rootPID(Names))

    after Timeout -> % wait for timeoutTime() ms if root
		if Timeout == 0 ->  % non-blocking case, return 
				{NewStates ++ CurQ, NumRecd, CurQLen+NumStates};
		   true -> % otherwise, root polls for termination
		    io:format("PID ~w: Root has timed out, polling workers now...~n", [self()]),
		    CommAcc = pollWorkers(dictToList(Names), {NumSent, NumRecd}),
			CheckSum = element(1,CommAcc) - element(2,CommAcc),
			if CheckSum == 0 ->	% time to die
				io:format("=== No End states were found ===~n"),
				terminateAll(tl(dictToList(Names))),
				terminateMe(BigListSize, rootPID(Names));
				true ->	% resume other processes and wait again for new states or timeout
					io:format("PID ~w: unusual, checksum is ~w, will wait " ++ 
							  "again for timeout...~n", [self(),CheckSum]),
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

pollWorkers([ThisPID | Rest], {RootSent, RootRecd}) when ThisPID == self() ->
    {S, R} = pollWorkers(Rest, {RootSent, RootRecd}),
    io:format("PID ~w: root CommAcc is {~w,~w}~n", [self(),RootSent,RootRecd]),
    {S+RootSent, R+RootRecd};

pollWorkers([ThisPID | Rest], {RootSent, RootRecd}) ->
    io:format("PID ~w: sending pause signal to PID ~w~n", [self(),ThisPID]),
    ThisPID ! pause,
    {S, R} = pollWorkers(Rest, {RootSent, RootRecd}),
    receive
	{'EXIT', Pid, Reason } ->
	    exitHandler(Pid,Reason);

	{ThisSent, ThisRecd, poll} ->
	    io:format("PID ~w: Got a worker CommAcc of {~w,~w}~n", 
		      [self(),ThisSent,ThisRecd]),
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
	    io:format("PID ~w: was told to die; visited ~w unique states; ~w " ++ 
		      "state-cache hits~n", [self(), NumStatesVisited, getHitCount()]),
	    RootPID ! {self(), {NumStatesVisited, getHitCount()}, done};
       true ->
	    io:format("PID ~w: was told to die; visited ~w unique states; ~n", 
		      [self(), NumStatesVisited]),
	    RootPID ! {self(), {NumStatesVisited, 0}, done}
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
        io:format("checkAck: ~w halting for now",[self()]),
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

%%----------------------------------------------------------------------
%% Function: startMnesia/1
%% Purpose : Starts the Mnesia DBMS
%% Args    : boolean
%% Returns : ok or error
%%     
%%----------------------------------------------------------------------
startMnesia(IsUsingMnesia) ->
    io:format("~w in startMnesia with parameter ~w~n", [node(), IsUsingMnesia]),  %% comment out when done
    case IsUsingMnesia of 
	true ->
            %mnesia:info(),
            %mnesia:system_info(all),
	    MnesiaStatus = mnesia:start(),
            %mnesia:info(),
            %mnesia:system_info(all),
            io:format("~w started mnesia status = ~w~n", [node(), MnesiaStatus]),
	    case MnesiaStatus of 
	        {error, _} -> error;
	        _Else -> ok
	    end;
	false->
	    ok
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
%% Function: createMnesiaTables/1
%% Purpose : Create schema for root, start Mnesia, create tables
%% Args    : boolean
%% Returns : ok
%%     
%%----------------------------------------------------------------------
createMnesiaTables(IsUsingMnesia) ->
    case IsUsingMnesia of 
	true ->
            %SchemaCreationStatus = mnesia:create_schema([node()]),
            %io:format("root created schema exit status ~w~n", [SchemaCreationStatus]),
            %if ok =/= SchemaCreationStatus -> halt();
            %   true -> ok
            %end,
            %MnesiaStartupStatus = startMnesia(isUsingMnesia()),
            %if MnesiaStartupStatus == error ->
            %    io:format("start: Error Mnesia did not start on ~w~n", [node()]),
            %    halt();
            %   true -> ok
            %end,
            CreateHTStatus = mnesia:create_table(visited_state, [{disc_copies, [node()]}, {local_content, true}, {attributes, record_info(fields, visited_state)}]),
            io:format("~w creating hash table ~w status ~w~n", [node(), visited_state, CreateHTStatus]),
            % if I feel like it, someday I'll put an index on order for the state queue
            CreateQStatus = mnesia:create_table(state_queue, [{disc_copies, [node()]}, {local_content, true}, {attributes, record_info(fields, state_queue)}]),
            io:format("~w creating state queue table ~w status ~w~n", [node(), state_queue, CreateQStatus]),
	    ok;
	false->
	    ok
    end.

%%----------------------------------------------------------------------
%% Function: attachToMnesiaTables/1
%% Purpose : Have slaves attach to root's Mnesia schema and tables
%% Args    : boolean
%% Returns : ok
%%     
%%----------------------------------------------------------------------
attachToMnesiaTables(IsUsingMnesia) ->
    case IsUsingMnesia of 
	true ->
            MnesiaStartupStatus = startMnesia(isUsingMnesia()),
            if MnesiaStartupStatus == error ->
                io:format("start: Error Mnesia did not start on ~w~n", [node()]),
                halt();
               true -> ok
            end,
            % "barrier": worker must be up before root creates mnesia schema
            %io:format("~w sending root schema barrier1 ready~n", [node()]),
            %rootPID(Names) ! {ready, self()},
            % need to wait for schema to be created before starting mnesia
            % receive message from root
            %receive 
            %    {ready, _Root} -> ok
            %end,
            %io:format("~w received schema barrier2 ready from root~n", [node()]),
            mnesia:change_table_copy_type(schema, node(), disc_copies),
            mnesia:add_table_copy(visited_state, node(), disc_copies),
            ok;
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
        case mnesia:transaction(fun() -> mnesia:write(StateQueue, Record, write) end) of
            {atomic, _} -> ok;
            Else -> io:format("~w addElemToStateQueue(~w, ~w, ~w, ~w) returned ~w~n", [node(), IsUsingMnesia, Element, StateQueue, Order, Else]),
                Else
        end;
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
        case mnesia:transaction(fun() -> mnesia:delete(StateQueue, Element, write) end) of
            {atomic, _} -> ok;
            Else -> io:format("~w delElemFromStateQueue(~w, ~w, ~w) returned ~w~n", [node(), IsUsingMnesia, Element, StateQueue, Else]),
                Else
        end;
       true -> ok
    end.

%%----------------------------------------------------------------------
%% Function: firstOfStateQueue/2
%% Purpose : check if anything in the state queue, if so, return it
%% Args    : boolean, atom table name
%% Returns : State or ok
%%     
%%----------------------------------------------------------------------
firstOfStateQueue(IsUsingMnesia, StateQueue) ->
    if IsUsingMnesia ->
        case mnesia:transaction(fun() -> mnesia:first(StateQueue) end) of
            {atomic, '$end_of_table'} -> ok;
            {atomic, State} -> State;
            Else -> io:format("~w firstOfStateQueue(~w, ~w) returned ~w~n", [node(), IsUsingMnesia, StateQueue, Else]),
                ok
        end;
       true -> ok
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
