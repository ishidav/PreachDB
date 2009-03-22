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
-module(preach_term).
-compile(inline). %inlines all functions of 24 lines or less
-export([start/3,startWorker/1]).

timeoutTime() -> 3000.

rootPID(Names) -> hd(Names).

mynode(Index) -> brad@marmot.cs.ubc.ca;
mynode(Index) -> 
	lists:nth(1+((Index-1) rem 2), [
			brad@marmot.cs.ubc.ca,
			brad@okanagan.cs.ubc.ca
			%brad@ayeaye.cs.ubc.ca,	
			%brad@avahi.cs.ubc.ca
			]).
% other machines: 
% brad@fossa.cs.ubc.ca, brad@indri.cs.ubc.ca

waitForTerm([], TotalStates) ->	
	TotalStates;
waitForTerm([FirstPID | RestPID], TotalStates) ->
	receive
		{FirstPID, NumStates, done} -> 
		io:format("PID ~w: worker thread ~w has reported termination~n", [self(), FirstPID])
	end,
	waitForTerm(RestPID, TotalStates + NumStates).

purgeRecQ(Count) ->
	receive
		_Garbage ->
			purgeRecQ(Count+1)
	after
		0 ->
			Count
	end.

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
	reach([], End, Names,dict:new(),{NumSent,0}), % if this returns, End was not found

	io:format("PID ~w: waiting for workers to report termination...~n", [self()]),
	NumStates = waitForTerm(Names, 0),
  	Dur = timer:now_diff(now(), T0)*1.0e-6,
	NumMessages = purgeRecQ(0),

	io:format("----------~n"),
	io:format("REPORT:~n"),
	io:format("\tTotal of ~w states visited~n", [NumStates]),
	io:format("\t~w messages purged from the receive queue~n", [NumMessages]),
	io:format("\tExecution time: ~f seconds~n", [Dur]),
	io:format("\tStates visited per second: ~w~n", [trunc(NumStates/Dur)]),
	io:format("----------~n"),
	done.	

compressState(State) ->
	stress:stateToInt(State).
%	stress:stateToBits(State).
%	State.

decompressState(CompressedState) ->
		stress:intToState(CompressedState).
%		stress:bitsToState(CompressedState).
%		CompressedState.

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
	Owner = lists:nth(stateHash(First,length(Names)), Names),
	Owner ! {compressState(First), state},
	sendStates(Rest, Names).

%%----------------------------------------------------------------------
%% Function: stateHash/2
%% Purpose : Maps states to owning threads. 
%% 
%% Args    : State is the state find the owner of
%%			 (assumes states are tuples)
%%			 
%% Returns : Owning thread in the range [1..P]
%%     
%%----------------------------------------------------------------------
stateHash(State, P) ->
% a silly has function
%	Hash = lists:sum(tuple_to_list(First)),
% a bit less silly
%	Hash = 1*element(1,State)+2*element(2,State)+3*element(3,State)+4*element(4,State)
%		+5*element(5,State)+6*element(6,State)+7*element(7,State),
% probably sufficient
	Hash = erlang:phash2(State, P),
	1+(Hash rem P).


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
	[self() | Names];
% Data is just End right now
initThreads(Names, NumThreads, Data) ->
	% ID = spawn(preach, startWorker, [Data]),
	ID = spawn(mynode(NumThreads),preach_term,startWorker,[Data]),
	io:format("Starting worker thread on ~w with PID ~w~n", [mynode(NumThreads), ID]),
	FullNames = initThreads([ID | Names], NumThreads-1, Data),
	ID ! FullNames. % send each worker the PID list

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
        Names -> do_nothing % dummy RHS
    end,
	reach([], End, Names,dict:new(),{0,0}),
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
	IsOldState = dict:is_key(FirstState, BigList),
	if IsOldState ->
		reach(RestStates, End, Names, BigList, {NumSent, NumRecd});
	true ->
		CurState = decompressState(FirstState),
		NewStates = stress:transition(CurState, start),
		EndFound = stateMatch(CurState,End),

		if EndFound ->
			io:format("=== End state ~w found by PID ~w ===~n", [End,self()]),
			terminateAll(lists:delete(self(),Names)), % terminate all other processes
			terminateMe(dict:size(BigList), rootPID(Names));
		true ->
			sendStates(NewStates, Names),
			NewNumSent = NumSent + length(NewStates),
