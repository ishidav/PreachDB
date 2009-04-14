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
-module(preach).
% -compile(inline). %inlines all functions of 24 lines or less
-export([start/3,startWorker/1]).

%% configuration-type functions
timeoutTime() -> 3000.

mynode(_Index) -> brad@marmot.cs.ubc.ca.
%mynode(Index) -> 
%	lists:nth(1+((Index-1) rem 2), [
%			brad@marmot.cs.ubc.ca,
%			brad@ayeaye.cs.ubc.ca
%			brad@marmot.cs.ubc.ca,	
%			brad@avahi.cs.ubc.ca
%			]).
% other machines: 
% brad@fossa.cs.ubc.ca, brad@indri.cs.ubc.ca

compressState(State) ->
	stress:stateToInt(State).
%	stress:stateToBits(State).
%	State.

decompressState(CompressedState) ->
		stress:intToState(CompressedState).
%		stress:bitsToState(CompressedState).
%		CompressedState.

%% end of configuration-type functions

rootPID(Names) -> dict:fetch(1,Names). % hd(Names).

%%----------------------------------------------------------------------
%% Function: start/3
%% Purpose : A timing wrapper for the parallel version of 
%%				our model checker.
%% Args    : P is the number of Erlang threads to use;
%%			Start is a list of states to initialize the state queue;
%%			End is the state we're looking for; may contain don't cares
%% Returns :
%%     
%%----------------------------------------------------------------------
start(Start,End,P) ->
 	T0 = now(),
	Names = initThreads([], P,End),
	
	sendStates(Start, Names),
	NumSent = length(Start),
	TableID = ets:new(big_list, [set, private]),

	reach([], End, Names,TableID,{NumSent,0}),
	ets:delete(TableID),

	io:format("PID ~w: waiting for workers to report termination...~n", [self()]),
	NumStates = waitForTerm(dictToList(Names), 0),
  	Dur = timer:now_diff(now(), T0)*1.0e-6,
	NumPurged = purgeRecQ(0),

	io:format("----------~n"),
	io:format("REPORT:~n"),
	io:format("\tTotal of ~w states visited~n", [NumStates]),
	io:format("\t~w messages purged from the receive queue~n", [NumPurged]),
	io:format("\tExecution time: ~f seconds~n", [Dur]),
	io:format("\tStates visited per second: ~w~n", [trunc(NumStates/Dur)]),
	io:format("\tStates visited per second per thread: ~w~n", [trunc((NumStates/Dur)/P)]),
	io:format("----------~n"),
	done.	


waitForTerm(PIDs, _) ->
	F = fun(_PID, Total) -> 	receive {DiffPID, NumStates, done} -> 
				io:format("PID ~w: worker thread ~w has reported termination~n", [self(), DiffPID])
				end,
				Total + NumStates end,
	lists:foldl(F, 0, PIDs).

purgeRecQ(Count) ->
	receive
		_Garbage ->
			purgeRecQ(Count+1)
	after
		100 ->
			Count
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
sendStates([], _Names) ->
	ok;

sendStates([First | Rest], Names) ->
%	Owner = lists:nth(1+erlang:phash2(First,length(Names)),Names),
	Owner = dict:fetch(1+erlang:phash2(First,dict:size(Names)), Names),
	Owner ! {compressState(First), state},
	sendStates(Rest, Names).


%%----------------------------------------------------------------------
%% Function: initThreads/3
%% Purpose : Spawns worker threads. Passes the command-line input to each thread.
%%		Sends the list of all PIDs to each thread once they've all been spawned.
%% Args    : Names is a list of PIDs of threads spawned so far.
%%		NumThreads is the number of threads left to spawn.
%%		Data is the command-line input.
%% Returns :
%%     
%%----------------------------------------------------------------------
initThreads(Names, 1, _Data) ->	
	NamesList = [self() | Names],
	NamesDict = dict:from_list(lists:zip(lists:seq(1,length(NamesList)), NamesList)),
	NamesDict;

% Data is just End right now
initThreads(Names, NumThreads, Data) ->
	ID = spawn(mynode(NumThreads),preach,startWorker,[Data]),
	io:format("Starting worker thread on ~w with PID ~w~n", [mynode(NumThreads), ID]),
	FullNames = initThreads([ID | Names], NumThreads-1, Data),
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
	reach([], End, Names,ets:new(big_list, [set,private]),{0,0}),
	io:format("PID ~w: Worker is done~n", [self()]),
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
reach([FirstState | RestStates], End, Names, BigList, {NumSent, NumRecd}) ->
	IsOldState = ets:member(BigList, FirstState), %dict:is_key(FirstState, BigList),
	if IsOldState ->
		reach(RestStates, End, Names, BigList, {NumSent, NumRecd});
	true ->
		CurState = decompressState(FirstState),
		NewStates = stress:transition(CurState, start),
		EndFound = stress:stateMatch(CurState,End),

		if EndFound ->
			io:format("=== End state ~w found by PID ~w ===~n", [End,self()]),
			rootPID(Names) ! end_found;
		   true -> do_nothing
		end,
		sendStates(NewStates, Names),
		NewNumSent = NumSent + length(NewStates),
		ets:insert(BigList, {FirstState}),
		reach(RestStates, End, Names, BigList, {NewNumSent, NumRecd}) % grow the big list
