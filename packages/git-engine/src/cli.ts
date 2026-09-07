#!/usr/bin/env node
import { parseArgs, type ParseArgsConfig } from 'node:util'
import { OmijaError, userError } from './error.ts'
import { isRepo } from './git.ts'
import { apply } from './commands/apply.ts'
import { preflight } from './commands/preflight.ts'
import { preview } from './commands/preview.ts'
import { scopeCheck } from './commands/scope-check.ts'
import { stage } from './commands/stage.ts'

const USAGE = `omija — integration engine for worktree-native agent orchestration

  omija preflight   --run <id> --base <ref>
  omija stage       --run <id> --task <id> --branch <branch>
  omija scope-check --run <id> --branch <branch> --allow <glob> [--allow <glob>...]
  omija preview     --run <id> --order <task-id,task-id,...>
  omija apply       --run <id> --base <ref>

Every command accepts --repo <path> (default: current directory).
Machine-readable JSON goes to stdout; human-readable text goes to stderr.

Exit codes: 0 ok · 1 you have to fix something · 2 conflict · 3 internal failure
`

type Options = Record<string, string | string[] | undefined>

const SCHEMA: Record<string, ParseArgsConfig['options']> = {
  preflight: {
    repo: { type: 'string' },
    run: { type: 'string' },
    base: { type: 'string' },
  },
  stage: {
    repo: { type: 'string' },
    run: { type: 'string' },
    task: { type: 'string' },
    branch: { type: 'string' },
  },
  'scope-check': {
    repo: { type: 'string' },
    run: { type: 'string' },
    branch: { type: 'string' },
    allow: { type: 'string', multiple: true },
  },
  preview: {
    repo: { type: 'string' },
    run: { type: 'string' },
    order: { type: 'string' },
  },
  apply: {
    repo: { type: 'string' },
    run: { type: 'string' },
    base: { type: 'string' },
  },
}

function required(options: Options, name: string): string {
  const value = options[name]
  if (typeof value !== 'string' || value === '') {
    throw userError(`--${name} is required`)
  }
  return value
}

function list(options: Options, name: string): string[] {
  const value = options[name]
  if (value === undefined) return []
  return Array.isArray(value) ? value : [value]
}

function run(command: string, argv: string[]): unknown {
  const schema = SCHEMA[command]
  if (schema === undefined) {
    throw userError(`unknown command ${JSON.stringify(command)}`)
  }

  let options: Options
  try {
    options = parseArgs({ args: argv, options: schema, allowPositionals: false }).values as Options
  } catch (cause) {
    throw userError(cause instanceof Error ? cause.message : String(cause))
  }

  const repo = typeof options['repo'] === 'string' ? options['repo'] : process.cwd()
  if (!isRepo(repo)) {
    throw userError(`${repo} is not a git repository`, { repo })
  }

  switch (command) {
    case 'preflight':
      return preflight(repo, required(options, 'run'), required(options, 'base'))
    case 'stage':
      return stage(
        repo,
        required(options, 'run'),
        required(options, 'task'),
        required(options, 'branch'),
      )
    case 'scope-check':
      return scopeCheck(
        repo,
        required(options, 'run'),
        required(options, 'branch'),
        list(options, 'allow'),
      )
    case 'preview':
      return preview(
        repo,
        required(options, 'run'),
        required(options, 'order').split(',').map((s) => s.trim()).filter((s) => s !== ''),
      )
    case 'apply':
      return apply(repo, required(options, 'run'), required(options, 'base'))
    default:
      throw userError(`unknown command ${JSON.stringify(command)}`)
  }
}

function main(argv: string[]): number {
  const command = argv[0]
  if (command === undefined || command === '--help' || command === '-h' || command === 'help') {
    process.stderr.write(USAGE)
    return command === undefined ? 1 : 0
  }

  try {
    const result = run(command, argv.slice(1))
    process.stdout.write(`${JSON.stringify({ ok: true, ...(result as object) }, null, 2)}\n`)
    return 0
  } catch (cause) {
    if (cause instanceof OmijaError) {
      process.stderr.write(`omija: ${cause.message}\n`)
      process.stdout.write(
        `${JSON.stringify({ ok: false, error: cause.message, ...cause.detail }, null, 2)}\n`,
      )
      return cause.code
    }
    throw cause
  }
}

process.exitCode = main(process.argv.slice(2))
