%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [tiny.erl]
%
%  PackageName                [preach]
%
%  Synopsis                   [Gospel version of a stress test for controlling
%								the number of states]
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
-module(tiny).
-export([transition/2, guard/2, action/2,stateMatch/2]).

% a tiny state space
% 4 states: {0,0},{0,1},{1,0},{1,1}
% transitions:	{0,0} -> {0,1}
%		{1,0} -> {0,0}
%		{0,1} -> {0,0}

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

% may need to allow Pattern to be a list of states, possibly
% with don't care variables
stateMatch(State, Pattern) ->
	Pairs = lists:zip(tuple_to_list(State), tuple_to_list(Pattern)),
	Eq = fun({X,Y}) -> (X == Y) or (Y == dc) end,
	lists:all(Eq, Pairs).

%-------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: tiny.erl,v $
% Revision 1.1  2009/03/25 23:56:53  binghamb
% A tiny transition system of 4 states.
%
%
%
%
