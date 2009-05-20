%---------------Manually added-------------------%

-module(test).
-export([start/3,startWorker/1]).
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
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_exitCrit) ->% s/mu_p/Field/
	    
	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_unlocked)}),%},
%	    X = (Field rem 2)+1, io:format("Field=~w X=~w~n",[Field,X]),
	    %State#state{
	      mu_turn = ((State#state.mu_turn)#mu_turn{
				     turn = setelement(1,(State#state.mu_turn)#mu_turn.turn,(Field rem 2)+1)}),%}, % s/mu_p/Field/; it was 1 - Field
%	    io:format("Field=~w X=~w  turn=~w~n",[Field,X,element(1,(State#state.mu_turn)#mu_turn.turn)]),
	    %State#state{
	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_init)})};
       
       true -> null
    end.
%======================RuleBase1=====================
rule1(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_crit) ->% s/mu_p/Field/

	    State#state{mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_exitCrit)})};

       true -> null
    end.
%======================RuleBase2=====================
rule2(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_lockAndRetry) ->% s/mu_p/Field/
	    
	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_locked)}),%},
	    %State#state{
	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_whileOtherLocked)})};
       
       true -> null
    end.
%======================RuleBase3=====================
rule3(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_waitForTurn) ->% s/mu_p/Field/
	    
	    if ( (element(1,(State#state.mu_turn)#mu_turn.turn) /= Field) ) ->% s/mu_p/Field/
		    State#state{mu_s = ((State#state.mu_s)#mu_s{
					  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_lockAndRetry)})};
	       true -> null
	    end
		;
       
       true -> null
    end.
%======================RuleBase4=====================
rule4(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_unlock) ->% s/mu_p/Field/

	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_unlocked)}),%},
	    %State#state{
	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_waitForTurn)})};
       
       true -> null
    end.
%======================RuleBase5=====================
rule5(State = #state{}, Field) ->
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_checkTurn) ->% s/mu_p/Field/
	    
	    if ( (element(1,(State#state.mu_turn)#mu_turn.turn) == ((Field rem 2)+1)) ) ->% s/mu_p/Field/; it was 1 - Field
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
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_whileOtherLocked) ->% s/mu_p/Field/

	    if ( (element(((Field rem 2)+1),(State#state.mu_c)#mu_c.c) == mu_unlocked) ) ->% s/mu_p/Field/; it was 1 - Field
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
    if (element(Field,(State#state.mu_s)#mu_s.s) == mu_init) ->% s/mu_p/Field/
	    %io:format("RuleBase7: Field = ~w, State = ~w~n",[Field,State]),
	    State#state{mu_c = ((State#state.mu_c)#mu_c{
				  c = setelement(Field,(State#state.mu_c)#mu_c.c,mu_locked)}),%},
	    %State#state{
	      mu_s = ((State#state.mu_s)#mu_s{
				  s = setelement(Field,(State#state.mu_s)#mu_s.s,mu_whileOtherLocked)})};
       true -> null
    end.
%======================StartState=====================
startstate() ->
    #state{mu_s = #mu_s{s={mu_init,mu_init}},
	   mu_c = #mu_c{c={mu_unlocked,mu_unlocked}},
	   mu_turn = #mu_turn{turn={1}}
	  }.
