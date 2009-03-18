%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [stress.erl]
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
-module(stress).

-export([transition/2, guard/2, action/2, bitsToState/1, stateToBits/1]).

transition(State, start) ->
        T = transition(7, State), % 6 is the number of guarded commands
        [X || X <- T, X /= null];
transition(0, _) ->
        [];
transition(Index, State) ->
        [guard(Index, State) | transition(Index-1, State)].


guard(Index, State) ->
    %S0 = element(1,State),
    %S1 = element(3,State),
    case Index of
	1 -> action(Index,State); 
	2 -> action(Index,State);
	3 -> action(Index,State);
	4 -> action(Index,State);
	5 -> action(Index,State);
	6 -> action(Index,State);
	7 -> action(Index,State)
	end.	     
		 
% action may be a function of State, but not for the simple example
action(Index, State) ->
% odd  refers to p=0
% even refers to p=1
	if Index /= 7 ->
			setelement(Index,State,(element(Index,State)+1) rem 10); % 10 is the number of values
		true -> 
			setelement(7,State,(element(7,State)+1) rem 1) % want 1 M states
	end.

%%----------------------------------------------------------------------
%% Function: stateToBits/1
%% Purpose : Converts a tuple of integers to a bit string. 
%%				
%% Args    : State is the tuple to convert 
%%			
%% Returns : A bit string where 4 bits are used for each integer in the
%%				State tuple.
%%     
%%----------------------------------------------------------------------
stateToBits(State) ->
	A = element(1,State),
	B = element(2,State),
	C = element(3,State),
	D = element(4,State),
	E = element(5,State),
	F = element(6,State),
%	<<A:4,B:4,C:4,D:4,E:4,F:4>>.	
	G = element(7,State),
	<<A:4,B:4,C:4,D:4,E:4,F:4,G:4>>.

%%----------------------------------------------------------------------
%% Function: bitsToState/1
%% Purpose : Converts a bit string to a tuple of integers. 
%%				
%% Args    : Bits is the bitstring to convert 
%%			
%% Returns : A tuple where each integer has the value of the 4 bits
%%				in the corresponding position of Bits.
%%     
%%----------------------------------------------------------------------
bitsToState(Bits) ->
%	<<A:4,B:4,C:4,D:4,E:4,F:4>> = Bits,
%	{A,B,C,D,E,F}.
	<<A:4,B:4,C:4,D:4,E:4,F:4,G:4>> = Bits,
	{A,B,C,D,E,F,G}.


%-------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: stress.erl,v $
% Revision 1.1  2009/03/18 23:19:09  binghamb
% Initial checkin of stress test transition system.
%
%
%
