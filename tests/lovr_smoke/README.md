# Real-LÖVR smoke test

`tests/run_lovr_smoke.sh` stages the runtime, one example asset set, and this
small project into a temporary directory, then runs it with the LÖVR binary
supplied in `LOVR_BIN`.

```bash
LOVR_BIN=/path/to/lovr tests/run_lovr_smoke.sh
```

It loads spineboy, advances the walk animation, renders five frames, checks
that the renderer issued draws and uploaded vertices, prints `LOVR_SMOKE_OK`,
and quits. The script uses `xvfb-run` when available.

GitHub Actions runs this job only via manual `workflow_dispatch` because
hosted Linux runners generally lack a DRI3-capable X/Vulkan display. Run it on
a desktop machine, a self-hosted GPU runner, or a CI runner with a working
Vulkan display. Set `VK_ICD_FILENAMES` to a software or hardware Vulkan ICD if
needed.
