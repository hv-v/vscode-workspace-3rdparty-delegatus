# SHIRE-1409 — design notes and status

Ticket text: [../.task_todos/SHIRE-1409.md](../.task_todos/SHIRE-1409.md).
Branch: `SHIRE-1409-validate-node-params`. Uncommitted at time of writing.

## What changed

| file | change |
|---|---|
| `config_manager/src/node_config.cpp` | new private `NodeConfig::runValidations(property, param)`, the validation loop taken out of `validateParameters`. `readParameters` calls it on every value loaded from disk that is requested and has matching writability. `validateParameters` keeps not-found → not-writable → type, then calls it. |
| `config_manager/include/jen_config_manager/node_config.hpp` | declares `runValidations`; adds `@throws ValidationError` to the `readParameters` doc |
| `config_manager/src/config_manager.cpp` | `handleGetNodeParameters` gets a `catch (const ValidationError&)`: log `get-parameters-invalid`, set the per-node `get_node_parameters` diagnostic to `ERROR`, clear the parameters, return error code `VALIDATION` |
| `README.md` | new section "Validating stored parameters" |
| `config_manager/test/test_config_manager.cpp`, `test_node_config.cpp` | 19 new tests. `GetParametersWithServiceValidationSucceeds` is replaced by `…FailsWhenServiceNotReady`, because the old test asserted the opposite of this ticket. |

## Decisions

- **Only values loaded from disk are validated, not schema `default_value`s.**
  The ticket says "parameters that are loaded from disk". Validating defaults
  would also make every node with a service-validated default depend on its
  validator, even when nothing is stored. Today `loadSchema` accepts a default
  outside its own range, and such a default is still returned.
- **The type is not re-checked on the read path.** `ParamsParser::parseParamsBlock`
  already converts every value to the schema type, or throws.
- **Writable and read-only values are both validated.** Writability is checked
  only on the set path.
- **Unrequested parameters are not validated.** A get that names
  `parameter_names` validates only those parameters.
- **The diagnostic that degrades is `<diagnostics.node_config_prefix>/get_node_parameters<node>`.**
  It goes to `ERROR` and returns to `OK` on the next successful get for that
  node. The manager-health task counts the node under "failed configs" but
  stays `OK`, the same behaviour as the existing checksum or schema failures.

## Resolved: crash in the running node (SHIRE-1766)

- **Before the merge, service validation aborted the running config manager.**
  On the branch head, under `rclcpp::spin`, it failed with `Node
  '/jen_config_manager' has already been added to an executor`. Both get and
  set were affected; set already did this on master.
- **SHIRE-1766 is now on master.** It adds a MultiThreadedExecutor, a
  validation callback group and a `future.wait_for(5s)`. On 2026-10-16, master
  was merged into this branch locally as `9537b16`.
- **The 2026-10-15 Jenkins "Tests failed" came from three tests:**
  `GetNodeParametersTest.GetParametersService{ValidSucceeds,ReceivesValue,InvalidFails}`.
  Each ran 5008 ms and failed. They called the handler with nothing spinning
  the node, which worked with the old `spin_until_future_complete` but not with
  `wait_for`. The branch head alone still passed, so Jenkins tested the merge.
  These three tests now run the handler with `std::async` and spin the node on
  the test thread with `rclcpp::spin_until_future_complete`. This was a
  test-only change. An earlier `BackgroundSpinner` class was replaced by this
  simpler form. Each test takes about 1 s, because only the diagnostic timer
  wakes the spin.
- **End-to-end check after the merge passed.** The real node ran in the tester
  image with a Python validator on `/validator/validate`:
  - stored `"bad"` → error code 8, and diagnostic
    `system/configuration/get_node_parameters/demo` at level 2 (`ERROR`)
  - stored `"good"` → the parameter is returned with error code 0
  - the process stayed alive

## Verification

After the merge and test fix (2026-10-16):

- `docker build --target tester` → `[  PASSED  ] 260 tests`. Log:
  `../.errors/SHIRE-1409_ci_fix_async.log`.
- The full suite with `--gtest_repeat=20` passed 20 out of 20 runs.
- Reproduction logs for the Jenkins failure: `../.errors/SHIRE-1409_ci_head.log`
  (head alone, green) and `../.errors/SHIRE-1409_ci_merged.log` (merged, 3
  failed).

Before the merge (2026-10-14):

- Ran `docker build --target tester`. Result: `[  PASSED  ] 260 tests`,
  `100% tests passed`. Log: `../.errors/SHIRE-1409_tester_build.log`.
- Ran `GetNodeParametersTest.*:ReadParametersTest.*:SetParametersTest.*:SetNodeParametersTest.*`
  with `--gtest_repeat=10`: passed 10 out of 10 runs.
- `cpp-verifier` reported clang-format clean and naming clean. Its only
  blocking item is the SHIRE-1766 crash above.
