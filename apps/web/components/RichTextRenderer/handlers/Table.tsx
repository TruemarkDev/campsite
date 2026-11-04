import { NodeHandler } from '.'

export const Table: NodeHandler = ({ children, node }) => {
  const columnWidths = node.content?.[0]?.content?.flatMap((cell) => {
    const colspan = Number(cell.attrs?.colspan || 1)
    const widths = cell.attrs?.colwidth as number[] | null | undefined

    return widths?.length ? widths : Array<null>(colspan).fill(null)
  })

  return (
    <div className='rich-text-table-wrapper'>
      <table className='rich-text-table'>
        {columnWidths && (
          <colgroup>
            {columnWidths.map((width, index) => (
              // eslint-disable-next-line react/no-array-index-key
              <col key={index} style={width ? { width: `${width}px` } : undefined} />
            ))}
          </colgroup>
        )}
        <tbody>{children}</tbody>
      </table>
    </div>
  )
}

export const TableRow: NodeHandler = ({ children }) => <tr>{children}</tr>

function cellStyle(node: Parameters<NodeHandler>[0]['node']): React.CSSProperties | undefined {
  const style: React.CSSProperties = {}

  if (node.attrs?.align) style.textAlign = node.attrs.align
  if (node.attrs?.backgroundColor) style.backgroundColor = node.attrs.backgroundColor

  return Object.keys(style).length ? style : undefined
}

export const TableHeader: NodeHandler = ({ children, node }) => (
  <th scope='col' style={cellStyle(node)}>
    {children}
  </th>
)

export const TableCell: NodeHandler = ({ children, node }) => <td style={cellStyle(node)}>{children}</td>
