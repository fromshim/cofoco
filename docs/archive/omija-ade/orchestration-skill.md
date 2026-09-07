# Archived Omija orchestration skill

> Status: **Superseded** on 2026-09-04. Current direction: [TodoCrew product spec](../../product-spec.md).
> Historical instructions, not an active skill. Do not execute this workflow for TodoCrew V1.
> Renamed from `skill/SKILL.md` so it is not presented as an installable current workflow.
> Original snapshot: Git tag `omija-phase0` (commit `974ca87`).

Original skill metadata and instructions follow; all paths describe the old layout.

---
name: omija
description: Run a coding goal across several isolated worktrees and land the results as one linear history. Use when work splits into independent pieces that different agents can do in parallel, when the user says "omija", "쪼개서 병렬로", "worktree 나눠서", "여러 에이전트로 돌려", "run this across worktrees", or when a change is large enough that one session would serialize it. Orchestrates Orca worktrees and workers, then uses the omija CLI to preview and fast-forward the combined result.
---

# Omija

You plan and judge. The `omija` command owns every git operation that can lose work.

That split is the whole design. Deciding how to cut up a goal needs judgement, so it lives here in prose. Rebasing and fast-forwarding must not be skipped or improvised, so they live in a tested binary with exit codes you branch on. **Never run `git rebase`, `git merge`, or `git push` yourself during a run.**

## Before you start

Check both tools are reachable:

```bash
orca status
omija --help
```

If `omija` is not on PATH, call it as `node <omija-repo>/src/cli.ts`.

## 1. Cut the goal into tasks

One rule decides the split: **do the tasks write to the same files?**

- Different files → separate tasks, run at the same time. Four independent pieces means four tasks.
- Same files → merge them into one task. Do not split work that shares a write scope.
- Genuinely unsure → keep them together. A task that turns out too big is cheaper than a conflict.

For each task write down:

| Field | Meaning |
|---|---|
| id | `[a-z0-9][a-z0-9._-]*`, unique in the run |
| objective | what "done" means, not how to do it |
| write scope | globs the worker may modify, e.g. `apps/api/**` |
| verify | a command that passes only when the task is done |
| agent | `claude` or `codex` |

**Write scopes must not overlap.** If two tasks need the same glob, you cut wrong: go back and merge them.

Pick agents by the profile in `docs/architecture-overview.md` §12. Roughly: Claude for requirement shaping and broad architecture, Codex for narrow implementation, tests, and refactors. Have the other provider review whatever one of them wrote.

Show the user the split before creating anything.

## 2. Freeze the base

```bash
omija preflight --run <run-id> --base main
```

Exit 1 means the working tree is dirty or the ref is unknown. **Report it and stop.** Never stash or discard the user's changes to get past this. The `baseSha` it prints is the commit every lane starts from.

Use the Orca run id as `<run-id>` so the two systems line up.

## 3. Create the run and dispatch workers

```bash
orca orchestration run-create --objective "<goal>" --json
```

Then for each task:

```bash
orca orchestration task-create --run <orca-run-id> --task-title "<task-id>" --spec "<packet>" --json

orca orchestration worker-start --task <task-id> --run <orca-run-id> \
  --worktree new-top-level --agent <claude|codex> --base-branch main --json
```

`worker-start` creates the worktree and starts the agent in one step. `--worktree new-top-level` is what you want: every task branches from the same frozen base. Only use `new-child` when a task genuinely builds on another task's branch, which slice 1 does not support.

Start every task before waiting on any of them. Dispatching one at a time is not parallel.

### The worker packet

`--spec` must contain all of this:

```
목표: <objective>

기준 커밋: <baseSha>
쓰기 범위: <globs>   이 밖의 파일은 건드리지 마라
검증: <verify command>   끝내기 전에 직접 돌려서 통과시켜라

금지: rebase, merge, push, 다른 브랜치 checkout, main 수정
      통합은 코디네이터가 한다

완료 보고: 바꾼 파일 목록, 커밋 subject, 검증 명령 출력
막히면: orca orchestration ask 로 물어라. 범위를 넘겨 짐작하지 마라
```

The scope line is not a courtesy. `omija scope-check` enforces it afterwards, and a worker that ignores it gets its work rejected.

## 4. Wait, then check each result

```bash
orca orchestration worker-read --dispatch <dispatch-id> --json
```

Get each lane's branch from `orca worktree list --json`: match on `path`, read `branch` (it comes back as `refs/heads/<name>`).

For every finished task, in this order:

```bash
omija scope-check --run <run-id> --branch <branch> --allow '<glob>' [--allow '<glob>']
```

Exit 1 means the worker went outside its scope or changed nothing. Send it back with the exact file list from the JSON `outside` field. Do not clean up on its behalf.

Then run the task's verify command in that worktree yourself. The worker claiming it passes is not evidence.

Then:

```bash
omija stage --run <run-id> --task <task-id> --branch <branch>
```

This copies the branch head to a staging ref. The worker's branch is never rewritten, so it stays inspectable if integration goes wrong later.

## 5. Preview the combined history

```bash
omija preview --run <run-id> --order <task-id>,<task-id>
```

Order matters: it is the order commits land on the base. Put foundational work first.

- **Exit 0**: the `graph` field shows exactly what will land. Show it to the user.
- **Exit 2**: conflict. The JSON gives `taskId`, `files`, and `appliedBefore`. Send the conflicting task back to its worker with those files named, then re-run scope-check → stage → preview. **Never resolve the conflict yourself in the integration branch** — it is thrown away on the next preview.

Preview is idempotent and leaves no worktree behind, so re-running it is free.

## 6. Get approval, then land

Show the user the graph and ask. This gate is not optional and not something to infer from earlier approval.

Once approved, with `main` checked out and clean:

```bash
omija apply --run <run-id> --base main
```

Exit 1 with `moved from` means someone else moved `main` since the preview. The graph the user approved no longer describes what would land: re-run `preview`, show the new graph, ask again.

## 7. Clean up

```bash
orca orchestration worker-release --dispatch <dispatch-id>
orca worktree rm --worktree <selector>
```

Remove only lanes that are integrated and clean. Staging refs move to `refs/omija/archive/<run-id>/<task-id>` on apply, so the original work is still reachable after the worktrees are gone.

## Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | success | continue |
| 1 | someone has to fix something | read the JSON detail, fix or send back, retry |
| 2 | integration conflict | send the named task back with the file list |
| 3 | internal failure | stop and show the user; do not retry blindly |

Human-readable text goes to stderr, JSON to stdout. Parse stdout.

## Never

- Run `git rebase`, `git merge`, or `git push` during a run
- Stash, discard, or commit the user's uncommitted changes
- Resolve a conflict inside the integration branch
- Apply without showing the user the previewed graph
- Give two tasks overlapping write scopes
- Let a worker integrate or push its own branch
