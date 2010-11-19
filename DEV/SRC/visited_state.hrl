-define(DBHTNAME, visited_state).
-define(DBSQNAME, state_queue).

-record(visited_state, {state, parent}).

-record(visited_state_with_degs, {state, outstandingacks, indeg, outdeg}).

-record(state_queue, {state, order}).

-record(alt_state_queue, {order, state}).
