%--------------------------------------------------------------------------------
% LICENSE AGREEMENT
%
%  FileName                   [preach.hrl]
%
%  PackageName                [preach]
%
%  Synopsis                   [Main erl module for Parallel Model Checking]
%
%  Author                     [BRAD BINGHAM, FLAVIO M DE PAULA, VALERIE ISHIDA]
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
-define(PVERSION, 0.5).


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
    io:format(" Welcome to PReachDB - Parallel/Distributed Model Checker~n", []),
    io:format(" Version ~w~n",[?PVERSION]),
    io:format(" Author: VALERIE ISHIDA~n~n",[]),
    io:format(" Based on (UBC) PReach written by~n",[]),
    io:format(" PReach Authors: BRAD BINGHAM, FLAVIO M DE PAULA~n~n",[]),
    io:format(" [Copyright (C) 2010 University of British Columbia]~n~n",[]),
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
    io:format("PreachDB enabled options:~n~n",[]),
    io:format("sname        ~s~n",[getSname()]),
    io:format("is root      [true/false]? ~w~n",[amIRoot()]),
    io:format("localmode    [true/false]? ~w~n",[isLocalMode()]),
    io:format("mnesia       [true/false]? ~w~n",[isUsingMnesia()]),
    io:format("mnesia dir   ~s~n",[getMnesiaDir()]),
    io:format("cwd          ~s~n",[element(2, file:get_cwd())]),
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
%% Function: isUsingMnesia/0
%% Purpose : Test if -mnesia dir was passed to erl.
%%               
%% Args    :  
%%
%% Returns : true or false 
%%     
%%----------------------------------------------------------------------
isUsingMnesia() ->     
    case init:get_argument(mnesia) of
	{ok, _Args} ->
            true;
	error ->
            false
    end.

%%----------------------------------------------------------------------
%% Function: getMnesiaDir/0
%% Purpose : Return the PATH of Mnesia data
%%               
%% Args    :  
%%
%% Returns : string
%%     
%%----------------------------------------------------------------------
getMnesiaDir() ->     
    case init:get_argument(mnesia) of
	{ok, [[_, Path]]} ->
            Path;
	true ->
            ""
    end.

%%----------------------------------------------------------------------
%% Function: getSname/0
%% Purpose : Return the sname commandline arg
%%               
%% Args    :  
%%
%% Returns : string
%%     
%%----------------------------------------------------------------------
getSname() ->     
    case init:get_argument(sname) of
	{ok, [[Path]]} ->
            Path;
	true ->
            ""
    end.

%%----------------------------------------------------------------------
%% Function: amIRoot/0
%% Purpose : check if I'm root based on my sname
%%               
%% Args    :  
%%
%% Returns : boolean
%%     
%%----------------------------------------------------------------------
amIRoot() ->     
    MySname = getSname(),
    string:equal(MySname, "pruser0").
