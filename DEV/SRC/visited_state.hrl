-record(visited_state, {state, processed}).

-record(visited_state_with_degs, {state, processed, indeg, outdeg}).

-record(state_queue, {order, state}).

-record(alt_state_queue, {state, order}).
