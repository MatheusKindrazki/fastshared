/**
 * Small Markdown renderer for the publications legal drafts.
 * The drafts are authored text, escaped before any tag is emitted.
 */

const LIST_RE = /^(\s*)([-*]|\d+\.)\s+(.*)$/;

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function sanitizeHref(href: string): string {
  const trimmed = href.trim();
  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) return trimmed;
  try {
    const url = new URL(trimmed);
    if (url.protocol === 'https:' || url.protocol === 'http:' || url.protocol === 'mailto:') {
      return url.toString();
    }
  } catch {
    /* reject anything that is not an absolute http(s) or mailto URL */
  }
  return '#';
}

function inlinePlain(raw: string): string {
  let html = escapeHtml(raw);
  html = html.replace(/`([^`]+)`/g, (_match, code: string) => `<code>${code}</code>`);
  html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>');
  return html;
}

function inline(raw: string): string {
  const anchors: string[] = [];
  const marked = raw.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_match, text: string, href: string) => {
    const token = `\u0000L${anchors.length}\u0000`;
    anchors.push(`<a href="${escapeHtml(sanitizeHref(href))}">${inlinePlain(text)}</a>`);
    return token;
  });
  let html = inlinePlain(marked);
  anchors.forEach((anchor, index) => {
    html = html.replace(`\u0000L${index}\u0000`, anchor);
  });
  return html;
}

function isBlockStart(line: string): boolean {
  return (
    line.startsWith('#') ||
    line.startsWith('>') ||
    line.startsWith('|') ||
    line.trim() === '---' ||
    LIST_RE.test(line)
  );
}

function parseQuote(lines: string[], start: number): { html: string; next: number } {
  const chunks: string[] = [];
  const buf: string[] = [];
  let index = start;
  const flush = () => {
    if (buf.length === 0) return;
    chunks.push(`<p>${inline(buf.join(' '))}</p>`);
    buf.length = 0;
  };
  while (index < lines.length && (lines[index] ?? '').startsWith('>')) {
    const content = (lines[index] ?? '').replace(/^>\s?/, '');
    if (content.trim() === '') flush();
    else buf.push(content);
    index += 1;
  }
  flush();
  return { html: `<blockquote>${chunks.join('')}</blockquote>`, next: index };
}

function parseList(lines: string[], start: number): { html: string; next: number } {
  const base = LIST_RE.exec(lines[start] ?? '')?.[1]?.length ?? 0;
  const ordered = /^\s*\d+\./.test(lines[start] ?? '');
  const items: string[] = [];
  let index = start;

  while (index < lines.length) {
    const line = lines[index] ?? '';
    if (line.trim() === '') {
      const next = lines[index + 1];
      if (next && LIST_RE.test(next) && (LIST_RE.exec(next)?.[1]?.length ?? 0) >= base) {
        index += 1;
        continue;
      }
      break;
    }
    const match = LIST_RE.exec(line);
    if (!match) break;
    const indent = match[1]?.length ?? 0;
    if (indent < base) break;
    if (indent > base) break;
    let item = inline(match[3] ?? '');
    index += 1;
    if (index < lines.length && LIST_RE.test(lines[index] ?? '')) {
      const nestedIndent = LIST_RE.exec(lines[index] ?? '')?.[1]?.length ?? 0;
      if (nestedIndent > base) {
        const nested = parseList(lines, index);
        item += nested.html;
        index = nested.next;
      }
    }
    items.push(`<li>${item}</li>`);
  }

  const tag = ordered ? 'ol' : 'ul';
  return { html: `<${tag}>${items.join('')}</${tag}>`, next: index };
}

function parseTable(lines: string[], start: number): { html: string; next: number } {
  const rows: string[][] = [];
  let index = start;
  while (index < lines.length && (lines[index] ?? '').trim().startsWith('|')) {
    const raw = (lines[index] ?? '')
      .trim()
      .replace(/^\|/, '')
      .replace(/\|$/, '');
    const cells = raw.split('|').map((cell) => cell.trim());
    const divider = cells.every((cell) => /^:?-+:?$/.test(cell));
    if (!divider) rows.push(cells);
    index += 1;
  }
  const headers = rows[0] ?? [];
  const body = rows.slice(1);
  const head = `<thead><tr>${headers.map((cell) => `<th scope="col">${inline(cell)}</th>`).join('')}</tr></thead>`;
  const bodyHtml = body
    .map((row) => {
      const cells = row
        .map((cell, cellIndex) => {
          const label = escapeHtml(headers[cellIndex] ?? '');
          return `<td data-label="${label}">${inline(cell)}</td>`;
        })
        .join('');
      return `<tr>${cells}</tr>`;
    })
    .join('');
  return {
    html: `<div class="legal-table"><table>${head}<tbody>${bodyHtml}</tbody></table></div>`,
    next: index,
  };
}

/** Drop the authoring banner. Keep the policy text, including its draft effective date. */
export function prepareLegalMarkdown(source: string): string {
  const lines = source.replace(/\r\n/g, '\n').split('\n');
  let start = 0;
  if ((lines[0] ?? '').startsWith('# DRAFT')) {
    start = 1;
    while (start < lines.length && (lines[start] ?? '').trim() === '') start += 1;
  }
  const kept: string[] = [];
  for (let index = start; index < lines.length; index += 1) {
    const line = lines[index] ?? '';
    if (/^> \*\*Summary of changes/.test(line)) {
      while (index < lines.length && (lines[index] ?? '').startsWith('>')) index += 1;
      index -= 1;
      continue;
    }
    kept.push(line);
  }
  return kept.join('\n').replaceAll('](/refund-policy/)', '](/refund/)');
}

export function renderLegalMarkdown(source: string): string {
  const lines = prepareLegalMarkdown(source).split('\n');
  const blocks: string[] = [];
  let index = 0;

  while (index < lines.length) {
    const line = lines[index] ?? '';
    if (line.trim() === '') {
      index += 1;
      continue;
    }
    if (line.trim() === '---') {
      index += 1;
      continue;
    }
    if (line.startsWith('### ')) {
      blocks.push(`<h3>${inline(line.slice(4).trim())}</h3>`);
      index += 1;
      continue;
    }
    if (line.startsWith('## ')) {
      blocks.push(`<h2>${inline(line.slice(3).trim())}</h2>`);
      index += 1;
      continue;
    }
    if (line.startsWith('# ')) {
      blocks.push(`<h1>${inline(line.slice(2).trim())}</h1>`);
      index += 1;
      continue;
    }
    if (line.startsWith('>')) {
      const quote = parseQuote(lines, index);
      blocks.push(quote.html);
      index = quote.next;
      continue;
    }
    if (line.trim().startsWith('|')) {
      const table = parseTable(lines, index);
      blocks.push(table.html);
      index = table.next;
      continue;
    }
    if (LIST_RE.test(line)) {
      const list = parseList(lines, index);
      blocks.push(list.html);
      index = list.next;
      continue;
    }

    const buf = [line.trim()];
    index += 1;
    while (index < lines.length) {
      const next = lines[index] ?? '';
      if (next.trim() === '' || isBlockStart(next)) break;
      buf.push(next.trim());
      index += 1;
    }
    blocks.push(`<p>${inline(buf.join(' '))}</p>`);
  }

  return blocks.join('\n');
}
