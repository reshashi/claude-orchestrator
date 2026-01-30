/**
 * CLI Interface
 *
 * Command-line interface for the orchestrator.
 */

import { Command } from 'commander';
import * as path from 'node:path';
import * as os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import * as fs from 'node:fs/promises';

import { Orchestrator } from './orchestrator.js';
import { StateManager } from './state-manager.js';
import { createLogger } from './logger.js';
import { getStateEmoji, getStateDescription } from './state-machine.js';
import { startServer } from './server.js';

const execFileAsync = promisify(execFile);

const VERSION = '3.1.0';

export function createCli(): Command {
  const program = new Command();

  program
    .name('claude-orchestrator')
    .description('Cross-platform Claude Code worker orchestration')
    .version(VERSION);

  // Spawn command
  program
    .command('spawn <name> <task>')
    .description('Create a worktree and spawn a Claude worker')
    .option('-r, --repo <name>', 'Repository name (defaults to current directory)')
    .option('--no-start', 'Create worktree only, do not start worker')
    .action(async (name: string, task: string, options) => {
      const logger = createLogger({ level: 'info' });

      try {
        // Get repo name
        const repoName = options.repo ?? path.basename(process.cwd());
        const worktreesDir = path.join(os.homedir(), '.worktrees');
        const worktreePath = path.join(worktreesDir, repoName, name);
        const branchName = `feature/${name}`;

        // Check if worktree already exists
        try {
          await fs.access(worktreePath);
          console.error(`Error: Worktree already exists at ${worktreePath}`);
          process.exit(1);
        } catch {
          // Good - doesn't exist
        }

        // Create worktree
        console.log(`Creating worktree for ${name}...`);
        await fs.mkdir(path.dirname(worktreePath), { recursive: true });

        try {
          await execFileAsync('git', [
            'worktree', 'add',
            '-b', branchName,
            worktreePath,
            'HEAD',
          ], { cwd: process.cwd() });
        } catch (err) {
          console.error(`Failed to create worktree: ${err}`);
          process.exit(1);
        }

        // Create WORKER_CLAUDE.md with task
        const workerClaudeMd = `# Worker Task: ${name}

## Your Task
${task}

## Important
- Read the main CLAUDE.md for coding standards
- Run \`npm run type-check && npm run lint && npm run test\` before creating a PR
- Only create a PR if all checks pass
- Use conventional commit format

## Files You Own
This worker owns all files related to this task. Coordinate with other workers if you need to modify shared files.
`;

        await fs.writeFile(
          path.join(worktreePath, 'WORKER_CLAUDE.md'),
          workerClaudeMd,
          'utf-8'
        );

        // Log to session file
        const sessionsFile = path.join(os.homedir(), '.claude', 'active-sessions.log');
        await fs.mkdir(path.dirname(sessionsFile), { recursive: true });
        await fs.appendFile(
          sessionsFile,
          `${name}|${branchName}|${worktreePath}|${new Date().toISOString()}|${task}\n`,
          'utf-8'
        );

        if (options.start === false) {
          console.log(`\nWorktree created at ${worktreePath}`);
          console.log(`Branch: ${branchName}`);
          console.log(`\nTo start the worker manually:`);
          console.log(`  cd ${worktreePath} && claude`);
          return;
        }

        // Start worker
        console.log(`Starting Claude worker...`);

        const orchestrator = new Orchestrator({ logger });
        await orchestrator.initialize();

        const worker = await orchestrator.spawn(name, task, repoName);

        console.log(`\nWorker '${name}' spawned!`);
        console.log(`  Path: ${worktreePath}`);
        console.log(`  Branch: ${branchName}`);
        console.log(`  PID: ${worker.pid}`);
        console.log(`\nThe worker is running in the background.`);
        console.log(`Use 'claude-orchestrator status ${name}' to check progress.`);
        console.log(`Use 'claude-orchestrator read ${name}' to see output.`);

        // Keep process running to maintain worker
        orchestrator.start();

        // Handle shutdown
        process.on('SIGINT', async () => {
          console.log('\nShutting down...');
          orchestrator.stop();
          await orchestrator.stopWorker(name);
          process.exit(0);
        });

      } catch (err) {
        console.error(`Error: ${err}`);
        process.exit(1);
      }
    });

  // List command
  program
    .command('list')
    .alias('ls')
    .description('List all workers')
    .option('-a, --all', 'Include completed workers')
    .action(async (options) => {
      const logger = createLogger({ level: 'error' });
      const stateManager = new StateManager({
        workersDir: path.join(os.homedir(), '.claude', 'workers'),
        logger,
      });

      await stateManager.initialize();
      const workers = await stateManager.loadAllWorkerStates();

      if (workers.length === 0) {
        console.log('No workers found.');
        return;
      }

      const activeStates = ['SPAWNING', 'INITIALIZING', 'WORKING', 'PR_OPEN', 'REVIEWING', 'MERGING'];

      const filtered = options.all
        ? workers
        : workers.filter(w => activeStates.includes(w.state));

      if (filtered.length === 0) {
        console.log('No active workers. Use --all to see completed workers.');
        return;
      }

      console.log('\nWorkers:');
      console.log('─'.repeat(80));

      for (const worker of filtered) {
        const emoji = getStateEmoji(worker.state);
        const prInfo = worker.prNumber ? ` PR #${worker.prNumber}` : '';
        console.log(`${emoji} ${worker.id.padEnd(20)} ${worker.state.padEnd(12)}${prInfo}`);
        console.log(`   Path: ${worker.config.worktreePath}`);
        console.log(`   Task: ${worker.config.task.substring(0, 60)}...`);
        console.log('');
      }
    });

  // Status command
  program
    .command('status [worker-id]')
    .description('Get detailed status of a worker (or all workers)')
    .action(async (workerId?: string) => {
      const logger = createLogger({ level: 'error' });
      const stateManager = new StateManager({
        workersDir: path.join(os.homedir(), '.claude', 'workers'),
        logger,
      });

      await stateManager.initialize();

      if (workerId) {
        const state = await stateManager.loadWorkerState(workerId);
        if (!state) {
          console.error(`Worker '${workerId}' not found.`);
          process.exit(1);
        }

        console.log(`\n${getStateEmoji(state.state)} Worker: ${state.id}`);
        console.log('─'.repeat(50));
        console.log(`State:       ${state.state}`);
        console.log(`Description: ${getStateDescription(state.state)}`);
        console.log(`Branch:      ${state.config.branchName}`);
        console.log(`Path:        ${state.config.worktreePath}`);
        console.log(`Task:        ${state.config.task}`);
        console.log(`Last Active: ${state.lastActivity}`);

        if (state.prNumber) {
          console.log(`PR:          #${state.prNumber} - ${state.prUrl}`);
        }
        if (state.reviewStatus !== 'none') {
          console.log(`Review:      ${state.reviewStatus}`);
        }
        if (state.agentsRun.length > 0) {
          console.log(`Agents Run:  ${state.agentsRun.join(', ')}`);
        }
        if (state.error) {
          console.log(`Error:       ${state.error}`);
        }
      } else {
        // Summary of all workers
        const workers = await stateManager.loadAllWorkerStates();

        const summary = {
          total: workers.length,
          working: workers.filter(w => w.state === 'WORKING').length,
          prOpen: workers.filter(w => w.state === 'PR_OPEN').length,
          reviewing: workers.filter(w => w.state === 'REVIEWING').length,
          merged: workers.filter(w => w.state === 'MERGED').length,
          error: workers.filter(w => w.state === 'ERROR').length,
        };

        console.log('\nOrchestrator Status');
        console.log('─'.repeat(40));
        console.log(`Total Workers: ${summary.total}`);
        console.log(`Working:       ${summary.working}`);
        console.log(`PR Open:       ${summary.prOpen}`);
        console.log(`Reviewing:     ${summary.reviewing}`);
        console.log(`Merged:        ${summary.merged}`);
        console.log(`Errors:        ${summary.error}`);
      }
    });

  // Read command
  program
    .command('read <worker-id>')
    .description('Read output from a worker')
    .option('-n, --lines <number>', 'Number of lines to show', '50')
    .action(async (workerId: string, options) => {
      const logger = createLogger({ level: 'error' });
      const stateManager = new StateManager({
        workersDir: path.join(os.homedir(), '.claude', 'workers'),
        logger,
      });

      await stateManager.initialize();
      const lines = await stateManager.readOutputLog(workerId, parseInt(options.lines, 10));

      if (lines.length === 0) {
        console.log('No output found for this worker.');
        return;
      }

      console.log(lines.join('\n'));
    });

  // Send command
  program
    .command('send <worker-id> <message>')
    .description('Send a message to a worker')
    .action(async (workerId: string, message: string) => {
      const logger = createLogger({ level: 'info' });
      const orchestrator = new Orchestrator({ logger });
      await orchestrator.initialize();

      try {
        await orchestrator.sendMessage(workerId, message);
        console.log(`Message sent to ${workerId}`);
      } catch (err) {
        console.error(`Failed to send message: ${err}`);
        process.exit(1);
      }
    });

  // Stop command
  program
    .command('stop <worker-id>')
    .description('Stop a worker')
    .action(async (workerId: string) => {
      const logger = createLogger({ level: 'info' });
      const orchestrator = new Orchestrator({ logger });
      await orchestrator.initialize();

      try {
        await orchestrator.stopWorker(workerId);
        console.log(`Worker ${workerId} stopped`);
      } catch (err) {
        console.error(`Failed to stop worker: ${err}`);
        process.exit(1);
      }
    });

  // Merge command
  program
    .command('merge <worker-id>')
    .description('Manually trigger merge for a worker')
    .action(async (workerId: string) => {
      const logger = createLogger({ level: 'info' });
      const orchestrator = new Orchestrator({ logger });
      await orchestrator.initialize();

      try {
        const success = await orchestrator.triggerMerge(workerId);
        if (success) {
          console.log(`PR for ${workerId} merged successfully`);
        } else {
          console.error(`Failed to merge PR for ${workerId}`);
          process.exit(1);
        }
      } catch (err) {
        console.error(`Error: ${err}`);
        process.exit(1);
      }
    });

  // Cleanup command
  program
    .command('cleanup [worker-id]')
    .description('Clean up completed workers')
    .option('--force', 'Remove all non-running workers')
    .action(async (workerId?: string, _options?: { force?: boolean }) => {
      const logger = createLogger({ level: 'info' });
      const orchestrator = new Orchestrator({ logger });
      await orchestrator.initialize();

      try {
        await orchestrator.cleanup(workerId);
        console.log(workerId ? `Cleaned up ${workerId}` : 'Cleanup complete');
      } catch (err) {
        console.error(`Error: ${err}`);
        process.exit(1);
      }
    });

  // Loop command (runs the orchestrator loop)
  program
    .command('loop')
    .description('Run the orchestrator monitoring loop')
    .option('--poll <ms>', 'Poll interval in milliseconds', '5000')
    .action(async (options) => {
      const logger = createLogger({
        level: 'info',
        logFile: path.join(os.homedir(), '.claude', 'orchestrator.log'),
      });

      const orchestrator = new Orchestrator({
        logger,
        config: {
          pollIntervalMs: parseInt(options.poll, 10),
        },
      });

      await orchestrator.initialize();
      orchestrator.start();

      console.log('Orchestrator loop started. Press Ctrl+C to stop.');

      process.on('SIGINT', () => {
        console.log('\nStopping orchestrator...');
        orchestrator.stop();
        process.exit(0);
      });

      // Keep process running
      await new Promise(() => {});
    });

  // Serve command (runs HTTP/WebSocket API server)
  program
    .command('serve')
    .description('Start the HTTP/WebSocket API server for Moltbot integration')
    .option('-p, --port <number>', 'Port to listen on', '3001')
    .option('-H, --host <string>', 'Host to bind to', 'localhost')
    .option('--poll <ms>', 'Poll interval for orchestrator loop', '5000')
    .action(async (options) => {
      const logger = createLogger({
        level: 'info',
        logFile: path.join(os.homedir(), '.claude', 'orchestrator.log'),
      });

      const port = parseInt(options.port, 10);
      const host = options.host;

      // Create and initialize orchestrator
      const orchestrator = new Orchestrator({
        logger,
        config: {
          pollIntervalMs: parseInt(options.poll, 10),
        },
      });

      await orchestrator.initialize();

      // Start the orchestrator loop
      orchestrator.start();

      // Start the HTTP server
      try {
        const server = await startServer({
          port,
          host,
          logger,
          orchestrator,
        });

        console.log('');
        console.log('Claude Orchestrator API Server');
        console.log('══════════════════════════════════════════════');
        console.log(`HTTP API:    http://${host}:${port}/api`);
        console.log(`WebSocket:   ws://${host}:${port}/ws/status`);
        console.log(`Health:      http://${host}:${port}/api/health`);
        console.log('');
        console.log('Endpoints:');
        console.log('  GET    /api/workers          - List all workers');
        console.log('  GET    /api/workers/:id      - Get worker status');
        console.log('  POST   /api/workers          - Spawn new worker');
        console.log('  POST   /api/workers/:id/send - Send message');
        console.log('  POST   /api/workers/:id/stop - Stop worker');
        console.log('  POST   /api/workers/:id/merge - Merge PR');
        console.log('  DELETE /api/workers/:id      - Cleanup worker');
        console.log('  WS     /ws/status            - Real-time updates');
        console.log('');
        console.log('Press Ctrl+C to stop.');

        process.on('SIGINT', async () => {
          console.log('\nShutting down...');
          orchestrator.stop();
          await server.close();
          process.exit(0);
        });

        // Keep process running
        await new Promise(() => {});
      } catch (err) {
        console.error(`Failed to start server: ${err}`);
        process.exit(1);
      }
    });

  return program;
}
