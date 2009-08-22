-module(german3).

%
% Exports the main routines defined in preach.erl
%
-export([start/0,autoStart/0,startWorker/1]).

stateToBits(State) -> State.
bitsToState(Bits) -> Bits.
stateMatch(State, Pattern) -> false.



%%----------------------------------------------------------------------
%% 
%% Purpose : Includes the model checker module
%%				
%% Requires: Environment variable PREACH_PATH to be set pointing to
%%	     preach's root directory
%%
-include("$PREACH_PATH/DEV/SRC/preach.erl").

%%%% higher order functions for handling for loops and quantifiers %%%%

forloop0(X,[H|T],B) -> B(H,(forloop0(X,T,B)));
forloop0(X,[],B) -> X.
forloop(X,F,T,B) -> forloop0(X,(lists:seq(T,F,-1)),B).
% forall([e1,e2,...,ek],F) = F(e1) and F(e2) and ... and F(ek)
forall(L,F) -> lists:foldl(fun(X,Y) -> F(X) and Y end,true , L).
% exists([e1,e2,...,ek],F) = F(e1) or  F(e2) or  ... or  F(ek)
exists(L,F) -> lists:foldl(fun(X,Y) -> F(X) or  Y end,false, L).

%%%%%%%  data type declarations %%%%%%%

-record( cACHE, {
   state,
   data
}).
cACHE_undefined() -> #cACHE{
   state = undefined,
   data = undefined
}.
-record( mSG, {
   cmd,
   data
}).
mSG_undefined() -> #mSG{
   cmd = undefined,
   data = undefined
}.
-record(ms, {
   auxData,
   memData,
   curPtr,
   curCmd,
   exGntd,
   shrSet,
   invSet,
   chan3,
   chan2,
   chan1,
   cache
}).
ms_undefined() -> #ms{
   auxData = undefined,
   memData = undefined,
   curPtr = undefined,
   curCmd = undefined,
   exGntd = undefined,
   shrSet = {undefined,undefined,undefined},
   invSet = {undefined,undefined,undefined},
   chan3 = {mSG_undefined(),mSG_undefined(),mSG_undefined()},
   chan2 = {mSG_undefined(),mSG_undefined(),mSG_undefined()},
   chan1 = {mSG_undefined(),mSG_undefined(),mSG_undefined()},
   cache = {cACHE_undefined(),cACHE_undefined(),cACHE_undefined()}
}.

%%%%%%%  procedure/function declarations %%%%%%%


%%%%%%%  start states %%%%%%%


