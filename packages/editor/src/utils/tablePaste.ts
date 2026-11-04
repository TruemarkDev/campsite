export interface TablePasteData {
  rows: string[][]
}

function parseDelimitedText(text: string, delimiter: '\t' | ','): string[][] | null {
  const rows: string[][] = []
  let row: string[] = []
  let field = ''
  let quoted = false

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index]

    if (character === '"') {
      if (quoted && text[index + 1] === '"') {
        field += '"'
        index += 1
      } else {
        quoted = !quoted
      }
      continue
    }

    if (character === delimiter && !quoted) {
      row.push(field)
      field = ''
      continue
    }

    if ((character === '\n' || character === '\r') && !quoted) {
      if (character === '\r' && text[index + 1] === '\n') index += 1
      row.push(field)
      rows.push(row)
      row = []
      field = ''
      continue
    }

    field += character
  }

  if (quoted) return null

  row.push(field)
  if (row.length > 1 || row[0] !== '' || rows.length > 0) rows.push(row)

  while (rows.at(-1)?.every((value) => value === '') && rows.length > 1) rows.pop()

  return rows.length ? rows : null
}

export function parseTablePaste(text: string): TablePasteData | null {
  if (!text || (!text.includes('\t') && !text.includes(',') && !text.includes('\n') && !text.includes('\r'))) {
    return null
  }

  const delimiter = text.includes('\t') ? '\t' : ','
  const rows = parseDelimitedText(text, delimiter)

  if (!rows || rows.length === 0) return null

  const width = Math.max(...rows.map((row) => row.length))
  return { rows: rows.map((row) => [...row, ...Array<string>(width - row.length).fill('')]) }
}
