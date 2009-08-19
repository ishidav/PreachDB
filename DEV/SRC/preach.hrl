%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [preach.hrl]
%
%  PackageName                [preach]
%
%  Synopsis                   [Main erl module for Parallel Model Checking]
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

%%%%%%% MACROS #########
-define(BLOOM_N_ENTRIES, 40000000).
-define(BLOOM_ERR_PROB, 0.000001).
-define(CACHE_SIZE, 2048).
-define(CACHE_HIT_INDEX, ?CACHE_SIZE + 10).
-define(PVERSION, 1.0).


%%----------------------------------------------------------------------
%% Function: displayHeader/0, displayOptions/0
%% Purpose : displayOptions should ALWAYS present the status of runtime
%%           options passed to preach. This will help debug and post-
%%           process large number of runs w/ different options passed
%% Args    : 
%%	
%% Returns :
%%     
%%----------------------------------------------------------------------

displayHeader() -> 
    io:format("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%~n~n",[]),
    io:format(" Welcome to PReach - Parallel/Distributed Model Checker v~w~n~n",[?PVERSION]),
    io:format(" Authors: BRAD BINGHAM, FLAVIO M DE PAULA~n~n",[]),
    io:format(" [Copyright (C) 2009 University of British Columbia]~n~n",[]),
    io:format(" Compiled in ~w/~w/~w ~w:~w:~w~n",[
		  element(1,element(1,erlang:localtime())),
		  element(2,element(1,erlang:localtime())),
		  element(3,element(1,erlang:localtime())),
		  element(1,element(2,erlang:localtime())),
		  element(2,element(2,erlang:localtime())),
		  element(3,element(2,erlang:localtime()))]),
    io:format("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%~n~n",[]).

displayOptions() ->
    io:format("------------------------------------------~n",[]),
    io:format("Preach enabled options:~n~n",[]),
    io:format("localmode    [true/false]? ~w~n",[isLocalMode()]),
    io:format("statecaching [true/false]? ~w~n",[isCaching()]),
    io:format("------------------------------------------~n",[]).


%%----------------------------------------------------------------------
%% Function: isLocalMode/0
%% Purpose : Test if -localmode was passed to erl.
%%               
%% Args    :  
%%
%% Returns : true or false 
%%     
%%----------------------------------------------------------------------
isLocalMode() ->
    case  init:get_argument(localmode) of 
	{ok, _Args} ->
            true;
	error ->
            false
    end.

%%----------------------------------------------------------------------
%% Function: isCaching/0
%% Purpose : Test if -statecaching was passed to erl.
%%               
%% Args    :  
%%
%% Returns : true or false 
%%     
%%----------------------------------------------------------------------
isCaching() ->
    case init:get_argument(statecaching) of
	{ok, _Args} ->
            true;
	error ->
            false
    end.
%--------------------------------------------------------------------------------
%                             Revision History
%
%
% $Log: preach.hrl,v $
% Revision 1.1  2009/07/23 16:26:24  depaulfm
% Header file containing macro defns and some util functions
%