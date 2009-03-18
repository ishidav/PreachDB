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

-compile(inline). %inlines all functions of 24 lines or less

-export([start/3,startWorker/1]).

mynode(Index) -> brad@marmot.cs.ubc.ca; %brad@ayeaye.cs.ubc.ca;
mynode(Index) -> 
	lists:nth(1+((Index-1) rem 3), [
			brad@marmot.cs.ubc.ca,
			brad@avahi.cs.ubc.ca,	%	brad@avahi.cs.ubc.ca, 
			brad@ayeaye.cs.ubc.ca	%	brad@fossa.cs.ubc.ca,
			%brad@fossa.cs.ubc.ca	%   brad@indri.cs.ubc.ca
			]).

waitForTerm([], TotalStates) ->	
	TotalStates;
waitForTerm([FirstPID | RestPID], TotalStates) ->
	receive
		{FirstPID, NumStates, timeout} -> 
		io:format("PID ~w: worker thread ~w has reported a timeout~n", [self(), FirstPID])
	end,
	waitForTerm(RestPID, TotalStates + NumStates).


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
	reach([], End, Names,dict:new()), % if this returns, End was not found

	io:format("PID ~w: waiting for termination...~n", [self()]),

	NumStates = waitForTerm(Names, 0),
	io:format("=== State ~w was not found ===~n", [End]),
	io:format("=== Total of ~w states visited ===~n", [NumStates]),
  	Dur = timer:now_diff(now(), T0)*1.0e-6,
	io:format("Execution time: ~w~n", [Dur]),
	done.	

%%----------------------------------------------------------------------
%% Function: sendStates/2
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%			Thread i owns state n iff stateHash(n) mod p is i, 
%%			where p is the number of threads. 
%% Args    : First is the state we're currently sending
%%			 Rest are the rest of the states to send
%%			 Names is a list of PIDs
%% Returns : ok
%%     
%%----------------------------------------------------------------------
sendStates([], _) ->
	ok;

sendStates([First | Rest], Names) ->
	Owner = lists:nth(1+(stateHash(First) rem length(Names)), Names),

% a silly hash function
%	Owner = lists:nth(1+(lists:sum(tuple_to_list(First)) rem length(Names)), Names),
%	Owner = lists:nth(1+(First rem length(Names)), Names), % mod calculation (rem is %)
%	io:format("Owner of state ~w is ~w - sending...~n", [First, Owner]), % debugging message

%	enable bit packing here
%	Owner ! {stress:stateToBits(First),state},
	Owner ! {First,state},
	sendStates(Rest, Names).

%%----------------------------------------------------------------------
%% Function: stateHash/1
%% Purpose : Maps states to owning threads. 
%% 
%% Args    : State is the state find the owner of
%%			 (assumes states are tuples)
%%			 
%% Returns : Owning thread in the range [1..P]
%%     
%%----------------------------------------------------------------------
stateHash(State) ->
	1*element(1,State)+2*element(2,State)+3*element(3,State)+4*element(4,State)
		+5*element(5,State)+6*element(6,State). %+7*element(7,State).

%%----------------------------------------------------------------------
%% Function: initThreads/3
%% Purpose : Spawns worker threads. Passes the command-line input to each thread.
%%		Sends the list of all PIDs to each thread once they've all been spawned.
%% Args    : Names is a list of PIDs of threads spawned so far.
%%			NumThreads is the number of threads left to spawn.
%%			Data is the command-line input.
%% Returns :
%%     
%%----------------------------------------------------------------------
initThreads(Names, 1, _) ->	
	[self() | Names];
% Data is just End right now
initThreads(Names, NumThreads, Data) ->
	% ID = spawn(preach, startWorker, [Data]),
	ID = spawn(mynode(NumThreads),preach,startWorker,[Data]),
	io:format("Starting worker thread on ~w with PID ~w~n", [mynode(NumThreads), ID]),
	FullNames = initThreads([ID | Names], NumThreads-1, Data),
	ID ! FullNames. % send each worker the PID list

%%----------------------------------------------------------------------
%% Function: startWorker/1
%% Purpose : Initializes a worker thread by receiving the list of PIDs and 
%%		calling reach/4.
%% Args    : Trans is the list of transitions
%%	     End is the state we're looking for
%% Returns :
%%     
%%----------------------------------------------------------------------
startWorker(End) ->
    receive
        Names -> do_nothing % dummy RHS
    end,
	reach([], End, Names,dict:new()),
	ok.

%%----------------------------------------------------------------------
%% Function: reach/4
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
%%
%% Returns :
%%     
%%----------------------------------------------------------------------
reach([FirstState | RestStates], End, Names, BigList) ->
	IsOldState = dict:is_key(FirstState, BigList),
	if IsOldState ->
		reach(RestStates, End, Names, BigList);
	true ->
%		enable bit packing here
		CurState = FirstState,
%		CurState = stress:bitsToState(FirstState),

		NewStates = stress:transition(CurState, start),
		EndFound = stateMatch(CurState,End),

		if EndFound ->
			io:format("=== State ~w found by PID ~w ===~n", [End,self()]),
			io:format("PID ~w: # states visited was ~w~n", [self(), dict:size(BigList)]),
			terminateAll(Names);
		true ->
			sendStates(NewStates, Names),
			reach(RestStates, End, Names, dict:append(FirstState, true, BigList)) % grow the big list
		end
	end;

% StateQ is empty, so check for messages. If none are found, we die
reach([], End, Names, BigList) ->
	NewQ = checkMessageQ(timeout, BigList, Names), 
	NewQ2 = lists:usort(NewQ), % remove any duplicate states
	if NewQ == [] ->
			[];
	   true ->
		reach(NewQ2, End, Names, BigList)
	end.

%%----------------------------------------------------------------------
%% Function: checkMessageQ/2
%% Purpose : Polls for incoming messages for 10 seconds; terminates if no
%%				messages arrive.
%% Args    : timeout is atomic indicator that we are polling;
%%			 notimeout performs a nonblocking receive of a state
%%			 BigList is used only to report the size upon termination
%% Returns : List of received states
%%     
%%----------------------------------------------------------------------
checkMessageQ(timeout, BigList, Names) ->
	receive
	die -> 
		io:format("PID ~w: was told to die; visited ~w unique states~n", [self(), dict:size(BigList)]),
		exit(normal);
    {State, state} ->
%		io:format("PID ~w received state ~w~n", [self(), State]), % for debugging
		[State | checkMessageQ(notimeout,BigList,Names)]
	after 
		10000 -> % wait for 10000 ms   
		lists:nth(1,Names) ! {self(), dict:size(BigList), timeout},
		io:format("PID ~w: TIMEOUT; visited ~w unique states~n", [self(), dict:size(BigList)]),
		[] 
	end;

% Get all queued messages without waiting
checkMessageQ(notimeout, BigList, _) ->
	receive
	die -> 
		io:format("PID ~w: was told to die; visited ~w unique states~n", [self(), dict:size(BigList)]),
		exit(normal);
        {State, state} ->
%		io:format("PID ~w received state ~w~n", [self(), State]), % for debugging
		[State | checkMessageQ(notimeout,BigList,[])]
	after 
		0 -> % wait for 0 ms   
			[] 
	end.

%%----------------------------------------------------------------------
%% Function: terminateAll/1
%% Purpose : Terminates all processes if the end state is found
%% Args    : A list of the PIDs to send die signals to
%% Returns :
%%     
%%----------------------------------------------------------------------
terminateAll([]) ->	
	exit(normal);
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