%		reach(RestStates, End, Names, dict:append(FirstState, true, BigList), {NewNumSent, NumRecd}) % grow the big list
	end;

% StateQ is empty, so check for messages. If none are found, we die
reach([], End, Names, BigList, {NumSent, NumRecd}) ->
	TableSize = element(2,lists:nth(4,ets:info(BigList))),
	Ret = checkMessageQ(timeout, TableSize, Names, {NumSent, NumRecd}, 0, []),
	if Ret == done ->
			done;
	   true ->
		{NewQ, NewNumRecd} = Ret,

		%reach(lists:usort(lists:filter(fun(X) -> ets:member(BigList,X)==false end, NewQ)),End, Names, BigList, {NumSent, NewNumRecd}) 
		%reach([X || X <- NewQ, ets:member(BigList,X) == false], End, Names, BigList, {NumSent, NewNumRecd}) 
		reach(NewQ, End, Names, BigList, {NumSent, NewNumRecd})
	end.


dictToList(Names) -> element(2,lists:unzip(lists:sort(dict:to_list(Names)))).

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
%	io:format("PID ~w: checking my message queue; ~w messages received so far~n", [self(), NumRecd]), % for debugging
	IsRoot = rootPID(Names) == self(),
	Timeout = if IsRoot -> timeoutTime(); true -> infinity end,
	receive
	{State, state} ->
		checkMessageQ(notimeout,BigListSize,Names,{NumSent, NumRecd+1},0, [State|NewStates]);
	pause -> % report # messages sent/received
		rootPID(Names) ! {NumSent, NumRecd, poll},
		receive
		resume ->
			checkMessageQ(timeout, BigListSize, Names, {NumSent, NumRecd},0, NewStates);
		die ->
			terminateMe(BigListSize, rootPID(Names))
		end;
	die -> 
		terminateMe(BigListSize, rootPID(Names));
	end_found -> 
		terminateAll(tl(dictToList(Names))),
		terminateMe(BigListSize, rootPID(Names))
	after Timeout -> % wait for timeoutTime() ms if root 
		io:format("PID ~w: Root has timed out, polling workers now...~n", [self()]),
		CommAcc = pollWorkers(dictToList(Names), {NumSent, NumRecd}),
		CheckSum = element(1,CommAcc) - element(2,CommAcc),
		if CheckSum == 0 ->	% time to die
			io:format("=== No End states were found ===~n"),
			terminateAll(tl(dictToList(Names))),
			terminateMe(BigListSize, rootPID(Names));
		true ->	% resume other processes and wait again for new states or timeout
			io:format("PID ~w: unusual, checksum is ~w, will wait again for timeout...~n", [self(),CheckSum]),
			resumeWorkers(tl(dictToList(Names))),
			checkMessageQ(timeout,BigListSize,Names,{NumSent,NumRecd},0, NewStates)
		end
	end;

%checkMessageQ(notimeout, BigListSize, Names, {NumSent, NumRecd}, Depth, NewStates) when Depth == 1000->
%	{NewStates, NumRecd};

% Get all queued messages without waiting
checkMessageQ(notimeout, BigListSize, Names, {NumSent, NumRecd}, Depth, NewStates) ->
	receive
	% could check for pause messages here
	{State, state} ->
		checkMessageQ(notimeout,BigListSize,Names,{NumSent, NumRecd+1},Depth+1, [State|NewStates]);
	die -> 
		terminateMe(BigListSize, rootPID(Names))
	after 
		0 -> % wait for 0 ms  
			{NewStates, NumRecd} 
	end.

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
		io:format("PID ~w: Got a worker CommAcc of {~w,~w}~n", [self(),ThisSent,ThisRecd]),
		{S+ThisSent, R+ThisRecd}
	end.

resumeWorkers(PIDs) ->
	lists:map(fun(PID) -> PID ! resume end, PIDs),
	ok.

terminateMe(NumStatesVisited, RootPID) ->
	io:format("PID ~w: was told to die; visited ~w unique states~n", [self(), NumStatesVisited]),
	RootPID ! {self(), NumStatesVisited, done},
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
