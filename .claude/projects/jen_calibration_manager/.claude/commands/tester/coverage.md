---
description: Report per-file gcov coverage for jen_calibration_manager sources
allowed-tools: Bash(docker run:*), Read
---

Per-file coverage from the `tester` image (build it with `/tester:run` first).

Do **not** report the aggregate over every `.gcov` — it includes all ROS
headers and reads ~18%, which is meaningless. Use the per-file view:

```bash
docker run --rm --entrypoint python3 jen_calibration_manager_build:latest -c "
import glob
for f in sorted(glob.glob('/ros2_ws/gcov/*.gcov')):
    name = f.split('/')[-1]
    if name.endswith('Test.cpp.gcov'): continue
    if not any(k in name for k in ['Calibration','Validat','Publisher','CameraInfo']): continue
    counts = [l.split(':',1)[0].strip() for l in open(f, errors='ignore')]
    hit = sum(1 for c in counts if c.isdigit()); tot = hit + sum(1 for c in counts if c=='#####')
    if tot: print(f'{name}: {hit}/{tot} ({100*hit/tot:.0f}%)')
"
```

Compare against the last measured baseline in the `tester` skill and call out
anything that dropped. `ValidationVisitor.hpp` reads low because header
instantiations are counted once per object file — ignore it, and judge the
visitors by `ValidationVisitorTest` instead.
