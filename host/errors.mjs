export class HostError extends Error {
  constructor(message, { status = 400, code = 'host_error', cause } = {}) {
    super(message, { cause });
    this.name = 'HostError';
    this.status = status;
    this.code = code;
  }
}

export function messageOf(error) {
  return error instanceof Error ? error.message : String(error);
}

export function parseEnvelope(value, context = 'MoonBit') {
  let parsed;
  try {
    parsed = typeof value === 'string' ? JSON.parse(value) : value;
  } catch (cause) {
    throw new HostError(`${context} returned invalid JSON`, { status: 500, cause });
  }
  if (!parsed || typeof parsed !== 'object' || typeof parsed.ok !== 'boolean') {
    throw new HostError(`${context} returned an invalid result envelope`, { status: 500 });
  }
  return parsed;
}

export function unwrap(value, context) {
  const response = parseEnvelope(value, context);
  if (!response.ok) throw new HostError(typeof response.error === 'string' ? response.error : JSON.stringify(response.error));
  return response.result;
}

export function checkAbort(signal) {
  if (signal?.aborted) throw signal.reason ?? new DOMException('Operation aborted', 'AbortError');
}
