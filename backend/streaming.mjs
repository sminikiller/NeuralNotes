// Incremental display of the JSON text field. Only a completed, validated result
// is authoritative; partial text must never be persisted as a study artifact.
export function partialText(raw) {
  const match = /"text"\s*:\s*"/.exec(raw);
  if (!match) return '';
  let result = '';
  for (let i = match.index + match[0].length; i < raw.length; i++) {
    const ch = raw[i];
    if (ch === '"') break;
    if (ch !== '\\') { result += ch; continue; }
    const escape = raw[++i];
    if (!escape) break;
    if (escape === 'u') {
      const hex = raw.slice(i + 1, i + 5); if (!/^[\da-f]{4}$/i.test(hex)) break;
      result += String.fromCharCode(parseInt(hex, 16)); i += 4;
    } else {
      const escapes = { '"': '"', '\\': '\\', '/': '/', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t' };
      if (!(escape in escapes)) break; result += escapes[escape];
    }
  }
  if (/[\uD800-\uDBFF]$/.test(result)) result = result.slice(0, -1);
  return result;
}

export async function* responseEvents(response) {
  if (!response.body) throw new Error('Empty event stream');
  const decoder = new TextDecoder(); let buffer = '', size = 0;
  for await (const chunk of response.body) {
    size += chunk.length; if (size > 2 * 1024 * 1024) throw new Error('Event stream too large');
    buffer += decoder.decode(chunk, { stream: true });
    buffer = buffer.replace(/\r\n/g, '\n');
    let end;
    while ((end = buffer.indexOf('\n\n')) >= 0) {
      const frame = buffer.slice(0, end); buffer = buffer.slice(end + 2);
      const data = frame.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
      if (data && data !== '[DONE]') yield JSON.parse(data);
    }
  }
  if (buffer.trim() && buffer.trim() !== 'data: [DONE]') throw new Error('Truncated event stream');
}
