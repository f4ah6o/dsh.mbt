import { parentPort, workerData } from 'node:worker_threads';

try {
  const pattern = new RegExp(workerData.pattern, workerData.ignoreCase ? 'i' : '');
  parentPort.on('message', ({ id, text, limit }) => {
    const matches = [];
    const lines = text.split('\n');
    for (let index = 0; index < lines.length && matches.length < limit; index++) {
      if (pattern.test(lines[index])) matches.push({ line: index + 1, text: lines[index].slice(0, 2000) });
    }
    parentPort.postMessage({ id, matches });
  });
  parentPort.postMessage({ ready: true });
} catch (error) {
  parentPort.postMessage({ error: error.message });
}
