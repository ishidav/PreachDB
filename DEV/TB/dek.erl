%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [dek.erl]
%
%  PackageName                [preach]
%
%  Synopsis                   [Gospel version of Murphi's 3.1 Dek mutex]
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
-module(dek).

-export([transition/2, guard/2, action/2]).
%%%%% murphi
%Type
%	ind_t :	0..1;
%	label_t : Enum { init, whileOtherLocked, checkTurn, unlock, waitForTurn, lockAndRetry, crit, exitCrit };
%	lock_t : Enum { locked, unlocked };

%Var
%	s :	Array[ ind_t ] Of label_t;
%	c :	Array[ ind_t ] Of lock_t;
%	turn :	0..1;

%%%%% gospel encoding
%
% gospel(label_t) ->
%    init             =   1 
%    whileOtherLocked =   2
%    checkTurn        =   4
%    unlock           =   8
%    waitForTurn      =  16
%    lockAndRetry     =  32
%    crit             =  64
%    exitCrit         = 128
%
% gospel(lock_t) ->
%    locked           =   1 
%    unlocked         =   2

%%%%% gospel state var order
%  s0, c0, s1, c1, turn
%

transition(State, start) ->
        T = transition(16, State), % 16 is the number of guarded commands
        [X || X <- T, X /= null];
transition(0, _) ->
        [];
transition(Index, State) ->
        [guard(Index, State) | transition(Index-1, State)].


guard(Index, State) ->
    S0 = element(1,State),
    S1 = element(3,State),
    case Index of
	
	1 -> % Rule "Init" 
	     if
		 S0 == 1 ->
			action(Index, State);
		    true -> 
			null
		end;
	2 -> % Rule "Init" 
	     if
		 S1 == 1 ->
			action(Index, State);
		    true -> 
			null
		end;
 	3 -> % Rule "WhileOtherLocked"   
	    if
		S0 == 2 ->
			action(Index, State);
		    true -> 
			null
 		end;
 	4 -> % Rule "WhileOtherLocked"   
	    if
		S1 == 2 ->
			action(Index, State);
		    true -> 
			null
 		end;
 	5 -> % Rule "CheckTurn"   
	    if
		S0 == 4 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	6 -> % Rule "CheckTurn"   
	    if
		S1 == 4 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	7 -> % Rule "Unlock"   
	    if
		S0 == 8 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	8 -> % Rule "Unlock"   
	    if
		S1 == 8 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	9 -> % Rule "WaitForTurn"
	    if
		S0 == 16 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	10 -> % Rule "WaitForTurn"
	    if
		S1 == 16 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	11 -> % Rule "LockAndRetry" 
	    if
		S0 == 32 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	12 -> % Rule "LockAndRetry" 
	    if
		S1 == 32 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	13 -> % Rule "Crit"   
	    if
		S0 == 64 ->
		    action(Index, State);
		true -> 
		    null
	    end;
 	14 -> % Rule "Crit"   
	    if
		S1 == 64 ->
		    action(Index, State);
		true -> 
		    null
	    end;
	15 -> % Rule "ExitCrit"
	    if
		S0 == 128 ->
		    action(Index, State);
		true -> 
		    null
	    end;
	16 -> % Rule "ExitCrit"
	    if
		S1 == 128 ->
		    action(Index, State);
		true -> 
		    null
	    end
    end.

% action may be a function of State, but not for the simple example
action(Index, State) ->
% odd  refers to p=0
% even refers to p=1
    case Index of
	1 ->    {2,1,element(3,State),element(4,State),element(5,State)};

	2 ->    {element(1,State),element(2,State),2,1,element(5,State)};

	3 ->    C1 = element(4,State),
		if C1 == 2 ->
			{64,element(2,State),element(3,State),element(4,State),element(5,State)};
		   true ->
			{4,element(2,State),element(3,State),element(4,State),element(5,State)}%null
		end;

	4 ->    C0 = element(2,State), 
		if C0 == 2 -> 
			{element(1,State),element(2,State),64,element(4,State),element(5,State)};
		   true  ->
			{element(1,State),element(2,State),64,element(4,State),element(5,State)}%null
		end;

	5 ->    Tu = element(5,State),
		if Tu == 1 ->
			{8,element(2,State),element(3,State),element(4,State),element(5,State)};
		   true ->
			{4,element(2,State),element(3,State),element(4,State),element(5,State)}	
		end;

	6 ->   Tu = element(5,State),
		if Tu == 1 ->
			{element(1,State),element(2,State),8,element(4,State),element(5,State)};
		   true ->
			{element(1,State),element(2,State),4,element(4,State),element(5,State)}	
		end;

	7 ->   {16,1,element(3,State),element(4,State),element(5,State)};

	8 ->   {element(1,State),element(2,State),16,1,element(5,State)};
	
	9 ->   Tu = element(5,State),
	       if Tu /= 0 ->
		      {32,element(2,State),element(3,State),element(4,State),element(5,State)}; 
		  true -> null
	       end;

	10 ->  Tu = element(5,State),
	       if Tu /= 1 ->
		      {element(1,State),element(2,State),32,element(4,State),element(5,State)}; 
		  true -> null
	       end;

	11 -> {2,1,element(3,State),element(4,State),element(5,State)}; 
	12 -> {element(1,State),element(2,State),2,1,element(5,State)};
	13 -> {128,element(2,State),element(3,State),element(4,State),element(5,State)}; 
	14 -> {element(1,State),element(2,State),128,element(4,State),element(5,State)};

	15 ->  {1,2,element(3,State),element(4,State),1}; 
	16 ->  {element(1,State),element(2,State),1,2,0} 
    end.


%-------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: dek.erl,v $
% Revision 1.1  2009/03/09 23:14:16  depaulfm
% Bootstrapping and debuggin Dek's mutex in gospel
%
%
