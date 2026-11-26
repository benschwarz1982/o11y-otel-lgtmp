# Runbook: 1286-linux-basis-hostcpuhigh (Remediation)

This runbook is executed automatically when an alert with
`Runbook-Key: 1286-linux-basis-hostcpuhigh` fires (`1286 Linux Basis -
host CPU > 80%`, `vm-rocky-demo`).

This demo's CPU saturation is always caused by the same intentional
cause: two CPU-spin loops (`while :; do :; done`) started on the VM for
demonstration purposes (the same mechanism `demo:uc1-break` in
`.gitlab-ci.yml` uses), tracked in `/tmp/demo-uc1-cpu.pids`.

⚠️ The agent is authorized to automatically execute all steps listed below WITHOUT further confirmation.

## Authorized Steps for the Agent:

1. **Verify the System:**
```bash
top -bn1 | head -20
```

2. **Identify the Cause:**
```bash
cat /tmp/demo-uc1-cpu.pids 2>/dev/null
```

3. **Targeted Cleanup:**

`demo:uc1-break` starts these loops via `az vm run-command` (as root on
the VM), while remediation connects over SSH as the unprivileged
`openclaw` user. Its only sudo permission is this one wrapper, which
kills exactly the PIDs recorded in `/tmp/demo-uc1-cpu.pids` - and only
if each is still a root-owned `while :; do :; done` loop - verifies
they are gone and removes the pid file (F07). No arguments; any other
`sudo` command is denied.

Found live, and still important: never use `pgrep -f`/`pkill -f` with
a text pattern in this runbook. The entire step is sent to the remote
shell as one `bash -c "..."` string, so that shell's own command line
contains the pattern too - `pkill -f` then **sends SIGTERM to the shell
running your own SSH session** (`Command exited with code 255`).

```bash
sudo /usr/local/sbin/demo-uc1-stop
```

4. **Verify Success:**

Checks each recorded PID via `/proc/<pid>` (works without privileges,
unlike `kill -0` against a root-owned process). The wrapper in step 3
removes the pid file once every loop is gone.

```bash
still_running=0
if [ -f /tmp/demo-uc1-cpu.pids ]; then
  while read -r pid; do
    [ -n "$pid" ] && [ -d "/proc/$pid" ] && still_running=1
  done < /tmp/demo-uc1-cpu.pids
fi
if [ "$still_running" = "1" ]; then
  echo "WARNING: a CPU-spin loop is still running after kill attempts"
else
  echo "stopped - verified no CPU-spin loop remains"
fi
top -bn1 | head -20
```

5. **Completion:**
Print the final `top` output in the chat, confirming CPU usage has
dropped back to normal. Your success/failure statement here must
match step 4's own output exactly, re-run just now - never restate an
earlier step's result as the current outcome. If step 4 printed the
WARNING line, report clearly that remediation was incomplete and
propose next steps; otherwise report clearly that it succeeded.
