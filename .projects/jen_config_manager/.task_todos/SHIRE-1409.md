# SHIRE-1409 — validate node parameters loaded from disk

Branch: `SHIRE-1409-validate-node-params` (tracks `origin/master`, cut at `b6bcb21`).

## Ticket text

Node parameter validation is currently implemented only for the ROS service
`/config_manager/set_node_parameters`. We want to have the same validation for
parameters that are loaded from disk.

The same validations that run when `set_node_parameters` should be called when
`get_node_parameters` are called (including calling validation services).

Acceptance criteria:

- A failed validation prevents getting the parameters from succeeding.
- A failed validation will result in a degradation of some diagnostic state.
