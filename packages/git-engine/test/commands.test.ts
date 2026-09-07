import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { apply } from '../src/commands/apply.ts'
import { preflight } from '../src/commands/preflight.ts'
import { preview } from '../src/commands/preview.ts'
import { scopeCheck } from '../src/commands/scope-check.ts'
import { stage } from '../src/commands/stage.ts'
import { OmijaError } from '../src/error.ts'
import { tryRevParse } from '../src/git.ts'
import { archiveRef, integrationRef, stagingRef } from '../src/refs.ts'
import { type Fixture, makeRepo, taskBranch } from './fixture.ts'

/** Extra worktrees beyond the fixture's own checkout. Preview must leave none. */
function worktreePaths(repo: Fixture): string[] {
  return repo
    .git('worktree', 'list', '--porcelain')
    .split('\n')
    .filter((line) => line.startsWith('worktree '))
    .map((line) => line.slice('worktree '.length))
    .slice(1)
}

/** Assert that `fn` throws an OmijaError with the expected exit code. */
function throwsWith(code: 1 | 2 | 3, fn: () => unknown): OmijaError {
  try {
    fn()
  } catch (cause) {
    assert.ok(cause instanceof OmijaError, `expected OmijaError, got ${String(cause)}`)
    assert.equal(cause.code, code, `expected exit ${code}, got ${cause.code}: ${cause.message}`)
    return cause
  }
  throw new assert.AssertionError({ message: `expected a failure with exit ${code}` })
}

describe('preflight', () => {
  let repo: Fixture
  before(() => { repo = makeRepo() })
  after(() => repo.cleanup())

  test('freezes the base sha', () => {
    const result = preflight(repo.path, 'run-1', 'main')
    assert.equal(result.baseSha, repo.sha('main'))
    assert.equal(tryRevParse(repo.path, 'refs/omija/base/run-1'), result.baseSha)
  })

  test('is idempotent while the base has not moved', () => {
    const again = preflight(repo.path, 'run-1', 'main')
    assert.equal(again.baseSha, repo.sha('main'))
  })

  test('refuses a second base for the same run', () => {
    repo.write('moved.txt', 'x\n')
    repo.commit('move main')
    const error = throwsWith(1, () => preflight(repo.path, 'run-1', 'main'))
    assert.match(error.message, /already based on/)
  })

  test('refuses a dirty working tree', () => {
    repo.write('dirty.txt', 'uncommitted\n')
    const error = throwsWith(1, () => preflight(repo.path, 'run-dirty', 'main'))
    assert.match(error.message, /uncommitted/)
    assert.deepEqual(error.detail['dirty'], ['dirty.txt'])
    repo.git('clean', '-fd')
  })

  test('refuses an unknown base ref', () => {
    throwsWith(1, () => preflight(repo.path, 'run-2', 'no-such-branch'))
  })

  test('refuses a run id that would escape the ref namespace', () => {
    throwsWith(1, () => preflight(repo.path, '../../heads/main', 'main'))
  })
})

describe('stage', () => {
  let repo: Fixture
  before(() => {
    repo = makeRepo()
    taskBranch(repo, 'task-a', 'apps/api/a.ts', 'export const a = 1\n')
    preflight(repo.path, 'run-1', 'main')
  })
  after(() => repo.cleanup())

  test('copies the branch head without moving the branch', () => {
    const before = repo.sha('task-a')
    const result = stage(repo.path, 'run-1', 'task-a', 'task-a')
    assert.equal(result.sha, before)
    assert.equal(repo.sha('task-a'), before, 'task branch must not be rewritten')
    assert.equal(tryRevParse(repo.path, stagingRef('run-1', 'task-a')), before)
    assert.equal(result.commits.length, 1)
  })

  test('refuses a branch with no commits on top of base', () => {
    repo.branch('empty-branch', 'main')
    const error = throwsWith(1, () => stage(repo.path, 'run-1', 'empty', 'empty-branch'))
    assert.match(error.message, /no commits/)
  })

  test('refuses a branch that does not descend from the run base', () => {
    repo.git('checkout', '--detach', 'main')
    repo.write('orphan.txt', 'x\n')
    repo.commit('unrelated root')
    repo.git('branch', 'sideways')
    repo.checkout('main')
    // move the run base forward so `sideways` is no longer a descendant
    preflight(repo.path, 'run-3', 'sideways')
    const error = throwsWith(1, () => stage(repo.path, 'run-3', 'task-a', 'task-a'))
    assert.match(error.message, /not based on/)
  })

  test('refuses before preflight', () => {
    throwsWith(1, () => stage(repo.path, 'run-unknown', 'task-a', 'task-a'))
  })
})

