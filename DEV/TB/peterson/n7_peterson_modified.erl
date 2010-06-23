% $Id: n7_peterson_modified.erl,v 1.2 2009/08/19 05:05:23 depaulfm Exp $
%------------------------------------------------------------------------------
%  LICENSE AGREEMENT
% 
%  FileName                   [7_peterson_modified.erl]
% 
%  PackageName                [preach]
% 
%  Synopsis                   [This is a semi-automatic translation of         ]
%                             [ 7_peterson_modified.m                          ]
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
%-------------------------------------------------------------------------------

% IMPORTANT : (temporary arrangement)
% Requires preach.erl to have the following 
%
%	ID = spawn(mynode(NumThreads),preach,startWorker,[Data]),
% replaced with-->
%	ID = spawn(mynode(NumThreads),test,startWorker,[Data]),
%
%---------------Manually added-------------------%

-module(n7_peterson_modified).
%-export([start/3,startWorker/1]).
-export([start/0, autoStart/0]).
-include("$PREACH_PATH/DEV/SRC/preach.erl").

stateToBits(State) -> State.
bitsToState(Bits) -> Bits.
stateMatch(State, Pattern) -> State == Pattern. 

transition(State) ->
  T = [ rule0(State,1), rule0(State,2),rule0(State,3), rule0(State,4),rule0(State,5),rule0(State,6),rule0(State,7),
	rule1(State,1), rule1(State,2),rule1(State,3), rule1(State,4),rule1(State,5),rule1(State,6),rule1(State,7),
	rule2(State,1), rule2(State,2),rule2(State,3), rule2(State,4),rule2(State,5),rule2(State,6),rule2(State,7),
	rule3(State,1), rule3(State,2),rule3(State,3), rule3(State,4),rule3(State,5),rule3(State,6),rule3(State,7),
	rule4(State,1), rule4(State,2),rule4(State,3), rule4(State,4),rule4(State,5),rule4(State,6),rule4(State,7)
       ],
    % Uncomment the next few lines if you want to print all Reachable States
    % Well you will alow want to select the appropriate dir path
    %{ok,Filename} = file:open("YOUR_DIRECTORY_HERE/Reachable_States",[write]),
    %io:format(Filename,"State = ~w~n",[[Y || Y <- T, Y /= null]]), file:close(Filename),
        [X || X <- T, X /= null].
       
%--------------------------------------------------%

%gospel:program::generate_code
-record(mu_p,{p}).
-record(mu_q,{q}).
-record(mu_turn,{turn}).
-record(mu_localj,{localj}).

% State Definition
-record(state, {
                 mu_localj,
                 mu_turn,
                 mu_q,
                 mu_p
}).
%======================RuleBase0=====================
rule0(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_p)#mu_p.p) == mu_L4) ->
	    
	    State#state{mu_q = ((State#state.mu_q)#mu_q{
				  q = setelement(Field,(State#state.mu_q)#mu_q.q,2)}),%},
			%State#state{
			mu_p = ((State#state.mu_p)#mu_p{
				  p = setelement(Field,(State#state.mu_p)#mu_p.p,mu_L0)})};
       
       true -> null
    end.
%======================RuleBase1=====================
rule1(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_p)#mu_p.p) == mu_L3) ->

    if ((((((((not(Field /= 1) or (element(1,(State#state.mu_q)#mu_q.q) < element(Field,(State#state.mu_localj)#mu_localj.localj))) and 
	       (not((Field /= 2)) or (element(2,(State#state.mu_q)#mu_q.q) < element(Field,(State#state.mu_localj)#mu_localj.localj)))) and
	      (not((Field /= 3)) or (element(3,(State#state.mu_q)#mu_q.q) < element(Field,(State#state.mu_localj)#mu_localj.localj)))) and
	     (not((Field /= 4)) or (element(4,(State#state.mu_q)#mu_q.q) < element(Field,(State#state.mu_localj)#mu_localj.localj)))) and
	    (not((Field /= 5)) or (element(5,(State#state.mu_q)#mu_q.q) < element(Field,(State#state.mu_localj)#mu_localj.localj)))) and
	   (not((Field /= 6)) or (element(6,(State#state.mu_q)#mu_q.q) < element(Field,(State#state.mu_localj)#mu_localj.localj)))) and
	  (not((Field /= 7)) or (element(7,(State#state.mu_q)#mu_q.q) < element(Field,(State#state.mu_localj)#mu_localj.localj)))) or
	(element(element(Field,(State#state.mu_localj)#mu_localj.localj),(State#state.mu_turn)#mu_turn.turn) /= Field))  ->

			Y = (element(Field,(State#state.mu_localj)#mu_localj.localj) + 1),%;

		if ( Y =< 7 ) ->%%%%%%%%%%%%%%%%%%%% THIS RHS WAS HARD-CODED
			X = mu_L1;
		   true ->
			X = mu_L4
		end,
		State#state{
		  mu_localj = ((State#state.mu_localj)#mu_localj{
				 localj = setelement(Field,(State#state.mu_localj)#mu_localj.localj,Y)}),
					       
		  mu_p = ((State#state.mu_p)#mu_p{
			    p = setelement(Field,(State#state.mu_p)#mu_p.p,X)})
		 };

	   true -> null
	end;
       
       true -> null
    end.
%======================RuleBase2=====================
rule2(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_p)#mu_p.p) == mu_L2) ->

	    State#state{mu_turn = ((State#state.mu_turn)#mu_turn{
				     turn = setelement(element(Field,(State#state.mu_localj)#mu_localj.localj),(State#state.mu_turn)#mu_turn.turn,Field)}),%},

			mu_p = ((State#state.mu_p)#mu_p{
				  p = setelement(Field,(State#state.mu_p)#mu_p.p,mu_L3)})};

       true -> null
    end.
%======================RuleBase3=====================
rule3(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_p)#mu_p.p) == mu_L1) ->
	    
	    State#state{mu_q = ((State#state.mu_q)#mu_q{
				  q = setelement(Field,(State#state.mu_q)#mu_q.q,element(Field,(State#state.mu_localj)#mu_localj.localj))}),%},

			mu_p = ((State#state.mu_p)#mu_p{
				  p = setelement(Field,(State#state.mu_p)#mu_p.p,mu_L2)})};
       
       true -> null
    end.
%======================RuleBase4=====================
rule4(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_p)#mu_p.p) == mu_L0) ->

	    State#state{mu_localj = ((State#state.mu_localj)#mu_localj{
				       localj = setelement(Field,(State#state.mu_localj)#mu_localj.localj,2)}),%},

			mu_p = ((State#state.mu_p)#mu_p{
				  p = setelement(Field,(State#state.mu_p)#mu_p.p,mu_L1)})};
       
       true -> null
    end.
%======================StartState=====================
startstates() ->
   [#state{mu_q      = #mu_q{q={1,1,1,1,1,1,1}}, 
	  mu_p      = #mu_p{p={mu_L0,mu_L0,mu_L0,mu_L0,mu_L0,mu_L0,mu_L0}},
	  mu_turn   = #mu_turn{turn={1,1,1,1,1,1,1,1}},
	  mu_localj = #mu_localj{localj={1,1,1,1,1,1,1}}}].