init(MS_0 = #ms{},D) ->
      MS_1 = forloop(MS_0,1,3,fun(I,MS_0_0=#ms{}) ->
         MS_0_1 = MS_0_0#ms{chan1 = setelement(I,MS_0_0#ms.chan1,(element(I,MS_0_0#ms.chan1))#mSG{cmd = empty})},
         MS_0_2 = MS_0_1#ms{chan2 = setelement(I,MS_0_1#ms.chan2,(element(I,MS_0_1#ms.chan2))#mSG{cmd = empty})},
         MS_0_3 = MS_0_2#ms{chan3 = setelement(I,MS_0_2#ms.chan3,(element(I,MS_0_2#ms.chan3))#mSG{cmd = empty})},
         MS_0_4 = MS_0_3#ms{cache = setelement(I,MS_0_3#ms.cache,(element(I,MS_0_3#ms.cache))#cACHE{state = invalid})},
         MS_0_5 = MS_0_4#ms{invSet = setelement(I,MS_0_4#ms.invSet,false)},
         MS_0_6 = MS_0_5#ms{shrSet = setelement(I,MS_0_5#ms.shrSet,false)},
         MS_0_6 end
      ),
      MS_2 = MS_1#ms{exGntd = false},
      MS_3 = MS_2#ms{curCmd = empty},
      MS_4 = MS_3#ms{memData = D},
      MS_5 = MS_4#ms{auxData = D},
      MS_5
.


%%%%%%%  rules %%%%%%%


recvGntE_guard(MS_0 = #ms{},I) ->
   (((element(I,MS_0#ms.chan2))#mSG.cmd)) == (gntE)
.

recvGntE(MS_0 = #ms{},I) ->
   G = recvGntE_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{cache = setelement(I,MS_0#ms.cache,(element(I,MS_0#ms.cache))#cACHE{state = exclusive})},
      MS_2 = MS_1#ms{cache = setelement(I,MS_1#ms.cache,(element(I,MS_1#ms.cache))#cACHE{data = ((element(I,MS_1#ms.chan2))#mSG.data)})},
      MS_3 = MS_2#ms{chan2 = setelement(I,MS_2#ms.chan2,(element(I,MS_2#ms.chan2))#mSG{cmd = empty})},
      MS_4 = MS_3#ms{chan2 = setelement(I,MS_3#ms.chan2,(element(I,MS_3#ms.chan2))#mSG{data = undefined})},
      MS_4;
   true -> null
end.


recvGntS_guard(MS_0 = #ms{},I) ->
   (((element(I,MS_0#ms.chan2))#mSG.cmd)) == (gntS)
.

recvGntS(MS_0 = #ms{},I) ->
   G = recvGntS_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{cache = setelement(I,MS_0#ms.cache,(element(I,MS_0#ms.cache))#cACHE{state = shared})},
      MS_2 = MS_1#ms{cache = setelement(I,MS_1#ms.cache,(element(I,MS_1#ms.cache))#cACHE{data = ((element(I,MS_1#ms.chan2))#mSG.data)})},
      MS_3 = MS_2#ms{chan2 = setelement(I,MS_2#ms.chan2,(element(I,MS_2#ms.chan2))#mSG{cmd = empty})},
      MS_4 = MS_3#ms{chan2 = setelement(I,MS_3#ms.chan2,(element(I,MS_3#ms.chan2))#mSG{data = undefined})},
      MS_4;
   true -> null
end.


sendGntE_guard(MS_0 = #ms{},I) ->
   (((((((((MS_0#ms.curCmd) == (reqE)) and ((MS_0#ms.curPtr) == (I)))) and ((((element(I,MS_0#ms.chan2))#mSG.cmd)) == (empty)))) and ((MS_0#ms.exGntd) == (false)))) and (forall(lists:seq(1,3), fun(J) -> ((element(J,MS_0#ms.shrSet))) == (false) end)))
.

sendGntE(MS_0 = #ms{},I) ->
   G = sendGntE_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{chan2 = setelement(I,MS_0#ms.chan2,(element(I,MS_0#ms.chan2))#mSG{cmd = gntE})},
      MS_2 = MS_1#ms{chan2 = setelement(I,MS_1#ms.chan2,(element(I,MS_1#ms.chan2))#mSG{data = MS_1#ms.memData})},
      MS_3 = MS_2#ms{shrSet = setelement(I,MS_2#ms.shrSet,true)},
      MS_4 = MS_3#ms{exGntd = true},
      MS_5 = MS_4#ms{curCmd = empty},
      MS_6 = MS_5#ms{curPtr = undefined},
      MS_6;
   true -> null
end.


sendGntS_guard(MS_0 = #ms{},I) ->
   (((((((MS_0#ms.curCmd) == (reqS)) and ((MS_0#ms.curPtr) == (I)))) and ((((element(I,MS_0#ms.chan2))#mSG.cmd)) == (empty)))) and ((MS_0#ms.exGntd) == (false)))
.

sendGntS(MS_0 = #ms{},I) ->
   G = sendGntS_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{chan2 = setelement(I,MS_0#ms.chan2,(element(I,MS_0#ms.chan2))#mSG{cmd = gntS})},
      MS_2 = MS_1#ms{chan2 = setelement(I,MS_1#ms.chan2,(element(I,MS_1#ms.chan2))#mSG{data = MS_1#ms.memData})},
      MS_3 = MS_2#ms{shrSet = setelement(I,MS_2#ms.shrSet,true)},
      MS_4 = MS_3#ms{curCmd = empty},
      MS_5 = MS_4#ms{curPtr = undefined},
      MS_5;
   true -> null
end.


recvInvAck_guard(MS_0 = #ms{},I) ->
   (((((element(I,MS_0#ms.chan3))#mSG.cmd)) == (invAck)) and (not ((MS_0#ms.curCmd) == (empty))))
.

recvInvAck(MS_0 = #ms{},I) ->
   G = recvInvAck_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{chan3 = setelement(I,MS_0#ms.chan3,(element(I,MS_0#ms.chan3))#mSG{cmd = empty})},
      MS_2 = MS_1#ms{shrSet = setelement(I,MS_1#ms.shrSet,false)},
      MS_2_0 = MS_2,
      MS_3 = if ((MS_2#ms.exGntd) == (true)) ->
         MS_2_1 = MS_2_0#ms{exGntd = false},
         MS_2_2 = MS_2_1#ms{memData = ((element(I,MS_2_1#ms.chan3))#mSG.data)},
         MS_2_3 = MS_2_2#ms{chan3 = setelement(I,MS_2_2#ms.chan3,(element(I,MS_2_2#ms.chan3))#mSG{data = undefined})},
         MS_2_3;
         true -> MS_2 end,
      MS_3;
   true -> null
end.


sendInvAck_guard(MS_0 = #ms{},I) ->
   (((((element(I,MS_0#ms.chan2))#mSG.cmd)) == (inv)) and ((((element(I,MS_0#ms.chan3))#mSG.cmd)) == (empty)))
.

sendInvAck(MS_0 = #ms{},I) ->
   G = sendInvAck_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{chan2 = setelement(I,MS_0#ms.chan2,(element(I,MS_0#ms.chan2))#mSG{cmd = empty})},
      MS_2 = MS_1#ms{chan3 = setelement(I,MS_1#ms.chan3,(element(I,MS_1#ms.chan3))#mSG{cmd = invAck})},
      MS_2_0 = MS_2,
      MS_3 = if ((((element(I,MS_2#ms.cache))#cACHE.state)) == (exclusive)) ->
         MS_2_1 = MS_2_0#ms{chan3 = setelement(I,MS_2_0#ms.chan3,(element(I,MS_2_0#ms.chan3))#mSG{data = ((element(I,MS_2_0#ms.cache))#cACHE.data)})},
         MS_2_1;
         true -> MS_2 end,
      MS_4 = MS_3#ms{cache = setelement(I,MS_3#ms.cache,(element(I,MS_3#ms.cache))#cACHE{state = invalid})},
      MS_5 = MS_4#ms{cache = setelement(I,MS_4#ms.cache,(element(I,MS_4#ms.cache))#cACHE{data = undefined})},
      MS_5;
   true -> null
end.


sendInv_guard(MS_0 = #ms{},I) ->
   (((((((element(I,MS_0#ms.chan2))#mSG.cmd)) == (empty)) and (((element(I,MS_0#ms.invSet))) == (true)))) and ((((MS_0#ms.curCmd) == (reqE)) or ((((MS_0#ms.curCmd) == (reqS)) and ((MS_0#ms.exGntd) == (true)))))))
.

sendInv(MS_0 = #ms{},I) ->
   G = sendInv_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{chan2 = setelement(I,MS_0#ms.chan2,(element(I,MS_0#ms.chan2))#mSG{cmd = inv})},
      MS_2 = MS_1#ms{invSet = setelement(I,MS_1#ms.invSet,false)},
      MS_2;
   true -> null
end.


recvReqE_guard(MS_0 = #ms{},I) ->
   (((MS_0#ms.curCmd) == (empty)) and ((((element(I,MS_0#ms.chan1))#mSG.cmd)) == (reqE)))
.

recvReqE(MS_0 = #ms{},I) ->
   G = recvReqE_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{curCmd = reqE},
      MS_2 = MS_1#ms{curPtr = I},
      MS_3 = MS_2#ms{chan1 = setelement(I,MS_2#ms.chan1,(element(I,MS_2#ms.chan1))#mSG{cmd = empty})},
      MS_4 = forloop(MS_3,1,3,fun(J,MS_3_0=#ms{}) ->
         MS_3_1 = MS_3_0#ms{invSet = setelement(J,MS_3_0#ms.invSet,(element(J,MS_3_0#ms.shrSet)))},
         MS_3_1 end
      ),
      MS_4;
   true -> null
end.


recvReqS_guard(MS_0 = #ms{},I) ->
   (((MS_0#ms.curCmd) == (empty)) and ((((element(I,MS_0#ms.chan1))#mSG.cmd)) == (reqS)))
.

recvReqS(MS_0 = #ms{},I) ->
   G = recvReqS_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{curCmd = reqS},
      MS_2 = MS_1#ms{curPtr = I},
      MS_3 = MS_2#ms{chan1 = setelement(I,MS_2#ms.chan1,(element(I,MS_2#ms.chan1))#mSG{cmd = empty})},
      MS_4 = forloop(MS_3,1,3,fun(J,MS_3_0=#ms{}) ->
         MS_3_1 = MS_3_0#ms{invSet = setelement(J,MS_3_0#ms.invSet,(element(J,MS_3_0#ms.shrSet)))},
         MS_3_1 end
      ),
      MS_4;
   true -> null
end.


sendReqE_guard(MS_0 = #ms{},I) ->
   (((((element(I,MS_0#ms.chan1))#mSG.cmd)) == (empty)) and ((((((element(I,MS_0#ms.cache))#cACHE.state)) == (invalid)) or ((((element(I,MS_0#ms.cache))#cACHE.state)) == (shared)))))
.

sendReqE(MS_0 = #ms{},I) ->
   G = sendReqE_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{chan1 = setelement(I,MS_0#ms.chan1,(element(I,MS_0#ms.chan1))#mSG{cmd = reqE})},
      MS_1;
   true -> null
end.


sendReqS_guard(MS_0 = #ms{},I) ->
   (((((element(I,MS_0#ms.chan1))#mSG.cmd)) == (empty)) and ((((element(I,MS_0#ms.cache))#cACHE.state)) == (invalid)))
.

sendReqS(MS_0 = #ms{},I) ->
   G = sendReqS_guard(MS_0,I),
   if (G) ->
      MS_1 = MS_0#ms{chan1 = setelement(I,MS_0#ms.chan1,(element(I,MS_0#ms.chan1))#mSG{cmd = reqS})},
      MS_1;
   true -> null
end.


store_guard(MS_0 = #ms{},D,I) ->
   (((element(I,MS_0#ms.cache))#cACHE.state)) == (exclusive)
.

store(MS_0 = #ms{},D,I) ->
   G = store_guard(MS_0,D,I),
   if (G) ->
      MS_1 = MS_0#ms{cache = setelement(I,MS_0#ms.cache,(element(I,MS_0#ms.cache))#cACHE{data = D})},
      MS_2 = MS_1#ms{auxData = D},
      MS_2;
   true -> null
end.

startstates0() -> [
   init(ms_undefined(), 1),
   init(ms_undefined(), 2),
   null
].

startstates() ->
   T = startstates0(),
   [X || X <- T, X /= null]
.
transition0(MS) -> [
   recvGntE(MS, 1),
   recvGntE(MS, 2),
   recvGntE(MS, 3),
   recvGntS(MS, 1),
   recvGntS(MS, 2),
   recvGntS(MS, 3),
   sendGntE(MS, 1),
   sendGntE(MS, 2),
   sendGntE(MS, 3),
   sendGntS(MS, 1),
   sendGntS(MS, 2),
   sendGntS(MS, 3),
   recvInvAck(MS, 1),
   recvInvAck(MS, 2),
   recvInvAck(MS, 3),
   sendInvAck(MS, 1),
   sendInvAck(MS, 2),
   sendInvAck(MS, 3),
   sendInv(MS, 1),
   sendInv(MS, 2),
   sendInv(MS, 3),
   recvReqE(MS, 1),
   recvReqE(MS, 2),
   recvReqE(MS, 3),
   recvReqS(MS, 1),
   recvReqS(MS, 2),
   recvReqS(MS, 3),
   sendReqE(MS, 1),
   sendReqE(MS, 2),
   sendReqE(MS, 3),
   sendReqS(MS, 1),
   sendReqS(MS, 2),
   sendReqS(MS, 3),
   store(MS, 1, 1),
   store(MS, 2, 1),
   store(MS, 1, 2),
   store(MS, 2, 2),
   store(MS, 1, 3),
   store(MS, 2, 3),
   null
].

transition(MS) ->
   T = transition0(MS),
   [X || X <- T, X /= null]
.