%			reach(RestStates, End, Names, dict:append(FirstState, true, BigList)) % grow the big list
			reach(RestStates, End, Names, dict:append(FirstState, true, BigList), {NewNumSent, NumRecd}) % grow the big list
		end
	end;

% StateQ is empty, so check for messages. If none are found, we die
reach([], End, Names, BigList, {NumSent, NumRecd}) ->
	Ret = checkMessageQ(timeout, dict:size(BigList), Names, {NumSent, NumRecd}, 0),
	if Ret == done ->
			done;
	   true ->
		{NewQ, NewNumRecd} = Ret,
		NewQ2 = lists:usort(NewQ), % remove any duplicate states
		reach(NewQ2, End, Names, BigList, {NumSent, NewNumRecd})
	end.

pollWorkers([], _) ->
	{0,0};

% deadlock bug here - what if and end state is found by a worker 
% while the root is waiting for a poll message?
pollWorkers([ThisPID | Rest], {RootSent, RootRecd}) ->
	if ThisPID == self() ->
		io:format("PID ~w: polling myself~n", [self()]),
		no_need_to_send;
	true ->
		io:format("PID ~w: sending pause signal to PID ~w~n", [self(),ThisPID]),
		ThisPID ! pause
	end,

	{S, R} = pollWorkers(Rest, {RootSent, RootRecd}),

	if ThisPID == self() ->
		io:format("PID ~w: root CommAcc is {~w,~w}~n", [self(),RootSent,RootRecd]),
		{S+RootSent, R+RootRecd};
	true ->
		receive
		{ThisSent, ThisRecd, poll} ->
			io:format("PID ~w: Got a worker CommAcc of {~w,~w}~n", [self(),ThisSent,ThisRecd]),
			{S+ThisSent, R+ThisRecd}
		end
	end.

resumeWorkers([]) ->
	ok;

resumeWorkers([ThisPID | Rest]) ->
	if ThisPID == self() ->
		no_need_to_send;
	true ->
		ThisPID ! resume
	end,
	resumeWorkers(Rest).

%%----------------------------------------------------------------------
%% Function: checkMessageQ/4
%% Purpose : Polls for incoming messages
%%
%% Args    : timeout is atomic indicator that we are polling;
%%		notimeout performs a nonblocking receive
%%		BigList is used only to report the size upon termination
%%		Names is the list of PIDs
%%	     {NumSent, NumRecd} is the running total of the number of states
%%	     sent and received, respectively
%% Returns : EITHER List of received states in the form of
%%		{NewStateQ, NewNumRecd} where NewNumRecd is
%%		equal to NumRecd + length(NewStateQ)
%%		OR the atom 'done' to indicate we are finished visiting states
%%     
%%----------------------------------------------------------------------
checkMessageQ(timeout, BigListSize, Names, {NumSent, NumRecd}, _) when self() == hd(Names) ->
%	io:format("PID ~w (root): checking my message queue; ~w messages received so far~n", [self(), NumRecd]), % for debugging
	receive
	{State, state} ->
