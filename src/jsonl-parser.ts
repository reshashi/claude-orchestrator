/**
 * JSONL Parser for Claude --print output
 *
 * Parses the JSON stream output from `claude --print --output-format stream-json`
 * and extracts meaningful events.
 */

import type { ClaudeMessage, ContentBlock } from './types.js';

/**
 * Parse a single JSONL line from Claude output
 */
export function parseJsonlLine(line: string): ClaudeMessage | null {
  const trimmed = line.trim();
  if (!trimmed) return null;

  try {
    return JSON.parse(trimmed) as ClaudeMessage;
  } catch {
    // Not valid JSON - could be non-JSON output
    return null;
  }
}

/**
 * Create a streaming JSONL parser that processes lines incrementally
 */
export function createJsonlParser(
  onMessage: (message: ClaudeMessage) => void,
  onError?: (error: Error, rawLine: string) => void
): {
  write: (chunk: string) => void;
  flush: () => void;
} {
  let buffer = '';

  return {
    write(chunk: string): void {
      buffer += chunk;

      // Process complete lines
      const lines = buffer.split('\n');
      // Keep the last incomplete line in the buffer
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          const parsed = JSON.parse(line) as ClaudeMessage;
          onMessage(parsed);
        } catch (err) {
          onError?.(err instanceof Error ? err : new Error(String(err)), line);
        }
      }
    },

    flush(): void {
      // Process any remaining data in buffer
      if (buffer.trim()) {
        try {
          const parsed = JSON.parse(buffer) as ClaudeMessage;
          onMessage(parsed);
        } catch (err) {
          onError?.(err instanceof Error ? err : new Error(String(err)), buffer);
        }
        buffer = '';
      }
    },
  };
}

/**
 * Extract text content from a Claude message
 */
export function extractText(message: ClaudeMessage): string {
  if (message.type !== 'assistant' || !message.message?.content) {
    return '';
  }

  return message.message.content
    .filter((block): block is ContentBlock & { text: string } =>
      block.type === 'text' && typeof block.text === 'string'
    )
    .map(block => block.text)
    .join('\n');
}

/**
 * Check if a message contains tool use
 */
export function hasToolUse(message: ClaudeMessage): boolean {
  if (message.type !== 'assistant' || !message.message?.content) {
    return false;
  }

  return message.message.content.some(block => block.type === 'tool_use');
}

/**
 * Get tool names from a message
 */
export function getToolNames(message: ClaudeMessage): string[] {
  if (message.type !== 'assistant' || !message.message?.content) {
    return [];
  }

  return message.message.content
    .filter((block): block is ContentBlock & { name: string } =>
      block.type === 'tool_use' && typeof block.name === 'string'
    )
    .map(block => block.name);
}

/**
 * Check if message indicates completion
 */
export function isComplete(message: ClaudeMessage): boolean {
  // Result message indicates Claude has finished
  if (message.type === 'result') {
    return true;
  }

  // Check for stop_reason in assistant message
  if (message.type === 'assistant' && message.message?.stop_reason === 'end_turn') {
    return true;
  }

  return false;
}

/**
 * Extract PR URL from message text
 */
export function extractPrUrl(message: ClaudeMessage): string | null {
  const text = extractText(message);

  // Match GitHub PR URLs
  const prUrlPattern = /https:\/\/github\.com\/[^/]+\/[^/]+\/pull\/(\d+)/;
  const match = text.match(prUrlPattern);

  return match ? match[0] : null;
}

/**
 * Extract PR number from URL or message
 */
export function extractPrNumber(message: ClaudeMessage): number | null {
  const url = extractPrUrl(message);
  if (!url) return null;

  const match = url.match(/\/pull\/(\d+)/);
  return match ? parseInt(match[1], 10) : null;
}

/**
 * Check if message indicates an error from Claude API
 */
export function isApiError(message: ClaudeMessage): boolean {
  // Check result message for error
  if (message.type === 'result' && message.result?.is_error) {
    return true;
  }

  // Check text content for error patterns
  const text = extractText(message);
  const errorPatterns = [
    /API.*error/i,
    /rate.*limit/i,
    /ECONNREFUSED/i,
    /connection.*failed/i,
    /Claude.*error/i,
  ];

  return errorPatterns.some(pattern => pattern.test(text));
}

/**
 * Check if message indicates QA review completion
 */
export function isReviewComplete(message: ClaudeMessage): 'passed' | 'failed' | null {
  const text = extractText(message);

  // QA Guardian output patterns
  if (/RESULT:.*FAIL/i.test(text)) {
    return 'failed';
  }

  if (/RESULT:.*(PASS|CONDITIONAL PASS)/i.test(text) || /QA GUARDIAN REVIEW/i.test(text)) {
    return 'passed';
  }

  return null;
}

/**
 * Parse accumulated output to find PR information
 */
export function parsePrFromOutput(output: string): { number: number; url: string } | null {
  const urlPattern = /https:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)/;
  const match = output.match(urlPattern);

  if (match) {
    return {
      number: parseInt(match[3], 10),
      url: match[0],
    };
  }

  return null;
}
