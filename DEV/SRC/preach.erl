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
%
% No module/exports defn since they should be included in the bottom of the 
% gospel code
%

%% configuration-type functions
timeoutTime() -> 3000.


%%----------------------------------------------------------------------
%% Function: createStateCache/1, deleteStateCache/1
%% Purpose : Routines to abstract away how the cache is implemented, eg,
%%           erlang lists, ets or dict, etc...
%%               
%% Args    : boolean resulting from calling isCaching() 
%%
%% NOTE    : More work needs to abstract away other calls like 
%%           ets:lookup, ets:insert, etc
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
%slaves([], _CWD, _NHosts) ->
slaves(_Hostlist, _CWD, 1) -> 
    ok;
slaves([Host|Hosts], CWD, NHosts) ->
    Args0 = "+h 100000 -setcookie " ++ atom_to_list(erlang:get_cookie()) ++
	" -pa " ++ CWD ++ " -pa " ++ CWD ++ "/ebin " ++  "-smp enable",
    
  % Pass cache option to workers 
    IsCaching = isCaching(),
    if IsCaching -> 
	    Args = Args0 ++ " -statecaching"; 
       true -> 
	    Args = Args0 
    end,
    
    NodeName = string:concat("pruser", integer_to_list(NHosts)),
    case slave:start_link(Host, NodeName, Args) of
	{ok, Node} ->
	    io:format("Erlang node started = [~p]~n", [Node]),
	    slaves(Hosts, CWD, NHosts - 1);
	{error,timeout} ->
	    io:format("Could not connect to host ~w...Exiting~n",[Host]),
	    halt();
	{error,Reason} ->
	    io:format("Could not start workers: Reason= ~w...Exiting~n",[Reason]),
	    halt()
    end.


%%----------------------------------------------------------------------
%% Function: compressState/1 decompressState/1 
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

setup() ->
    LocalMode = isLocalMode(),
    if LocalMode  ->
	    Names = initThreads([], 1, null, [], 0), %% should remove null param
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
		    slaves(lists:reverse(tl(HostList)), CWD, Nhosts),
		    Names = initThreads([], Nhosts, null,HostList, Nhosts)%, %%% should remove null param
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
    T0 = now(),
    {Names, P} = setup(), 
    createStateCache(isCaching()),

    sendStates(startstates(),Names),
    NumSent = length(startstates()),
    ESBF = bloom:bloom(?BLOOM_N_ENTRIES,?BLOOM_ERR_PROB), 
    
    reach([], null, Names,ESBF,{NumSent,0},[], 0), %should remove null param
    
    io:format("PID ~w: waiting for workers to report termination...~n", [self()]),
    {NumStates, NumHits} = waitForTerm(dictToList(Names), 0),
    Dur = timer:now_diff(now(), T0)*1.0e-6,
    NumPurged = purgeRecQ(0),
    deleteStateCache(isCaching()),
    
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
    io:format("----------~n"),
    done.	



%%----------------------------------------------------------------------
%% Function: autoStart/1
%% Purpose : A timing wrapper for the parallel version of our model checker.
%%           To be used when called from the ptest script
%%           
%% Args    : P is the number of Erlang threads to use;
%%	
%% Returns :
%%     
%%----------------------------------------------------------------------
autoStart() ->
    displayHeader(),
    displayOptions(),
    %process_flag(trap_exit,true),
    start().

%%----------------------------------------------------------------------
%% Function: waitForTerm/2
%% Purpose : 
%% Args    : 
%%	     
%% Returns :
%%     
%%----------------------------------------------------------------------
waitForTerm(PIDs, _) ->
    F = fun(_PID, {TotalStates, TotalHits}) -> 	
          	receive {DiffPID, {NumStates, NumHits}, done} -> 
			io:format("PID ~w: worker thread ~w has reported " ++
				  "termination~n", [self(), DiffPID])
	        end,
		{TotalStates + NumStates, TotalHits + NumHits} 
	end,
    lists:foldl(F, {0,0}, PIDs).

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
	_Garbage ->
	    purgeRecQ(Count+1)
    after
	100 ->
	    Count
    end.

