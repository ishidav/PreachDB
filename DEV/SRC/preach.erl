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

% preach.erl: Stands for "Parallel Reachability".
% Brad Bingham, 13/02/09
% Inputs: {Start,Trans,End}, P
%		P is the number of Erlang threads to use
%		Start is a list of integer start states
%		Trans is a list of integer transitions
%		End is the integer state we're looking for
% For example, if {Start,Trans,End} is {[2],[5,6],25},
% the first states we generate are {2+5, 2+6} = {7,8},
% and the end state will be found since 25 = 2+6+6+6+5.


%%----------------------------------------------------------------------
%% Function: start/2
%% Purpose : 
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
%% Purpose : 
%% Args    : 
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
%% Purpose : 
%% Args    : 
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
%% Purpose : 
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
startWorker({Trans,End}) ->
    receive
        Names -> do_nothing % dummy RHS
    end,
%	io:format("Data is ~w~n", [{Trans,End}]),
%	io:format("Names are ~w~n", [Names]),
	reach([], Trans, End, Names,sets:new()),
	ok.

%%----------------------------------------------------------------------
%% Function: reach/5
%% Purpose : 
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
% BigList stores every state ever reached by this worker
reach([FirstState | RestStates],Steps, End, Names, BigList) ->
	NewStatesTemp1 = expand(FirstState, Steps), % expand a single state
	Exceeds = fun(X) -> X > End end,
	NewStatesTemp2 = lists:dropwhile(Exceeds, NewStatesTemp1), % removes states beyond the boundary
	NewStates = sets:subtract(sets:from_list(NewStatesTemp2), BigList), % remove states already in the big list
	%EndState = fun(X) -> X == End end,
	EndFound = sets:is_element(End, NewStates), % check if we've generated the end
	if EndFound ->
		io:format("=== State ~w found by PID ~w ===~n", [End,self()]),
		io:format("PID ~w: # unique expanded states was ~w~n", [self(), sets:size(BigList)]),
		terminateAll(Names);
	   true -> 
		sendStates(sets:to_list(NewStates), Names),
		reach(RestStates,Steps,End,Names, sets:union(BigList, NewStates)) % grow the big list
	end;
%% below is old stuff from the sequential version

%	NewQ1 = lists:usort(RestStates ++ NewStates), % removes duplicate states
%	Exceeds = fun(X) -> X > End end,
%	NewQ2 = lists:dropwhile(Exceeds, NewQ1), % removes states beyond the boundary
%	EndState = fun(X) -> X == End end,
%	EndFound = lists:any(EndState, NewQ2),
%	if EndFound ->
%		io:format("State ~w found!~n", [End]);
%	   NewQ2 == [] ->
%		io:format("State ~w NOT found!~n", [End]);
%	   true ->
%		reach(NewQ2, Steps, End, [])
%	end;

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
%% Purpose : 
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
% Wait for timeout for a message to arrive
checkMessageQ(timeout, BigList) ->
	receive
	die -> 
		io:format("PID ~w: # unique expanded states was ~w~n", [self(), sets:size(BigList)]),
		exit(normal);
        State ->
%		io:format("PID ~w received state ~w~n", [self(), State]),
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
%		io:format("PID ~w received state ~w~n", [self(), State]),
		[State | checkMessageQ(notimeout,BigList)]
	after 
		0 -> % wait for 0 ms   
			[] 
	end.

%%----------------------------------------------------------------------
%% Function: expand/2
%% Purpose : 
%% Args    : 
%% Returns :
%%     
%%----------------------------------------------------------------------
expand(State, [FirstStep | RestSteps]) ->
	NewState = State + FirstStep,
%	io:format("~w (+~w)==> ~w~n", [State, FirstStep, NewState]),
	[NewState | expand(State, RestSteps)];
expand(_, []) ->
	[].

%%----------------------------------------------------------------------
%% Function: terminateAll/1
%% Purpose : 
%% Args    : 
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
% Revision 1.1  2009/02/14 00:53:47  depaulfm
% Continue Bootstrapping repository
%
