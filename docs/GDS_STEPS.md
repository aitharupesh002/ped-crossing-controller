# Getting the GDS (GitHub Actions, no local install)

1. On github.com click **New repository** → name e.g. `ped-crossing-controller` → **Public** → Create (do not add README).
2. Upload ALL files of this folder to the repo root (including the hidden `.github` folder), or push with git:
   ```bash
   cd <this folder>
   git init && git add -A && git commit -m "Pedestrian crossing controller"
   git branch -M main
   git remote add origin https://github.com/<your-username>/ped-crossing-controller.git
   git push -u origin main
   ```
3. Open the **Actions** tab. If asked, click "I understand my workflows, go ahead and enable them".
4. Wait for the `gds` workflow (about 5–15 minutes). A green tick means the GDS was generated.
5. Open the finished `gds` run → **Artifacts** → download `tt_submission` / `gds` (contains `*.gds`, `*.lef`, netlist, reports: area, timing, DRC, LVS).
6. Settings → Pages → Source: **GitHub Actions** (optional) to get the interactive 3D layout viewer from the `viewer` job.
7. If a job fails, open it, copy the red error lines and send them to me — I will diagnose the actual error.
