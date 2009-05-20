--$Id: dek_modified.m,v 1.2 2009/05/20 17:34:32 depaulfm Exp $
--------------------------------------------------------------------------------
-- LICENSE AGREEMENT
--
-- FileName                   [dek_modified.m]
--
-- PackageName                [preach]
--
-- Synopsis                   [This is a modified version of dek.m             ]
--                            [It replaces procedure and for loops w/ inline   ]
--                            [constructs. It comments out invariant           ]
--
-- Author                     [BRAD BINGHAM, FLAVIO M DE PAULA]
--
-- Copyright                  [Copyright (C) 2009 University of British Columbia]
--
-- This program is free software; you can redistribute it and/or modify
--it under the terms of the GNU General Public License as published by
--the Free Software Foundation; either version 2 of the License, or
--(at your option) any later version.
--
--This program is distributed in the hope that it will be useful,
--but WITHOUT ANY WARRANTY; without even the implied warranty of
--MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--GNU General Public License for more details.
--
--You should have received a copy of the GNU General Public License
--along with this program; if not, write to the Free Software
--Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
---------------------------------------------------------------------------------

------------------------------------------------------------------------
-- Copyright (C) 1992, 1993 by the Board of Trustees of 		 
-- Leland Stanford Junior University.					 
--									 
-- This description is provided to serve as an example of the use	 
-- of the Murphi description language and verifier, and as a benchmark	 
-- example for other verification efforts.				 
--									 
-- License to use, copy, modify, sell and/or distribute this description 
-- and its documentation any purpose is hereby granted without royalty,  
-- subject to the following terms and conditions, provided		 
--									 
-- 1.  The above copyright notice and this permission notice must	 
-- appear in all copies of this description.				 
-- 									 
-- 2.  The Murphi group at Stanford University must be acknowledged	 
-- in any publication describing work that makes use of this example. 	 
-- 									 
-- Nobody vouches for the accuracy or usefulness of this description	 
-- for any purpose.							 
-------------------------------------------------------------------------

----------------------------------------------------------------------
-- Filename:	dek.m
-- Version:	Murphi 2.3
-- Content: 	Dekker's algorithm for mutual exclusion.
--		Satisfies all conditions for a correct solution.
-- Last modification:
--              modified 8/25/92 by Ralph Melton for Murphi 2.3
----------------------------------------------------------------------

Type
	ind_t :	0..1;
	label_t : Enum { init, whileOtherLocked, checkTurn, unlock, waitForTurn, lockAndRetry, crit, exitCrit };
	lock_t : Enum { locked, unlocked };

Var
	s :	Array[ ind_t ] Of label_t;
	c :	Array[ ind_t ] Of lock_t;
	turn :	0..1;


Ruleset p : ind_t Do

	Rule "Init"
		s[p] = init
	==>
	Begin
		c[p] := locked;
	        s[ p ] := whileOtherLocked;
	End;

	Rule "WhileOtherLocked"			-- While c[1-p]=locked
		s[p] = whileOtherLocked
	==>
	Begin
		If c[1-p] = unlocked Then
                        s[ p ] := crit;
		Else
                        s[ p ] := checkTurn;
		End;
	End;

	Rule "CheckTurn"
		s[p] = checkTurn
	==>
	Begin
		If turn = 1-p Then
                        s[ p ] := unlock; 
		Else
                        s[ p ] := whileOtherLocked;
		End;
	End;

	Rule "Unlock"
		s[p] = unlock
	==>
	Begin
		c[p]:=unlocked;
                s[ p ] := waitForTurn;
	End;

	Rule "WaitForTurn"			-- Repeat until turn=p
		s[p] = waitForTurn
	==>
	Begin
		If turn != p Then
                         s[ p ] := lockAndRetry;
		End;
	End;

	Rule "LockAndRetry"
		s[p] = lockAndRetry
	==>
	Begin
		c[p] := locked;
                s[ p ] := whileOtherLocked;
	End;

	Rule "Crit"
		s[p] = crit
	==>
	Begin
                 s[ p ] := exitCrit;
	End;

	Rule "ExitCrit"
		s[p] = exitCrit
	==>
	Begin
		c[p] := unlocked;
		turn := 1-p;
                s[ p ] := init;
	End;

End;



Startstate
  Begin
        s[ 0 ] := init; 
        s[ 1 ] := init; 
	c[ 0 ] := unlocked;
	c[ 1 ] := unlocked;
	turn := 0;
End;

--Invariant
--	!( s[0] = crit & s[1] = crit );
