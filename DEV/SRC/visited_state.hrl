-record(visited_state, {state, processed}).

-record(visited_state_with_degs, {state, processed, indeg, outdeg}).

-record(state_queue, {state, order}).

-record(alt_state_queue, {order, state}).
