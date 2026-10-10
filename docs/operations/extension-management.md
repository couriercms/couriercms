# Extension Installation and Upgrade

This runbook applies to native Extension packages loaded from the configured
Extension directory, including the supported WordPress and Sanity packages.

## Verified lifecycle drill

The package lifecycle is continuously exercised by:

```text
mix test test/courier_cms/extensions/lifecycle_drill_test.exs
```

The test builds two precompiled versions with one stable Extension/component
identity, then starts three separate clean BEAM VMs. It verifies initial v1
installation, replacement by v2 with a different version and checksum, and
rollback to the exact original v1 package and artifact checksums. Each VM loads
only the package present in the active directory at startup; no hot reload or
production source compilation is used.

This repeatable software drill complements, but does not replace, the deployment
owner's periodic container/VM termination and backup recovery exercises in the
actual hosting environment.

## Preconditions

- Obtain the package from a trusted source.
- Review its version, checksum/signature, compatibility range, capabilities,
  checkpoint classification, and release notes.
- Back up PostgreSQL and the currently installed package.
- Confirm the replacement has the same stable Extension ID.
- Identify affected Connections and Routes.

## Install a new Extension

1. Put the package in a staging location outside `COURIERCMS_EXTENSIONS_PATH`.
2. Load the package on a staging node running the same CourierCMS/Elixir/OTP
   versions. Inspect **System > Extensions** and run:

   ```text
   /app/bin/couriercms rpc "CourierCMS.Release.verify_extensions!()"
   ```

   The command fails if a package was rejected, an active component reference
   cannot be resolved, an unfinished Run's exact artifact is unavailable, or a
   fresh eligible node reports a different Extension artifact set.
3. Stop the node, or keep it stopped before first startup.
4. Move the verified package atomically into the active directory.
5. Start CourierCMS.
6. Inspect startup logs and **System > Extensions**. Confirm the expected ID,
   version, checksum, SDK requirement, application, components, and loaded
   status on this node. Run `CourierCMS.Release.verify_extensions!()` again.
7. Create and test a Connection before activating a Route.

## Upgrade an Extension

1. Pause the affected Routes so no new Runs are planned.
2. Wait for affected planning and delivery jobs to finish. Investigate rather
   than force-killing important in-flight work.
3. Stop every node eligible to execute the Extension.
4. Remove the old package from the active directory and archive it outside that
   directory.
5. Move the verified replacement into the active directory. Never leave two
   packages with the same Extension ID active.
6. Start nodes and verify that all report the same version and checksum.
   System > Extensions must show cluster package consistency before Routes are
   resumed. `/health/ready` reports `extension_set_mismatch` while fresh nodes
   disagree when `COURIERCMS_REQUIRE_EXTENSION_CONSISTENCY=true`.
7. Test representative source and target Connections.
8. If checkpoint compatibility is `requires full baseline`, run a Full Scan
   before enabling incremental discovery.
9. Resume the affected Routes and monitor the first Runs and terminal-failure
   alerts.

The platform and unrelated Routes may remain available on other nodes, but an
affected Route must not run across a mixed Extension version/checksum set. Runs
capture the exact artifact before planning. If queued work encounters a
different installed version, checksum, SDK version, or runtime, it blocks with a
visible compatibility error instead of silently changing code. Fully draining
affected work is still the normal upgrade procedure because only one version of
an Extension ID may be installed at a time.

## Failure and rollback

If the Extension fails to load or misbehaves:

1. keep affected Routes paused;
2. capture the safe load/runtime diagnostics;
3. stop eligible nodes;
4. restore the archived package atomically;
5. restart and verify the old version/checksum; and
6. resume or replay affected work only after compatibility checks pass.

Oban and Run state remain in PostgreSQL. A node restart does not discard queued
work. Restore the exact archived artifact to resume an unfinished Run pinned to
it, or intentionally create a new Run after accepting the replacement artifact.
Do not edit captured Run evidence to bypass this boundary.

## Removal

Do not remove an Extension while enabled Connections, active Routes, unfinished
Runs, or retained retryable jobs reference it. **System > Extensions** shows the
durable reference counts and whether removal is blocked. After disabling and
draining the affected configuration, verify the guard before stopping nodes:

```text
/app/bin/couriercms rpc "CourierCMS.Release.assert_extension_removable!(\"com.example.extension\")"
```

The command is read-only and raises while an active or unfinished reference
exists. Historical disabled Connections and Routes remain in PostgreSQL and are
still shown, but do not by themselves prevent removing the package.

## Multi-node check

The screen reports the registry of the node serving the request. Before an
upgrade, repeat the verification command on every web or worker node eligible
to validate or execute the Extension. Fresh node heartbeats are compared
automatically using a deterministic fingerprint and displayed in the cluster
consistency table. Wait up to the heartbeat freshness window after retiring an
old node, or remove its stale heartbeat through the normal retention process.

During a controlled rolling restart, a temporary mismatch is expected. Keep
affected Routes paused until all eligible nodes agree. If an affected job lands
on an incompatible worker, its pinned artifact check prevents execution rather
than silently using the new code; unrelated Routes whose artifacts are present
remain operable.
