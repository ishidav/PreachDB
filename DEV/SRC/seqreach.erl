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

-export([reach/4,start/3]).

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
  	reach(Start,Steps,End,sets:new()),
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
reach([FirstState | RestStates],Steps,End,BigList) ->
	NewStates = addState(FirstState, Steps),
	Exceeds = fun(X) -> X > End end,
	NewStates2 = lists:dropwhile(Exceeds, NewStates), % removes states beyond the boundary
	EndState = fun(X) -> X == End end,
	EndFound = lists:any(EndState, NewStates2),
	NewStates3 = sets:subtract(sets:from_list(NewStates2), BigList), % remove states already in the big list
	NewQ = RestStates ++ sets:to_list(NewStates3),

	if EndFound ->
		io:format("State ~w found!~n", [End]);
	   NewQ == [] ->
		io:format("State ~w NOT found!~n", [End]);
	   true ->
		reach(NewQ, Steps, End, sets:union(BigList, NewStates3))
	end;
reach([], _, _,_) ->
	ok.

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


%-------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: seqreach.erl,v $
% Revision 1.2  2009/02/23 02:43:31  binghamb
% Deleted some commented out code and filled in details in function/module headers
%
% Revision 1.1  2009/02/14 00:53:47  depaulfm
% Continue Bootstrapping repository
%

