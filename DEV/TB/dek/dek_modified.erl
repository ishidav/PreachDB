% $Id: dek_modified.erl,v 1.4 2009/08/22 19:49:17 depaulfm Exp $
%------------------------------------------------------------------------------
%  LICENSE AGREEMENT
% 
%  FileName                   [dek_modified.erl]
% 
%  PackageName                [preach]
% 
%  Synopsis                   [This is a semi-automatic translation of         ]%                             [ dek_modified.m                                 ]
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

-module(dek_modified).
%-define(MODULE_NAME, dek_modified).
%-export([start/3,startWorker/1]).
-export([start/0,autoStart/0,startWorker/1]).
-include("$PREACH_PATH/DEV/SRC/preach.erl").

stateToBits(State) -> State.
bitsToState(Bits) -> Bits.
stateMatch(State, Pattern) -> State == Pattern. 

transition(State) ->
  T = [ rule0(State,1), rule0(State,2),
	rule1(State,1), rule1(State,2),
	rule2(State,1), rule2(State,2),
	rule3(State,1), rule3(State,2),
	rule4(State,1), rule4(State,2),
	rule5(State,1), rule5(State,2),
	rule6(State,1), rule6(State,2),
	rule7(State,1), rule7(State,2)
       ],
    [Y || Y <- T, Y /= null],
    io:format("State = ~w~n",[[Y || Y <- T, Y /= null]]),
        [X || X <- T, X /= null].
       
%--------------------------------------------------%


%gospel:program::generate_code
-record(mu_s,{s}).
-record(mu_c,{c}).
-record(mu_turn,{turn}).

% State Definition
-record(state, {
                 mu_turn,
                 mu_c,
                 mu_s
}).
%======================RuleBase0=====================
rule0(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_exitCrit) ->
	    
	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_unlocked)}),%},
	      mu_turn = ((State#state.mu_turn)#mu_turn{
				     turn = setelement(1,(State#state.mu_turn)#mu_turn.turn,(Field rem 2)+1)}),%}, % s/mu_p/Field/; it was 1 - Field
	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_init)})};
       
       true -> null
    end.
%======================RuleBase1=====================
rule1(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_crit) ->

	    State#state{mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_exitCrit)})};

       true -> null
    end.
%======================RuleBase2=====================
rule2(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_lockAndRetry) ->
	    
	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_locked)}),%},
	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_whileOtherLocked)})};
       
       true -> null
    end.
%======================RuleBase3=====================
rule3(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_waitForTurn) ->
	    
	    if ( (element(1,(State#state.mu_turn)#mu_turn.turn) /= Field) ) ->
		    State#state{mu_s = ((State#state.mu_s)#mu_s{
					  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_lockAndRetry)})};
	       true -> null
	    end
		;
       
       true -> null
    end.
%======================RuleBase4=====================
rule4(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_unlock) ->

	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_unlocked)}),%},

	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_waitForTurn)})};
       
       true -> null
    end.
%======================RuleBase5=====================
rule5(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_checkTurn) ->
	    
	    if ( (element(1,(State#state.mu_turn)#mu_turn.turn) == ((Field rem 2)+1)) ) ->
		    State#state{mu_s = ((State#state.mu_s)#mu_s{
					  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_unlock)})};
	       
	       true ->
		    State#state{mu_s = ((State#state.mu_s)#mu_s{
					  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_whileOtherLocked)})}
	    end
		;
       
       true -> null
    end.
%======================RuleBase6=====================
rule6(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_whileOtherLocked) ->

	    if ( (element(((Field rem 2)+1),(State#state.mu_c)#mu_c.c) == mu_unlocked) ) ->
		    State#state{mu_s = ((State#state.mu_s)#mu_s{
					  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_crit)})};
	       
	       true ->
		    State#state{mu_s = ((State#state.mu_s)#mu_s{
					  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_checkTurn)})}
	    end
		;

       true -> null
    end.

 %======================RuleBase7=====================
rule7(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_init) ->

	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_locked)}),%},

	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_whileOtherLocked)})};
       true -> null
    end.
%======================StartState=====================
startstates() ->
    [#state{mu_s = #mu_s{s={mu_init,mu_init}},
	   mu_c = #mu_c{c={mu_unlocked,mu_unlocked}},
	   mu_turn = #mu_turn{turn={1}}
	  }].
