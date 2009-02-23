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

-export([start/2,startWorker/1]).


%%----------------------------------------------------------------------
%% Function: start/2
%% Purpose : A timing wrapper for the parallel version of 
%%		our "integer reachability" toy program.
%% Args    : P is the number of Erlang threads to use;
%%	     Start is a list of integer start states;
%%	     Trans is a list of integer transitions;
%%	     End is the integer state we're looking for
%% Returns :
%%     
%%----------------------------------------------------------------------
start({Start,Trans,End},P) ->
 	T0 = now(),
	Names = initThreads([], P,{Trans,End}), 
	sendStates(Start, Names), 
	reach([], Trans, End, Names,sets:new()), % if this returns, End was not found
	io:format("=== State ~w was not found ===~n", [End]),
  	Dur = timer:now_diff(now(), T0)*1.0e-6,
	io:format("Execution time: ~w~n", [Dur]),
	done.	

sendStates([], _) ->
	ok;

%%----------------------------------------------------------------------
%% Function: sendStates/2
%% Purpose : Sends a list of states to their respective owners, one at a time.
%%	     Thread i owns state n iff n (mod p) = i, where p is the number of threads.
%% Args    : First is the state we're currently sending
%%	     Rest are the rest of the states to send
%%	     Names is a list of PIDs
%% Returns :
%%     
%%----------------------------------------------------------------------
% sends a list of states to their owners, using the state number mod P
sendStates([First | Rest], Names) ->
	Owner = lists:nth(1+(First rem length(Names)), Names), % mod calculation (rem is %)
%	io:format("Owner of state ~w is ~w - sending...~n", [First, Owner]), % debugging message
	Owner ! First,
	sendStates(Rest, Names).

%%----------------------------------------------------------------------
%% Function: initThreads/3
%% Purpose : Spawns worker threads. Passes the command-line input to each thread.
%%		Sends the list of all PIDs to each thread once they've all been spawned.
%% Args    : Names is a list of PIDs of threads spawned so far.
%%	     NumThreads is the number of threads left to spawn.
%%	     Data is the command-line input.
%% Returns :
%%     
%%----------------------------------------------------------------------
initThreads(Names, 1, _) ->	
	[self() | Names];
initThreads(Names, NumThreads, Data) ->
	ID = spawn(preach, startWorker, [Data]),
	FullNames = initThreads([ID | Names], NumThreads-1, Data),
	ID ! FullNames. % send each worker the PID list

%%----------------------------------------------------------------------
%% Function: startWorker/2
%% Purpose : Initializes a worker thread by receiving the list of PIDs and 
%%		calling reach/5.
%% Args    : Trans is the list of transitions
%%	     End is the state we're looking for
%% Returns :
%%     
%%----------------------------------------------------------------------
startWorker({Trans,End}) ->
    receive
        Names -> do_nothing % dummy RHS
    end,
	reach([], Trans, End, Names,sets:new()),
	ok.

%%----------------------------------------------------------------------
%% Function: reach/5
%% Purpose : Removes the first state from the list, and adds each element
%%		of Steps to it, generating length(Steps) new states that
%%		are appended to the list of states. Recurses until there
%%		are no further states to process. 
%%		For example, if {Start,Trans,End} is {[2],[5,6],25},
%%		the first states we generate are {2+5, 2+6} = {7,8},
%%		and the end state will be found since 25 = 2+6+6+6+5.
%% Args    : FirstState is the state to remove from the state queue
%%	     RestStates is the remainder of the state queue
%%	     Steps is the static list of numbers to add to FirstState
%%	     End is the state we seek. All states with a value greater
%%	     than End are discarded.
%%	     BigList is a set of states that have been generated by this 
%%		thread so far. That is, BigList may contain states that
%%		do not belong to this thread. If we want to save memory
%%		at the cost of sending some unnecessary messages, the BigList
%%		should be altered to only include states that have previously
%%		entered this worker's state queue.
%%		NOTE: Any line involving the BigList probably has poor performance.
%%
%% Returns :
%%     
%%----------------------------------------------------------------------
reach([FirstState | RestStates],Steps, End, Names, BigList) ->
	NewStatesTemp1 = expand(FirstState, Steps), % expand a single state
	Exceeds = fun(X) -> X > End end,
	NewStatesTemp2 = lists:dropwhile(Exceeds, NewStatesTemp1), % removes states beyond the boundary
	NewStates = sets:subtract(sets:from_list(NewStatesTemp2), BigList), % remove states already in the big list
	EndFound = sets:is_element(End, NewStates), % check if we've generated the end
	if EndFound ->
		io:format("=== State ~w found by PID ~w ===~n", [End,self()]),
		io:format("PID ~w: # unique expanded states was ~w~n", [self(), sets:size(BigList)]),
		terminateAll(Names);
	   true -> 
		sendStates(sets:to_list(NewStates), Names),
		reach(RestStates,Steps,End,Names, sets:union(BigList, NewStates)) % grow the big list
	end;

% StateQ is empty, so check for messages. If none are found, we die
reach([], Steps, End, Names, BigList) ->
	NewQ = checkMessageQ(timeout, BigList), 
	NewQ2 = lists:usort(NewQ),
	if NewQ == [] ->
			[];
	   true ->
		% remove duplicate states before calling reach
		reach(NewQ2, Steps, End, Names, BigList)
	end.

%%----------------------------------------------------------------------
%% Function: checkMessageQ/2
%% Purpose : Polls for incoming messages for 1 second; terminates if no
%%		messages arrive.
%% Args    : timeout is atomic indicator that we are polling;
%%		notimeout performs a nonblocking receive of a state
%%	     BigList is used only to report the size upon termination
%% Returns : List of received states
%%     
%%----------------------------------------------------------------------
checkMessageQ(timeout, BigList) ->
	receive
	die -> 
		io:format("PID ~w: # unique expanded states was ~w~n", [self(), sets:size(BigList)]),
		exit(normal);
        State ->
%		io:format("PID ~w received state ~w~n", [self(), State]), % for debugging
		[State | checkMessageQ(notimeout,BigList)]
	after 
		1000 -> % wait for 1000 ms   
		io:format("PID ~w: # unique expanded states was ~w~n", [self(), sets:size(BigList)]),
			[] 
	end;

% Get all queued messages without waiting
checkMessageQ(notimeout,BigList) ->
	receive
	die -> 
		io:format("PID ~w: # unique expanded states was ~w~n", [self(), sets:size(BigList)]),
		exit(normal);
        State ->
%		io:format("PID ~w received state ~w~n", [self(), State]), % for debugging
		[State | checkMessageQ(notimeout,BigList)]
	after 
		0 -> % wait for 0 ms   
			[] 
	end.

%%----------------------------------------------------------------------
%% Function: expand/2
%% Purpose : Performs expansion of a state
%% Args    : State is the state to expand
%%	     FirstStep is the current transition rule, which is simply addition
%% Returns : The list of sucessors to State
%%     
%%----------------------------------------------------------------------
expand(State, [FirstStep | RestSteps]) ->
	NewState = State + FirstStep,
%	io:format("~w (+~w)==> ~w~n", [State, FirstStep, NewState]), % verbose output
	[NewState | expand(State, RestSteps)];
expand(_, []) ->
	[].

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

%--------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: preach.erl,v $
% Revision 1.2  2009/02/23 02:43:40  binghamb
% Deleted some commented out code and filled in details in function/module headers
%
% Revision 1.1  2009/02/14 00:53:47  depaulfm
% Continue Bootstrapping repository
%