describe('scope-check', () => {
  let repo: Fixture
  before(() => {
    repo = makeRepo()
    taskBranch(repo, 'task-a', 'apps/api/a.ts', 'export const a = 1\n')
    repo.git('checkout', '-b', 'task-wide', 'main')
    repo.write('apps/api/b.ts', 'export const b = 1\n')
    repo.write('apps/web/leak.ts', 'export const leak = 1\n')
    repo.commit('feat: touches two apps')
    repo.checkout('main')
    preflight(repo.path, 'run-1', 'main')
  })
  after(() => repo.cleanup())

  test('accepts changes inside the write scope', () => {
    const result = scopeCheck(repo.path, 'run-1', 'task-a', ['apps/api/**'])
    assert.deepEqual(result.changed, ['apps/api/a.ts'])
  })

  test('reports files outside the write scope', () => {
    const error = throwsWith(1, () => scopeCheck(repo.path, 'run-1', 'task-wide', ['apps/api/**']))
    assert.deepEqual(error.detail['outside'], ['apps/web/leak.ts'])
  })

  test('treats an untouched branch as a failure', () => {
    repo.branch('untouched', 'main')
    const error = throwsWith(1, () => scopeCheck(repo.path, 'run-1', 'untouched', ['**']))
    assert.match(error.message, /changed no files/)
  })

  test('requires at least one glob', () => {
    throwsWith(1, () => scopeCheck(repo.path, 'run-1', 'task-a', []))
  })
})

describe('preview', () => {
  let repo: Fixture
  before(() => {
    repo = makeRepo()
    taskBranch(repo, 'task-a', 'apps/api/a.ts', 'export const a = 1\n')
    taskBranch(repo, 'task-b', 'apps/web/b.ts', 'export const b = 1\n')
    preflight(repo.path, 'run-1', 'main')
    stage(repo.path, 'run-1', 'task-a', 'task-a')
    stage(repo.path, 'run-1', 'task-b', 'task-b')
  })
  after(() => repo.cleanup())

  test('builds a linear candidate in the requested order', () => {
    const result = preview(repo.path, 'run-1', ['task-a', 'task-b'])
    assert.equal(result.steps.length, 2)
    assert.deepEqual(result.steps.map((s) => s.taskId), ['task-a', 'task-b'])

    const log = repo.git('log', '--format=%s', `${result.baseSha}..${result.head}`)
    assert.deepEqual(log.split('\n'), ['feat: task-b', 'feat: task-a'])
    assert.equal(repo.git('rev-list', '--merges', `${result.baseSha}..${result.head}`), '')
  })

  test('does not move the real task branches', () => {
    const a = repo.sha('task-a')
    const b = repo.sha('task-b')
    preview(repo.path, 'run-1', ['task-a', 'task-b'])
    assert.equal(repo.sha('task-a'), a)
    assert.equal(repo.sha('task-b'), b)
  })

  test('is idempotent', () => {
    const first = preview(repo.path, 'run-1', ['task-a', 'task-b'])
    const second = preview(repo.path, 'run-1', ['task-a', 'task-b'])
    assert.equal(first.head, second.head)
  })

  test('leaves no preview worktree behind', () => {
    preview(repo.path, 'run-1', ['task-a', 'task-b'])
    assert.deepEqual(worktreePaths(repo), [])
  })

  test('reports the conflicting task and files', () => {
    taskBranch(repo, 'clash-1', 'shared.ts', 'export const v = 1\n')
    taskBranch(repo, 'clash-2', 'shared.ts', 'export const v = 2\n')
    preflight(repo.path, 'run-clash', 'main')
    stage(repo.path, 'run-clash', 'clash-1', 'clash-1')
    stage(repo.path, 'run-clash', 'clash-2', 'clash-2')

    const error = throwsWith(2, () => preview(repo.path, 'run-clash', ['clash-1', 'clash-2']))
    assert.equal(error.detail['taskId'], 'clash-2')
    assert.deepEqual(error.detail['files'], ['shared.ts'])
    assert.deepEqual(error.detail['appliedBefore'], ['clash-1'])
    assert.deepEqual(worktreePaths(repo), [], 'a failed preview must still clean up')
  })

  test('refuses an unstaged task', () => {
    throwsWith(1, () => preview(repo.path, 'run-1', ['task-a', 'nope']))
  })

  test('refuses a duplicated task in the order', () => {
    throwsWith(1, () => preview(repo.path, 'run-1', ['task-a', 'task-a']))
  })
})