%%----------------------------------------------------------------------
%% Function: getHitCount/0
%% Purpose : Used only when caching sent states. 
%% Args    : 
%%	     
%% Returns :
%%     
%%----------------------------------------------------------------------
getHitCount() -> 
    element(2,hd(ets:lookup(cache, ?CACHE_HIT_INDEX))).

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
    CacheLookup = ets:lookup(cache, CacheIndex),
    WasSent = if Owner == self() -> % my state - send, do not cache
		      Owner ! {compressState(First), state},
		      1;
		 length(CacheLookup) > 0, element(2,hd(CacheLookup)) == First -> 
			% not my state, in cache - do not send
		      ets:insert(cache,[{?CACHE_HIT_INDEX, getHitCount()+1}]),
		      0;
		 true -> % not my state, not in cache - send and cache
		      ets:insert(cache,[{CacheIndex,First}]),    
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
    createStateCache(isCaching()),

    reach([], End, Names,bloom:bloom(?BLOOM_N_ENTRIES,?BLOOM_ERR_PROB),{0,0},[],0),
    io:format("PID ~w: Worker is done~n", [self()]),
    
    deleteStateCache(isCaching()),
    ok.

%%----------------------------------------------------------------------
%% Function: reach/5
%% Purpose : Removes the first state from the list, 
%%		generates new states returned by the call to transition that
%%		are appended to the list of states. Recurses until there
%%		are no further states to process. 
%% Args    : FirstState is the state to remove from the state queue
%%	     RestStates is the remainder of the state queue
%%	     End is the state we seek - may contain don't cares 
%%	     BigList is a set of states that have been visited by this 
%%		thread, which are necessarily also owned by this thread. 
%%		NOTE: Any line involving the BigList probably has poor performance.
%%	     {NumSent, NumRecd} is the running total of the number of states
%%	     sent and received, respectively
%%
%% Returns : done
%%     
%%----------------------------------------------------------------------
reach([FirstState | RestStates], End, Names, BigList, {NumSent, NumRecd}, SendList, Count) ->
    case bloom:member(FirstState,BigList) of 
	true ->
	    reach(RestStates, End, Names, BigList, {NumSent, NumRecd}, SendList, Count);
	false ->
	    %profiling(length(RestStates), length(SendList), NumSent, NumRecd, Count),
	    profiling(0, 0, NumSent, NumRecd, Count),
	    CurState = decompressState(FirstState),
	    NewStates = transition(CurState),
	    EndFound = stateMatch(CurState,End),
	    
	    if EndFound ->
		    io:format("=== End state ~w found by PID ~w ===~n", [End,self()]),
		    rootPID(Names) ! end_found;
	       true -> do_nothing
	    end,
	    reach(RestStates, End, Names, bloom:add(FirstState,BigList), {NumSent, NumRecd}, NewStates ++ SendList,Count+1) 
    end;

% StateQ is empty, so check for messages. If none are found, we die
reach([], End, Names, BigList, {NumSent, NumRecd}, SendList, Count) ->
    NewNumSent = NumSent + sendStates(SendList, Names),
    TableSize = Count, 
    Ret = checkMessageQ(timeout, TableSize, Names, {NewNumSent, NumRecd}, 0, []),
    if Ret == done ->
	    done;
       true ->
	    {NewQ, NewNumRecd} = Ret,
	    reach(NewQ, End, Names, BigList, {NewNumSent, NewNumRecd}, [],Count)
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
%%----------------------------------------------------------------------
profiling(_WQsize, _SendQsize, NumSent, NumRecd, Count) ->
    if (Count rem 10000)  == 0 ->
