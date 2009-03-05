%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [seqreach.erl]
%
%  PackageName                [preach]
%
%  Synopsis                   [Main erl module for sequential Model Checking]
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
-module(seqreach).

-export([start/3, stateMatch/2]).

%%----------------------------------------------------------------------
%% Function: start/3
%% Purpose : A timing wrapper for our "integer reachability"
%%	     toy program.
%% Args    : P is the number of Erlang threads to use;
%%	     Start is a list of integer start states;
%%	     Trans is a list of integer transitions;
%%	     End is the integer state we're looking for
%% Returns : <not used>
%%     
%%----------------------------------------------------------------------
start(Start,Steps,End)->
  	T0 = now(),
  	reach(Start, End, sets:new()),
	%reach(Start,Steps,End,sets:new()),
  	Dur = timer:now_diff(now(), T0)*1.0e-6,
	io:format("Execution time: ~w~n", [Dur]).

%%----------------------------------------------------------------------
%% Function: reach/4
%% Purpose : Removes the first state from the list, and adds each element
%%		of Steps to it, generating length(Steps) new states that
%%		are appended to the list of states. Recurses until there
%%		are no further states to process.
%% Args    : FirstState is the state to remove from the state queue
%%	     RestStates is the remainder of the state queue
%%	     Steps is the static list of numbers to add to FirstState
%%	     End is the state we seek. All states with a value greater
%%	     than End are discarded.
%%	     BigList is a set of states that have appeared in the state
%%	     list already.
%%
%% Returns : <not used>
%%     
%%----------------------------------------------------------------------

%reach([FirstState | RestStates],Steps,End,BigList) ->
reach([FirstState | RestStates], End, BigList) ->
	NewStates = transition(FirstState, start),
	io:format("State ~w transitions to state(s) ~w~n", [FirstState, NewStates]),

	%NewStates = addState(FirstState),
	%Exceeds = fun(X) -> X > End end,
	%NewStates2 = lists:dropwhile(Exceeds, NewStates), % removes states beyond the boundary
	EndState = fun(X) -> X == End end,
	EndFound = lists:any(EndState, NewStates),
	NewStates2 = sets:subtract(sets:from_list(NewStates), BigList), % remove states already in the big list
	NewQ = RestStates ++ sets:to_list(NewStates2),

	if EndFound ->
		io:format("State ~w found!~n", [End]);
	   NewQ == [] ->
		io:format("State ~w NOT found!~n", [End]);
	   true ->
		reach(NewQ, End, sets:union(BigList, NewStates2))
	end.
%reach([], _, _) ->
%	ok.

%%----------------------------------------------------------------------
%% Function: addState/2
%% Purpose : Generates a new state by summing State and the head of the
%%	     transition list. Recurses on the rest of the transition list.
%% Args    : State is the state we're exploring
%%	     FirstStep is the head of the transition list.
%%	     RestSteps is the remainder of the list.
%%
%% Returns : <not used>
%%     
%%----------------------------------------------------------------------
addState(State, [FirstStep | RestSteps]) ->
	NewState = State + FirstStep,
	% io:format("~w (+~w)==> ~w~n", [State, FirstStep, NewState]), % for debugging
	[NewState | addState(State, RestSteps)];
addState(_, []) ->
	[].

transition(State, start) ->
	T = transition(2, State), % 2 is the number of guarded commands
	[X || X <- T, X /= null];
transition(0, _) ->
	[];
transition(Index, State) ->
	[guard(Index, State) | transition(Index-1, State)].
	

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



%-------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: seqreach.erl,v $
% Revision 1.4  2009/03/05 23:26:28  binghamb
% Added matchState function to check for end states with don't care variables. Need to move this function eventually, and clean up some functions/documentation that are now not used.
%
% Revision 1.3  2009/03/05 09:12:44  binghamb
% Augmented with transition function and a toy example.
%
% Revision 1.2  2009/02/23 02:43:31  binghamb
% Deleted some commented out code and filled in details in function/module headers
%
% Revision 1.1  2009/02/14 00:53:47  depaulfm
% Continue Bootstrapping repository
%

