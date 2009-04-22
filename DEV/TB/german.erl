
-module(german).
%
%  Hand translation of german.m (murphi,see copy in this directory) 
%  * I removed the data path from the protocol for the initial version.
%    this has the effect that the record types CACHE and MSG, which 
%    have two fields in the data-equiped protocol, degenerate to 
%    a one-field record in this version. hence they are not modeled as records here.
%  * also, removing data causes rulesets parameterized by data values to 
%    collapse, and some state updates to be simplified
%  * this first version just uses three nodes, generalizing should be easy 
%    (and i'll do this soon),
%    although i'm not sure how to create an n-tuple literal where n is a variable,
%    which appears necessary to do the generalization cleanly.  
%

-export([start/3,startWorker/1]).
% -export([transition/1,startstate/0]).


%%----------------------------------------------------------------------
%% 
%% Purpose : Includes the model checker module
%%				
%% Requires: Environment variable PREACH_PATH to be set pointing to
%%	     preach's root directory
%%
-include("$PREACH_PATH/DEV/SRC/preach.erl").


%
%  create the list formed by applying all rules to State, but then
%  filter out all null results (a la Flavio), which are those rules
%  for which the guard doesn't hold
%
transition(State) ->
        T = [ send_req_s(State,1), send_req_s(State,2), send_req_s(State,3),
              send_req_e(State,1), send_req_e(State,2), send_req_e(State,3),
              recv_req_s(State,1), recv_req_s(State,2), recv_req_s(State,3),
              recv_req_e(State,1), recv_req_e(State,2), recv_req_e(State,3),
              send_inv(State,1), send_inv(State,2), send_inv(State,3),
              send_inv_ack(State,1), send_inv_ack(State,2), send_inv_ack(State,3),
              recv_inv_ack(State,1), recv_inv_ack(State,2), recv_inv_ack(State,3),
              send_gnt_s(State,1), send_gnt_s(State,2), send_gnt_s(State,3),
              send_gnt_e(State,1), send_gnt_e(State,2), send_gnt_e(State,3),
              recv_gnt_s(State,1), recv_gnt_s(State,2), recv_gnt_s(State,3),
              recv_gnt_e(State,1), recv_gnt_e(State,2), recv_gnt_e(State,3)
            ],
        [X || X <- T, X /= null].

% PARAM: need N falses in this tuple
all_false() -> {false,false,false}.
all_empty() -> {empty,empty,empty}.
all_invalid() -> {invalid,invalid,invalid}.

stateMatch(State, Pattern) -> dishwasher(State).

-record(murphi_state,
       {
   cache,   % : array [NODE] of CACHE;      -- Caches
   chan1,   % : array [NODE] of MSG;        -- Channels for Req*
   chan2,   % : array [NODE] of MSG;        -- Channels for Gnt* and Inv
   chan3,   % : array [NODE] of MSG;        -- Channels for InvAck
   invSet,  % : array [NODE] of boolean;   -- Set of nodes to be invalidated
   shrSet,  % : array [NODE] of boolean;   -- Set of nodes having S or E copies
   exGntd,  % : boolean;                   -- E copy has been granted
   curCmd,  % : MSG_CMD;                   -- Current request command
   curPtr   % : NODE;                      -- Current request node
%   MemData, % : DATA;                     -- Memory data
%   AuxData, % : DATA;                     -- Auxiliary variable for latest data
       }).

% ruleset d : DATA do startstate "Init"
%   for i : NODE do
%     Chan1[i].Cmd := Empty; Chan2[i].Cmd := Empty; Chan3[i].Cmd := Empty;
%     Cache[i].State := I; InvSet[i] := false; ShrSet[i] := false;
%   end;
%   ExGntd := false; CurCmd := Empty; MemData := d; AuxData := d;
% end end;
startstate() ->
   #murphi_state{
     cache = all_invalid(),
     chan1 = all_empty(),
     chan2 = all_empty(),
     chan3 = all_empty(),
     invSet = all_false(),
     shrSet = all_false(),
     exGntd = false,
     curCmd = empty,
     curPtr = 0  % 0 means undefined
   }.


   dishwasher(Ms = #murphi_state{}) ->
		Ms#murphi_state.curCmd == req_s.

    firstTrans(Ms = #murphi_state{}) ->
 (element(1,Ms#murphi_state.chan1) == req_s) or
(element(1,Ms#murphi_state.chan1) == req_e).

% ruleset i : NODE; d : DATA do rule "Store"
%   Cache[i].State = E
% ==>
%   Cache[i].Data := d; AuxData := d;
% end end;
% JESSE: Store doesn't do anything without data, so no need to model this one

%ruleset i : NODE do rule "SendReqS"
%  Chan1[i].Cmd = Empty & Cache[i].State = I
%==>
%  Chan1[i].Cmd := ReqS;
%end end;
send_req_s(Ms = #murphi_state{}, I) ->
    if (element(I,Ms#murphi_state.chan1) == empty) and
       (element(I,Ms#murphi_state.cache) == invalid)
      -> Ms#murphi_state{chan1 = (setelement(I,Ms#murphi_state.chan1,req_s))};
    true 
      -> null
    end.

% ruleset i : NODE do rule "SendReqE"
%   Chan1[i].Cmd = Empty & (Cache[i].State = I | Cache[i].State = S)
% ==>
%   Chan1[i].Cmd := ReqE;
% end end;
send_req_e(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.chan1) == empty) and
        ((element(I,Ms#murphi_state.cache) == invalid) or
         ( element(I,Ms#murphi_state.cache) == shared) ))
      -> Ms#murphi_state{chan1 = (setelement(I,Ms#murphi_state.chan1,req_e))};
    true 
      -> null
    end.


% ruleset i : NODE do rule "RecvReqS"
%   CurCmd = Empty & Chan1[i].Cmd = ReqS
% ==>
%   CurCmd := ReqS; CurPtr := i; Chan1[i].Cmd := Empty;
%   for j : NODE do InvSet[j] := ShrSet[j] end;
% end end;
recv_req_s(Ms = #murphi_state{}, I) ->
    if (Ms#murphi_state.curCmd == empty) and
       (element(I,Ms#murphi_state.chan1) == req_s)
      -> Ms#murphi_state{
           curCmd = req_s,
           curPtr = I,
           chan1 = (setelement(I,Ms#murphi_state.chan1,empty)),
           invSet = all_false()
         };
    true 
      -> null
    end.

% ruleset i : NODE do rule "RecvReqE"
%   CurCmd = Empty & Chan1[i].Cmd = ReqE
% ==>
%   CurCmd := ReqE; CurPtr := i; Chan1[i].Cmd := Empty;
%   for j : NODE do InvSet[j] := ShrSet[j] end;
% end end;
recv_req_e(Ms = #murphi_state{}, I) ->
    if (Ms#murphi_state.curCmd == empty) and
       (element(I,Ms#murphi_state.chan1) == req_e)
      -> Ms#murphi_state{
           curCmd = req_e,
           curPtr = I,
           chan1 = (setelement(I,Ms#murphi_state.chan1,empty)),
           invSet = Ms#murphi_state.shrSet
         };
    true 
      -> null
    end.

% ruleset i : NODE do rule "SendInv"
%   Chan2[i].Cmd = Empty & InvSet[i] = true &
%   ( CurCmd = ReqE | CurCmd = ReqS & ExGntd = true )
% ==>
%   Chan2[i].Cmd := Inv; InvSet[i] := false;
% end end;
send_inv(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.chan2) == empty) and
        (element(I,Ms#murphi_state.invSet)) and
        ( (element(I,Ms#murphi_state.curCmd) == req_e) or
          ( (element(I,Ms#murphi_state.curCmd) == req_s) and
            (element(I,Ms#murphi_state.exGntd)) )))
      -> Ms#murphi_state{
           chan2 = (setelement(I,Ms#murphi_state.chan2,inv)),
           invSet = (setelement(I,Ms#murphi_state.invSet,false))
         };
    true 
      -> null
    end.

% ruleset i : NODE do rule "SendInvAck"
%   Chan2[i].Cmd = Inv & Chan3[i].Cmd = Empty
% ==>
%   Chan2[i].Cmd := Empty; Chan3[i].Cmd := InvAck;
%   if (Cache[i].State = E) then Chan3[i].Data := Cache[i].Data end;
%   Cache[i].State := I; undefine Cache[i].Data;
% end end;
send_inv_ack(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.chan2) == inv) and
        (element(I,Ms#murphi_state.chan3) == empty))
      -> Ms#murphi_state{
           chan2 = (setelement(I,Ms#murphi_state.chan2,empty)),
           chan3 = (setelement(I,Ms#murphi_state.chan3,inv_ack)),
           cache = (setelement(I,Ms#murphi_state.cache,invalid))
         };
    true 
      -> null
    end.

% ruleset i : NODE do rule "RecvInvAck"
%   Chan3[i].Cmd = InvAck & CurCmd != Empty
% ==>
%   Chan3[i].Cmd := Empty; ShrSet[i] := false;
%   if (ExGntd = true)
%   then ExGntd := false; MemData := Chan3[i].Data; undefine Chan3[i].Data end;
% end end;
recv_inv_ack(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.chan3) == inv_ack) and
        (element(I,Ms#murphi_state.curCmd) /= empty))
      -> Ms#murphi_state{
           chan3 = (setelement(I,Ms#murphi_state.chan3,empty)),
           shrSet = (setelement(I,Ms#murphi_state.shrSet,false)),
           exGntd = false
         };
    true 
      -> null
    end.


% ruleset i : NODE do rule "SendGntS"
%   CurCmd = ReqS & CurPtr = i & Chan2[i].Cmd = Empty & ExGntd = false
% ==>
%   Chan2[i].Cmd := GntS; Chan2[i].Data := MemData; ShrSet[i] := true;
%   CurCmd := Empty; undefine CurPtr;
% end end;
send_gnt_s(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.curCmd) == req_s) and
        (element(I,Ms#murphi_state.curPtr) == I)  and
        (element(I,Ms#murphi_state.chan2) == empty) and
        (element(I,Ms#murphi_state.exGntd) == false))
      -> Ms#murphi_state{
           chan2 = (setelement(I,Ms#murphi_state.chan2,gnt_s)),
           shrSet = (setelement(I,Ms#murphi_state.shrSet,true)),
           curCmd = empty,
           curPtr = 0     % 0 means undefined 
         };
    true 
      -> null
    end.

% ruleset i : NODE do rule "SendGntE"
%   CurCmd = ReqE & CurPtr = i & Chan2[i].Cmd = Empty & ExGntd = false &
%   forall j : NODE do ShrSet[j] = false end
% ==>
%   Chan2[i].Cmd := GntE; Chan2[i].Data := MemData; ShrSet[i] := true;
%   ExGntd := true; CurCmd := Empty; undefine CurPtr;
% end end;
send_gnt_e(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.curCmd) == req_e) and
        (element(I,Ms#murphi_state.curPtr) == I)  and
        (element(I,Ms#murphi_state.chan2) == empty) and
        (element(I,Ms#murphi_state.exGntd) == false))
      -> Ms#murphi_state{
           chan2 = (setelement(I,Ms#murphi_state.chan2,gnt_e)),
           shrSet = (setelement(I,Ms#murphi_state.shrSet,true)),
           exGntd = true,
           curCmd = empty,
           curPtr = 0     % 0 means undefined 
         };
    true 
      -> null
    end.

% ruleset i : NODE do rule "RecvGntS"
%   Chan2[i].Cmd = GntS
% ==>
%   Cache[i].State := S; Cache[i].Data := Chan2[i].Data;
%   Chan2[i].Cmd := Empty; undefine Chan2[i].Data;
% end end;
recv_gnt_s(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.curCmd) == gnt_s))
      -> Ms#murphi_state{
           cache = (setelement(I,Ms#murphi_state.cache,shared)),
           chan2 = (setelement(I,Ms#murphi_state.chan2,empty))
         };
    true 
      -> null
    end.

% ruleset i : NODE do rule "RecvGntE"
%   Chan2[i].Cmd = GntE
% ==>
%   Cache[i].State := E; Cache[i].Data := Chan2[i].Data;
%   Chan2[i].Cmd := Empty; undefine Chan2[i].Data;
% end end;
recv_gnt_e(Ms = #murphi_state{}, I) ->
    if ((element(I,Ms#murphi_state.curCmd) == gnt_e))
      -> Ms#murphi_state{
           cache = (setelement(I,Ms#murphi_state.cache,exclusive)),
           chan2 = (setelement(I,Ms#murphi_state.chan2,empty))
         };
    true 
      -> null
    end.


%start() -> io:format("hello world~n",[]),
%           io:format("hello world 2~n",[]),
%           exit.