%	    io:format("VS=~w, |WQ|=~w, |SQ|=~w, NS=~w, NR=~w" ++ 
%		      " |MemSys|=~w, |MemProc|=~w ->~w~n", 
%		      [Count, WQsize, SendQsize, NumSent, NumRecd,
%		       erlang:memory(system), erlang:memory(processes),self()]);
	    io:fwrite("VS=~w,  NS=~w, NR=~w" ++ 
		      " |MemSys|=~.2f MB, |MemProc|=~.2f MB ->~w~n", 
		      [Count, NumSent, NumRecd,
		       erlang:memory(system)/1048576, 
		       erlang:memory(processes)/1048576,self()]);

       true -> ok
    end.


%%----------------------------------------------------------------------
%% Function: checkMessageQ/5-6
%% Purpose : Polls for incoming messages
%%
%% Args    : timeout is atomic indicator that we are polling;
%%		notimeout performs a nonblocking receive
%%		BigList is used only to report the size upon termination
%%		Names is the list of PIDs
%%	     {NumSent, NumRecd} is the running total of the number of states
%%	     sent and received, respectively
%%	     NewStates is a list accumulating the new received states
%%	     Depth is just for debugging and testing purposes
%% Returns : EITHER List of received states in the form of
%%		{NewStateQ, NewNumRecd} where NewNumRecd is
%%		equal to NumRecd + length(NewStateQ)
%%		OR the atom 'done' to indicate we are finished visiting states
%%     
%%----------------------------------------------------------------------
checkMessageQ(timeout, BigListSize, Names, {NumSent, NumRecd}, _, NewStates) ->
    IsRoot = rootPID(Names) == self(),
    Timeout = if IsRoot -> timeoutTime(); true -> infinity end,
    receive
       {'EXIT', Pid, Reason } ->
 	    io:format("~w Received Exit from ~w w/ Reason ~w ~n Exiting immediately...~n",[self(), Pid,Reason]),
 	    case net_kernel:connect(node(Pid)) of 
 		true -> ok;
 		_Other  ->
		    halt()
 	    end;

	{State, state} ->
	    checkMessageQ(notimeout,BigListSize,Names,{NumSent, NumRecd+1},0,
			  [State|NewStates]);
	pause -> % report # messages sent/received
	    rootPID(Names) ! {NumSent, NumRecd, poll},
	    receive
		resume ->
		    checkMessageQ(timeout, BigListSize, Names, {NumSent, NumRecd},
				  0, NewStates);
		die ->
		    terminateMe(BigListSize, rootPID(Names))
	    end;
	die -> 
	    terminateMe(BigListSize, rootPID(Names));
	end_found -> 
	    terminateAll(tl(dictToList(Names))),
	    terminateMe(BigListSize, rootPID(Names))
 
    after Timeout -> % wait for timeoutTime() ms if root 
	    io:format("PID ~w: Root has timed out, polling workers now...~n", 
		      [self()]),
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
		    checkMessageQ(timeout, BigListSize, Names, {NumSent,NumRecd}, 
				  0, NewStates)
	    end
    end;


% Get all queued messages without waiting
checkMessageQ(notimeout, BigListSize, Names, {NumSent, NumRecd}, Depth, NewStates) ->
    receive
        {'EXIT', Pid, Reason } ->
	    io:format("Received Exit from ~w w/ Reason ~w ~n Exiting immediately...~n",[Pid,Reason]),
 	    case net_kernel:connect(node(Pid)) of 
 		true -> ok;
 		_Other  ->
		    halt()
 	    end;
	% could check for pause messages here
	{State, state} ->
	    checkMessageQ(notimeout,BigListSize,Names,{NumSent, NumRecd+1},
			  Depth+1, [State|NewStates]);
	die -> 
	    terminateMe(BigListSize, rootPID(Names))
    after 
		0 -> % wait for 0 ms  
	    {NewStates, NumRecd} 
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

%--------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: preach.erl,v $
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