describe('apply', () => {
  let repo: Fixture
  before(() => {
    repo = makeRepo()
    taskBranch(repo, 'task-a', 'apps/api/a.ts', 'export const a = 1\n')
    taskBranch(repo, 'task-b', 'apps/web/b.ts', 'export const b = 1\n')
    preflight(repo.path, 'run-1', 'main')
    stage(repo.path, 'run-1', 'task-a', 'task-a')
    stage(repo.path, 'run-1', 'task-b', 'task-b')
    preview(repo.path, 'run-1', ['task-a', 'task-b'])
  })
  after(() => repo.cleanup())

  test('refuses when HEAD is not on the base branch', () => {
    repo.checkout('task-a')
    const error = throwsWith(1, () => apply(repo.path, 'run-1', 'main'))
    assert.match(error.message, /check out main/)
    repo.checkout('main')
  })

  test('fast-forwards the base branch', () => {
    const before = repo.sha('main')
    const result = apply(repo.path, 'run-1', 'main')
    assert.equal(result.from, before)
    assert.equal(repo.sha('main'), result.to)
    assert.equal(repo.git('log', '--format=%s', `${before}..HEAD`).split('\n').length, 2)
  })

  test('archives staging refs and drops the candidate', () => {
    assert.equal(tryRevParse(repo.path, stagingRef('run-1', 'task-a')), null)
    assert.notEqual(tryRevParse(repo.path, archiveRef('run-1', 'task-a')), null)
    assert.equal(tryRevParse(repo.path, integrationRef('run-1')), null)
  })

  test('refuses when the base moved since preview', () => {
    const repo2 = makeRepo()
    try {
      taskBranch(repo2, 'task-a', 'apps/api/a.ts', 'export const a = 1\n')
      preflight(repo2.path, 'run-1', 'main')
      stage(repo2.path, 'run-1', 'task-a', 'task-a')
      preview(repo2.path, 'run-1', ['task-a'])

      repo2.write('drift.txt', 'someone else pushed\n')
      repo2.commit('unrelated work on main')

      const error = throwsWith(1, () => apply(repo2.path, 'run-1', 'main'))
      assert.match(error.message, /moved from/)
    } finally {
      repo2.cleanup()
    }
  })

  test('refuses without a preview', () => {
    const repo2 = makeRepo()
    try {
      preflight(repo2.path, 'run-x', 'main')
      const error = throwsWith(1, () => apply(repo2.path, 'run-x', 'main'))
      assert.match(error.message, /no integration candidate/)
    } finally {
      repo2.cleanup()
    }
  })
})
