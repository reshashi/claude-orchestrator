/**
 * Logger
 *
 * Simple console logger with structured output.
 */

import * as fs from 'node:fs';
import * as path from 'node:path';

import type { Logger } from './types.js';

export interface LoggerOptions {
  level: 'debug' | 'info' | 'warn' | 'error';
  logFile?: string;
  useColors?: boolean;
}

const LEVELS = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const COLORS = {
  debug: '\x1b[90m',  // gray
  info: '\x1b[36m',   // cyan
  warn: '\x1b[33m',   // yellow
  error: '\x1b[31m',  // red
  reset: '\x1b[0m',
};

export function createLogger(options: LoggerOptions): Logger {
  const { level, logFile, useColors = true } = options;
  const minLevel = LEVELS[level];

  let logStream: fs.WriteStream | null = null;

  if (logFile) {
    const dir = path.dirname(logFile);
    fs.mkdirSync(dir, { recursive: true });
    logStream = fs.createWriteStream(logFile, { flags: 'a' });
  }

  function log(
    logLevel: 'debug' | 'info' | 'warn' | 'error',
    message: string,
    meta?: Record<string, unknown>
  ): void {
    if (LEVELS[logLevel] < minLevel) return;

    const timestamp = new Date().toISOString();
    const levelStr = logLevel.toUpperCase().padEnd(5);

    // Console output
    const color = useColors ? COLORS[logLevel] : '';
    const reset = useColors ? COLORS.reset : '';

    let consoleMsg = `${color}[${timestamp}] ${levelStr}${reset} ${message}`;
    if (meta && Object.keys(meta).length > 0) {
      consoleMsg += ` ${JSON.stringify(meta)}`;
    }
    console.log(consoleMsg);

    // File output (no colors)
    if (logStream) {
      const fileMsg = JSON.stringify({
        timestamp,
        level: logLevel,
        message,
        ...meta,
      });
      logStream.write(fileMsg + '\n');
    }
  }

  return {
    debug: (message: string, meta?: Record<string, unknown>) => log('debug', message, meta),
    info: (message: string, meta?: Record<string, unknown>) => log('info', message, meta),
    warn: (message: string, meta?: Record<string, unknown>) => log('warn', message, meta),
    error: (message: string, meta?: Record<string, unknown>) => log('error', message, meta),
  };
}

/**
 * Silent logger for testing
 */
export function createSilentLogger(): Logger {
  return {
    debug: () => {},
    info: () => {},
    warn: () => {},
    error: () => {},
  };
}
