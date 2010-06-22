-record(visited_state, {state, outstandingacks, seqno}).

-record(visited_state_with_degs, {state, outstandingacks, indeg, outdeg}).

-record(state_queue, {state, order}).

-record(alt_state_queue, {order, state}).