%		io:format("PID ~w received state ~w~n", [self(), State]), % for debugging
		case checkMessageQ(notimeout,BigListSize,Names,{NumSent, NumRecd+1},0) of
			{NewStateQ,NewNumRecd} -> {[State | NewStateQ], NewNumRecd};
			done -> done
		end;
	die -> 
		terminateMe(BigListSize, rootPID(Names))
	after 
		timeoutTime() -> % wait for timeoutTime() ms   
		io:format("PID ~w: Root has timed out, polling workers now...~n", [self()]),
		CommAcc = pollWorkers(Names, {NumSent, NumRecd}),
		CheckSum = element(1,CommAcc) - element(2,CommAcc),
		if CheckSum == 0 ->
			% time to die
			io:format("=== No End states were found ===~n"),
			terminateAll(tl(Names)),
			terminateMe(BigListSize, rootPID(Names));
		true ->
			% resume other processes and wait again for new states or timeout
			io:format("PID ~w: unusual, checksum is ~w, will wait again for timeout...~n", [self(),CheckSum]),
			resumeWorkers(Names),
			checkMessageQ(timeout,BigListSize,Names,{NumSent,NumRecd},0)
		end
	end;

checkMessageQ(timeout, BigListSize, Names, {NumSent, NumRecd}, _) ->
%	io:format("PID ~w (worker): checking my message queue; ~w messages received so far~n", [self(), NumRecd]), % for debugging
	receive
	{State, state} ->
%		io:format("PID ~w received state ~w~n", [self(), State]), % for debugging
		case checkMessageQ(notimeout,BigListSize,Names,{NumSent, NumRecd+1},0) of 
		{NewStateQ, NewNumRecd} -> {[State | NewStateQ], NewNumRecd};
		done -> done
		end;
	pause -> % report # messages sent/received
		rootPID(Names) ! {NumSent, NumRecd, poll},
		receive
		resume ->
			checkMessageQ(timeout, BigListSize, Names, {NumSent, NumRecd},0);
		die ->
			terminateMe(BigListSize, rootPID(Names))
		end;
	die -> 
		terminateMe(BigListSize, rootPID(Names))
	end;

%checkMessageQ(notimeout, BigListSize, Names, {NumSent, NumRecd}, Depth) when Depth == 1000->
%	{[], NumRecd};

% Get all queued messages without waiting
checkMessageQ(notimeout, BigListSize, Names, {NumSent, NumRecd}, Depth) ->
	receive
	% could check for pause messages here
        {State, state} ->
%		io:format("PID ~w received state ~w~n", [self(), State]), % for debugging
		case checkMessageQ(notimeout,BigListSize,Names,{NumSent, NumRecd+1}, Depth+1) of
		{NewStateQ,NewNumRecd} -> {[State | NewStateQ], NewNumRecd};
		done -> done
		end;
	die -> 
		terminateMe(BigListSize, rootPID(Names))
	after 
		1 -> % wait for 0 ms   
			{[], NumRecd} 
	end.

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
terminateAll([]) ->	
	done;
terminateAll([FirstPID | RestPID]) ->
	FirstPID ! die,
	terminateAll(RestPID).

%% the following functions to be removed. For "simple" testing only.
%% currently, transition, guard and action should all be implemented
%% in gospel. stateMatch should be implemented elsewhere, but we're
%% not sure where it should go at the moment.

%% Default transition unless we're MC-ing someting specific
transition(State, start) ->
	T = transition(2, State), % 2 is the number of guarded commands
	[X || X <- T, X /= null];
transition(0, _) ->
	[];
transition(Index, State) ->
	[guard(Index, State) | transition(Index-1, State)].
	
%% Default guard
guard(Index, State) ->
	case Index of
		1 -> 	if 
				State == {0,0} -> action(Index, State);
				true -> null
			end;
		2 ->	if 
				((State == {1,0}) or (State == {0,1})) -> action(Index, State);
				true -> null
			end
	end.

% action may be a function of State, but not for the simple example
action(Index, State) ->
	case Index of
		1 -> 	{0,1};
		2 ->	{0,0}
	end.

% may need to allow End to be a list of states, possibly
% with don't care variables
stateMatch(State, End) ->
	Pairs = lists:zip(tuple_to_list(State), tuple_to_list(End)),
	Eq = fun({X,Y}) -> (X == Y) or (Y == dc) end,
	lists:all(Eq, Pairs).


%--------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: preach.erl,v $
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
